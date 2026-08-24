import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../chat/data/models/chat_user.dart';
import '../models/call_session.dart';
import '../models/incoming_call_invite.dart';

class CallSignalingService {
  CallSignalingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get myId => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  Future<DocumentReference<Map<String, dynamic>>> createOutgoingCall({
    required ChatUser callee,
    required RTCSessionDescription offer,
  }) async {
    final caller = _auth.currentUser;
    if (caller == null) {
      throw StateError('You must be signed in to start a call.');
    }

    if (callee.uid.isEmpty || callee.uid == caller.uid) {
      throw StateError('Invalid call recipient.');
    }

    final reference = _calls.doc();

    await reference.set({
      'type': 'audio',
      'status': 'ringing',
      'callerId': caller.uid,
      'callerName': caller.displayName ?? 'VonoTalky user',
      'callerPhotoUrl': caller.photoURL,
      'calleeId': callee.uid,
      'calleeName': callee.name,
      'calleePhotoUrl': callee.photoUrl,
      'memberIds': [caller.uid, callee.uid],
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'createdAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'endedAt': null,
    });

    return reference;
  }

  Stream<List<IncomingCallInvite>> watchIncomingCalls() {
    final uid = myId;
    if (uid.isEmpty) return const Stream.empty();

    return _calls.where('calleeId', isEqualTo: uid).snapshots().map((snapshot) {
      final invites = snapshot.docs
          .where((document) => document.data()['status'] == 'ringing')
          .map(IncomingCallInvite.fromDoc)
          .toList(growable: false);

      final sorted = [...invites]
        ..sort((a, b) {
          final aa = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bb.compareTo(aa);
        });

      return sorted;
    });
  }

  Future<IncomingCallInvite?> readIncomingInvite(String callId) async {
    final uid = myId;
    if (callId.isEmpty || uid.isEmpty) return null;

    final document = await _calls.doc(callId).get();
    if (!document.exists) return null;

    final data = document.data();
    if (data == null ||
        data['calleeId'] != uid ||
        data['status'] != 'ringing') {
      return null;
    }

    return IncomingCallInvite.fromDoc(document);
  }

  Future<RTCSessionDescription> readOffer(String callId) async {
    final document = await _calls.doc(callId).get();

    final raw = document.data()?['offer'];
    if (raw is! Map) {
      throw StateError('This call has no WebRTC offer.');
    }

    final map = Map<String, dynamic>.from(raw);
    final sdp = map['sdp'] as String?;
    final type = map['type'] as String?;

    if (sdp == null ||
        sdp.trim().isEmpty ||
        type == null ||
        type.trim().isEmpty) {
      throw StateError('The WebRTC offer is incomplete.');
    }

    return RTCSessionDescription(sdp, type);
  }

  Future<void> acceptCall({
    required String callId,
    required RTCSessionDescription answer,
  }) async {
    if (callId.isEmpty) return;

    await _calls.doc(callId).update({
      'status': 'accepted',
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectCall(String callId) async {
    if (callId.isEmpty) return;

    await _calls.doc(callId).update({
      'status': 'rejected',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addCallerCandidate({
    required String callId,
    required RTCIceCandidate candidate,
  }) async {
    if (callId.isEmpty ||
        candidate.candidate == null ||
        candidate.candidate!.isEmpty) {
      return;
    }

    await _calls
        .doc(callId)
        .collection('callerCandidates')
        .add(_candidateData(candidate));
  }

  Future<void> addCalleeCandidate({
    required String callId,
    required RTCIceCandidate candidate,
  }) async {
    if (callId.isEmpty ||
        candidate.candidate == null ||
        candidate.candidate!.isEmpty) {
      return;
    }

    await _calls
        .doc(callId)
        .collection('calleeCandidates')
        .add(_candidateData(candidate));
  }

  Map<String, dynamic> _candidateData(RTCIceCandidate candidate) {
    return {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Stream<CallSession> watchSession(String callId) {
    if (callId.isEmpty) return const Stream.empty();

    return _calls
        .doc(callId)
        .snapshots()
        .where((document) => document.exists)
        .map(CallSession.fromDoc);
  }

  Stream<RTCSessionDescription?> watchAnswer(String callId) {
    if (callId.isEmpty) return const Stream.empty();

    return _calls.doc(callId).snapshots().map((document) {
      final raw = document.data()?['answer'];
      if (raw is! Map) return null;

      final map = Map<String, dynamic>.from(raw);
      final sdp = map['sdp'] as String?;
      final type = map['type'] as String?;

      if (sdp == null ||
          sdp.trim().isEmpty ||
          type == null ||
          type.trim().isEmpty) {
        return null;
      }

      return RTCSessionDescription(sdp, type);
    });
  }

  Stream<RTCIceCandidate> watchCallerCandidates(String callId) {
    return _candidateStream(callId, 'callerCandidates');
  }

  Stream<RTCIceCandidate> watchCalleeCandidates(String callId) {
    return _candidateStream(callId, 'calleeCandidates');
  }

  Stream<RTCIceCandidate> _candidateStream(String callId, String collection) {
    if (callId.isEmpty) return const Stream.empty();

    return _calls
        .doc(callId)
        .collection(collection)
        .orderBy('createdAt')
        .snapshots()
        .expand(
          (snapshot) => snapshot.docChanges
              .where((change) => change.type == DocumentChangeType.added)
              .map((change) {
                final data = change.doc.data() ?? const <String, dynamic>{};

                final value = data['candidate'] as String?;
                if (value == null || value.isEmpty) {
                  return null;
                }

                return RTCIceCandidate(
                  value,
                  data['sdpMid'] as String?,
                  (data['sdpMLineIndex'] as num?)?.toInt(),
                );
              })
              .whereType<RTCIceCandidate>(),
        );
  }

  Future<void> endCall(String callId) async {
    if (callId.isEmpty) return;

    final reference = _calls.doc(callId);
    final snapshot = await reference.get();
    if (!snapshot.exists) return;

    await reference.update({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markFailed(String callId) async {
    if (callId.isEmpty) return;

    final reference = _calls.doc(callId);
    final snapshot = await reference.get();
    if (!snapshot.exists) return;

    await reference.update({
      'status': 'failed',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }
}
