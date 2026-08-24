import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

class WebRtcAudioService {
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  bool _remoteDescriptionApplied = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  MediaStream? get localStream => _localStream;

  Future<void> prepare({
    required void Function(RTCIceCandidate candidate) onIceCandidate,
  }) async {
    if (_localStream != null && _peerConnection != null) return;

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    final connection = await createPeerConnection({
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302'],
        },
      ],
      'sdpSemantics': 'unified-plan',
    });

    connection.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;

      debugPrint('WebRTC local ICE candidate: ${candidate.candidate}');

      onIceCandidate(candidate);
    };

    connection.onIceConnectionState = (state) {
      debugPrint('WebRTC ICE state: $state');
    };

    connection.onConnectionState = (state) {
      debugPrint('WebRTC connection state: $state');
    };

    connection.onTrack = (event) {
      debugPrint(
        'WebRTC remote track: '
        'kind=${event.track.kind}, '
        'id=${event.track.id}, '
        'streams=${event.streams.length}',
      );

      if (event.track.kind == 'audio') {
        event.track.enabled = true;
      }
    };

    _peerConnection = connection;

    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
      await connection.addTrack(track, _localStream!);
    }
    await Helper.setSpeakerphoneOn(true);
  }

  Future<RTCSessionDescription> createOffer() async {
    final connection = _requireConnection();
    final offer = await connection.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await connection.setLocalDescription(offer);
    return offer;
  }

  Future<void> applyRemoteOffer(RTCSessionDescription offer) async {
    final connection = _requireConnection();
    await connection.setRemoteDescription(offer);
    _remoteDescriptionApplied = true;
    await _flushPendingCandidates(connection);
  }

  Future<RTCSessionDescription> createAnswer() async {
    final connection = _requireConnection();
    final answer = await connection.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await connection.setLocalDescription(answer);
    return answer;
  }

  Future<void> applyRemoteAnswer(RTCSessionDescription answer) async {
    final connection = _requireConnection();
    await connection.setRemoteDescription(answer);
    _remoteDescriptionApplied = true;
    await _flushPendingCandidates(connection);
  }

  Future<void> addRemoteCandidate(RTCIceCandidate candidate) async {
    final connection = _peerConnection;
    if (connection == null) return;

    if (!_remoteDescriptionApplied) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }

    await connection.addCandidate(candidate);
  }

  Future<void> setMuted(bool muted) async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> setSpeakerEnabled(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  RTCPeerConnection _requireConnection() {
    final connection = _peerConnection;
    if (connection == null) {
      throw StateError('WebRTC has not been prepared.');
    }
    return connection;
  }

  Future<void> _flushPendingCandidates(RTCPeerConnection connection) async {
    for (final candidate in _pendingRemoteCandidates) {
      await connection.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> dispose() async {
    _pendingRemoteCandidates.clear();
    _remoteDescriptionApplied = false;

    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;
  }
}
