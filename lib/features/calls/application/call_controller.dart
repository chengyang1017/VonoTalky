import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../chat/data/models/chat_user.dart';
import '../data/models/call_session.dart';
import '../data/services/call_signaling_service.dart';
import '../data/services/webrtc_audio_service.dart';
import '../domain/models/call_status.dart';
import 'call_state.dart';

class CallController extends ChangeNotifier {
  CallController({
    WebRtcAudioService? audioService,
    CallSignalingService? signalingService,
  }) : _audioService = audioService ?? WebRtcAudioService(),
       _signalingService = signalingService ?? CallSignalingService();

  final WebRtcAudioService _audioService;
  final CallSignalingService _signalingService;

  CallState _state = const CallState();
  Timer? _timer;
  DateTime? _connectedAt;
  String? _callId;

  StreamSubscription<CallSession>? _sessionSubscription;
  StreamSubscription<RTCSessionDescription?>? _answerSubscription;
  StreamSubscription<RTCIceCandidate>? _candidateSubscription;

  final List<RTCIceCandidate> _pendingCallerCandidates = [];

  bool _answerApplied = false;
  bool _disposed = false;
  bool _ending = false;

  CallState get state => _state;
  String? get callId => _callId;

  Future<void> startOutgoingCall(ChatUser callee) async {
    if (_disposed || _state.status != CallStatus.idle) return;

    _setState(_state.copyWith(status: CallStatus.preparing, clearError: true));

    try {
      await _audioService.prepare(
        onIceCandidate: (candidate) {
          if (_disposed) return;

          final id = _callId;
          if (id == null) {
            _pendingCallerCandidates.add(candidate);
            return;
          }

          unawaited(
            _signalingService
                .addCallerCandidate(callId: id, candidate: candidate)
                .catchError((_) {}),
          );
        },
      );

      if (_disposed) return;

      final offer = await _audioService.createOffer();
      if (_disposed) return;

      final reference = await _signalingService.createOutgoingCall(
        callee: callee,
        offer: offer,
      );

      _callId = reference.id;

      final pending = List<RTCIceCandidate>.from(_pendingCallerCandidates);
      _pendingCallerCandidates.clear();

      for (final candidate in pending) {
        if (_disposed) return;
        await _signalingService.addCallerCandidate(
          callId: reference.id,
          candidate: candidate,
        );
      }

      if (_disposed) return;

      _answerApplied = false;
      _listenForRemoteSignaling(reference.id);
      _setState(_state.copyWith(status: CallStatus.ringing));
    } catch (error) {
      if (_disposed) return;

      final id = _callId;
      if (id != null) {
        try {
          await _signalingService.markFailed(id);
        } catch (_) {}
      }

      if (_disposed) return;

      _setState(
        _state.copyWith(
          status: CallStatus.failed,
          errorMessage: 'Call could not be started: $error',
        ),
      );
    }
  }

  void _listenForRemoteSignaling(String callId) {
    if (_disposed) return;

    unawaited(_disposeSubscriptions());

    _sessionSubscription = _signalingService.watchSession(callId).listen((
      session,
    ) {
      if (_disposed || session.id != _callId) return;

      if (session.status == CallSessionStatus.accepted) {
        if (_state.status != CallStatus.connected) {
          _setState(_state.copyWith(status: CallStatus.connecting));
        }
        return;
      }

      if (session.status == CallSessionStatus.rejected ||
          session.status == CallSessionStatus.ended) {
        _timer?.cancel();
        _timer = null;

        if (_state.status != CallStatus.ended) {
          _setState(_state.copyWith(status: CallStatus.ended));
        }
        return;
      }

      if (session.status == CallSessionStatus.failed) {
        _timer?.cancel();
        _timer = null;
        _setState(
          _state.copyWith(
            status: CallStatus.failed,
            errorMessage: 'The call could not be connected.',
          ),
        );
      }
    });

    _answerSubscription = _signalingService.watchAnswer(callId).listen((
      answer,
    ) async {
      if (_disposed || callId != _callId || answer == null || _answerApplied) {
        return;
      }

      _answerApplied = true;

      try {
        await _audioService.applyRemoteAnswer(answer);
        if (_disposed || callId != _callId) return;
        markConnected();
      } catch (error) {
        if (_disposed) return;
        _setState(
          _state.copyWith(
            status: CallStatus.failed,
            errorMessage: 'Could not apply call answer: $error',
          ),
        );
      }
    });

    _candidateSubscription = _signalingService
        .watchCalleeCandidates(callId)
        .listen((candidate) {
          if (_disposed || callId != _callId) return;

          unawaited(
            _audioService.addRemoteCandidate(candidate).catchError((_) {}),
          );
        });
  }

  void markConnected() {
    if (_disposed ||
        _ending ||
        _state.status == CallStatus.ended ||
        _state.status == CallStatus.failed) {
      return;
    }

    if (_state.status == CallStatus.connected && _connectedAt != null) {
      return;
    }

    _connectedAt = DateTime.now();
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _ending) return;

      final startedAt = _connectedAt;
      if (startedAt == null) return;

      _setState(_state.copyWith(elapsed: DateTime.now().difference(startedAt)));
    });

    _setState(_state.copyWith(status: CallStatus.connected));
  }

  Future<void> toggleMute() async {
    if (_disposed || _ending) return;

    final next = !_state.muted;
    await _audioService.setMuted(next);

    if (_disposed || _ending) return;
    _setState(_state.copyWith(muted: next));
  }

  Future<void> toggleSpeaker() async {
    if (_disposed || _ending) return;

    final next = !_state.speakerEnabled;
    await _audioService.setSpeakerEnabled(next);

    if (_disposed || _ending) return;
    _setState(_state.copyWith(speakerEnabled: next));
  }

  Future<void> endCall() async {
    if (_disposed || _ending) return;
    _ending = true;

    _timer?.cancel();
    _timer = null;

    try {
      final id = _callId;
      if (id != null) {
        try {
          await _signalingService.endCall(id);
        } catch (_) {}
      }

      await _disposeSubscriptions();
      await _audioService.dispose();
      _pendingCallerCandidates.clear();

      if (_disposed) return;
      _setState(_state.copyWith(status: CallStatus.ended));
    } finally {
      _ending = false;
    }
  }

  Future<void> _disposeSubscriptions() async {
    final session = _sessionSubscription;
    final answer = _answerSubscription;
    final candidate = _candidateSubscription;

    _sessionSubscription = null;
    _answerSubscription = null;
    _candidateSubscription = null;

    await session?.cancel();
    await answer?.cancel();
    await candidate?.cancel();
  }

  void _setState(CallState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;
    _ending = true;

    _timer?.cancel();
    _timer = null;
    _pendingCallerCandidates.clear();

    unawaited(_disposeSubscriptions());
    unawaited(_audioService.dispose());

    super.dispose();
  }
}
