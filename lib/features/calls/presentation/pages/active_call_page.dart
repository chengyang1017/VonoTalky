import 'package:flutter/material.dart';

import '../../application/call_coordinator.dart';
import '../../domain/models/call_status.dart';

class ActiveCallPage extends StatefulWidget {
  const ActiveCallPage({super.key});

  @override
  State<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends State<ActiveCallPage> {
  final CallCoordinator coordinator = CallCoordinator.instance;

  @override
  void initState() {
    super.initState();
    coordinator
      ..setCallPageVisible(true)
      ..addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;

    if (!coordinator.hasCall) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {});
  }

  @override
  void dispose() {
    coordinator
      ..removeListener(_refresh)
      ..setCallPageVisible(false);
    super.dispose();
  }

  String get _statusText {
    final status = coordinator.status;

    if (status == CallStatus.preparing) return 'Preparing call...';
    if (status == CallStatus.ringing) {
      return coordinator.kind == ActiveCallKind.incoming
          ? 'Incoming voice call'
          : 'Calling...';
    }
    if (status == CallStatus.connecting) return 'Connecting...';
    if (status == CallStatus.connected) {
      final minutes = coordinator.elapsed.inMinutes.toString().padLeft(2, '0');
      final seconds = (coordinator.elapsed.inSeconds % 60).toString().padLeft(
        2,
        '0',
      );
      return '$minutes:$seconds';
    }
    if (status == CallStatus.failed) {
      return 'Call could not be connected.';
    }
    if (status == CallStatus.ended) return 'Call ended';

    return 'Voice call';
  }

  @override
  Widget build(BuildContext context) {
    final name = coordinator.displayName;
    final photo = coordinator.photoUrl;
    final status = coordinator.status;

    return Scaffold(
      backgroundColor: const Color(0xFFF2ECFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to VonoTalky',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 60,
                backgroundColor: Colors.white,
                backgroundImage: photo == null || photo.isEmpty
                    ? null
                    : NetworkImage(photo),
                child: photo == null || photo.isEmpty
                    ? Text(
                        name.trim().isEmpty
                            ? '?'
                            : name.trim()[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF76579A),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 22),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF332A3C),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: status == CallStatus.failed
                      ? const Color(0xFFB34B5E)
                      : const Color(0xFF746A7C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (coordinator.kind == ActiveCallKind.incoming &&
                  status == CallStatus.ringing)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundCallButton(
                      icon: Icons.call_end_rounded,
                      label: 'Decline',
                      backgroundColor: const Color(0xFFE65A68),
                      onTap: coordinator.declineIncoming,
                    ),
                    _RoundCallButton(
                      icon: Icons.call_rounded,
                      label: 'Accept',
                      backgroundColor: const Color(0xFF65B77A),
                      onTap: () async {
                        await coordinator.acceptIncoming();
                      },
                    ),
                  ],
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallAction(
                      icon: coordinator.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: coordinator.muted ? 'Unmute' : 'Mute',
                      active: coordinator.muted,
                      onTap: coordinator.toggleMute,
                    ),
                    _CallAction(
                      icon: coordinator.speakerEnabled
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                      label: 'Speaker',
                      active: coordinator.speakerEnabled,
                      onTap: coordinator.toggleSpeaker,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _RoundCallButton(
                  icon: Icons.call_end_rounded,
                  label: 'End',
                  backgroundColor: const Color(0xFFE65A68),
                  onTap: coordinator.hangUp,
                ),
              ],
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 70,
              height: 70,
              child: Icon(icon, color: Colors.white, size: 31),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: active ? const Color(0xFFD8C7EF) : Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: const Color(0xFF654A84), size: 27),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
