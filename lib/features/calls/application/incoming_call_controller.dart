import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/models/call_session.dart';
import '../data/services/call_signaling_service.dart';
import '../data/services/webrtc_audio_service.dart';
import '../domain/models/call_status.dart';
import 'call_state.dart';

class IncomingCallController extends ChangeNotifier {
  IncomingCallController({
    required this.callId,
    CallSignalingService? signalingService,
    WebRtcAudioService? audioService,
  }) : _signalingService = signalingService ?? CallSignalingService(),
       _audioService = audioService ?? WebRtcAudioService();

  final String callId;
  final CallSignalingService _signalingService;
  final WebRtcAudioService _audioService;

  CallState _state = const CallState(status: CallStatus.ringing);
  StreamSubscription<CallSession>? _sessionSubscription;
  StreamSubscription<RTCIceCandidate>? _candidateSubscription;
  Timer? _timer;
  DateTime? _connectedAt;

  bool _disposed = false;
  bool _closing = false;

  CallState get state => _state;

  void startWatching() {
    if (_disposed) return;

    _sessionSubscription ??= _signalingService.watchSession(callId).listen((
      session,
    ) {
      if (_disposed) return;

      if (session.status == CallSessionStatus.ended ||
          session.status == CallSessionStatus.rejected) {
        _setState(_state.copyWith(status: CallStatus.ended));
      } else if (session.status == CallSessionStatus.failed) {
        _setState(
          _state.copyWith(
            status: CallStatus.failed,
            errorMessage: 'The caller ended this call.',
          ),
        );
      }
    });
  }

  Future<void> accept() async {
    if (_disposed || _state.status != CallStatus.ringing) return;

    _setState(_state.copyWith(status: CallStatus.connecting, clearError: true));

    try {
      await _audioService.prepare(
        onIceCandidate: (candidate) {
          if (_disposed) return;

          unawaited(
            _signalingService
                .addCalleeCandidate(callId: callId, candidate: candidate)
                .catchError((_) {}),
          );
        },
      );

      if (_disposed) return;

      final offer = await _signalingService.readOffer(callId);
      if (_disposed) return;

      await _audioService.applyRemoteOffer(offer);
      if (_disposed) return;

      _candidateSubscription = _signalingService
          .watchCallerCandidates(callId)
          .listen((candidate) {
            if (_disposed) return;

            unawaited(
              _audioService.addRemoteCandidate(candidate).catchError((_) {}),
            );
          });

      final answer = await _audioService.createAnswer();
      if (_disposed) return;

      await _signalingService.acceptCall(callId: callId, answer: answer);

      if (_disposed) return;
      _markConnected();
    } catch (error) {
      if (_disposed) return;

      try {
        await _signalingService.markFailed(callId);
      } catch (_) {}

      if (_disposed) return;

      _setState(
        _state.copyWith(
          status: CallStatus.failed,
          errorMessage: 'Could not answer call: $error',
        ),
      );
    }
  }

  Future<void> reject() async {
    if (_disposed || _closing) return;
    _closing = true;

    try {
      await _signalingService.rejectCall(callId);
      await _closeMedia();

      if (!_disposed) {
        _setState(_state.copyWith(status: CallStatus.ended));
      }
    } finally {
      _closing = false;
    }
  }

  Future<void> hangUp() async {
    if (_disposed || _closing) return;
    _closing = true;

    try {
      try {
        await _signalingService.endCall(callId);
      } catch (_) {}

      await _closeMedia();

      if (!_disposed) {
        _setState(_state.copyWith(status: CallStatus.ended));
      }
    } finally {
      _closing = false;
    }
  }

  Future<void> toggleMute() async {
    if (_disposed || _closing) return;

    final next = !_state.muted;
    await _audioService.setMuted(next);

    if (_disposed) return;
    _setState(_state.copyWith(muted: next));
  }

  Future<void> toggleSpeaker() async {
    if (_disposed || _closing) return;

    final next = !_state.speakerEnabled;
    await _audioService.setSpeakerEnabled(next);

    if (_disposed) return;
    _setState(_state.copyWith(speakerEnabled: next));
  }

  void _markConnected() {
    if (_disposed || _closing || _state.status == CallStatus.connected) {
      return;
    }

    _connectedAt = DateTime.now();
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _closing) return;

      final start = _connectedAt;
      if (start == null) return;

      _setState(_state.copyWith(elapsed: DateTime.now().difference(start)));
    });

    _setState(_state.copyWith(status: CallStatus.connected));
  }

  Future<void> _closeMedia() async {
    _timer?.cancel();
    _timer = null;

    await _candidateSubscription?.cancel();
    _candidateSubscription = null;

    await _audioService.dispose();
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
    _timer?.cancel();
    _timer = null;

    unawaited(_sessionSubscription?.cancel());
    unawaited(_candidateSubscription?.cancel());
    unawaited(_audioService.dispose());

    super.dispose();
  }
}
