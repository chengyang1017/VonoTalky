import 'package:flutter/material.dart';

import '../../../../app/navigation/app_navigator.dart';
import '../../application/call_coordinator.dart';
import '../../domain/models/call_status.dart';
import '../pages/active_call_page.dart';

class GlobalCallBar extends StatelessWidget {
  const GlobalCallBar({super.key});

  CallCoordinator get coordinator => CallCoordinator.instance;

  Future<void> _openCallPage() async {
    if (!coordinator.hasCall || coordinator.callPageVisible) return;

    final navigator = AppNavigator.key.currentState;
    if (navigator == null) return;

    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => const ActiveCallPage()),
    );
  }

  Future<void> _accept() async {
    final accepted = await coordinator.acceptIncoming();
    if (accepted) {
      await _openCallPage();
    }
  }

  String get _subtitle {
    final status = coordinator.status;

    if (status == CallStatus.preparing) return 'Preparing call...';
    if (status == CallStatus.ringing) {
      return coordinator.kind == ActiveCallKind.incoming
          ? 'Incoming voice call'
          : 'Ringing...';
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
    if (status == CallStatus.failed) return 'Call failed';
    if (status == CallStatus.ended) return 'Call ended';

    return 'Voice call';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Material(
          color: colors.surface,
          elevation: 10,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                coordinator.kind == ActiveCallKind.incoming &&
                    coordinator.status == CallStatus.ringing
                ? null
                : _openCallPage,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  _CallAvatar(
                    name: coordinator.displayName,
                    photoUrl: coordinator.photoUrl,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coordinator.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          style: TextStyle(
                            color: coordinator.status == CallStatus.connected
                                ? const Color(0xFF3FA767)
                                : colors.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (coordinator.kind == ActiveCallKind.incoming &&
                      coordinator.status == CallStatus.ringing) ...[
                    IconButton.filled(
                      tooltip: 'Decline',
                      onPressed: coordinator.busy
                          ? null
                          : coordinator.declineIncoming,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE95362),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end_rounded),
                    ),
                    const SizedBox(width: 7),
                    IconButton.filled(
                      tooltip: 'Accept',
                      onPressed: coordinator.busy ? null : _accept,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF34B879),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_rounded),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: coordinator.muted ? 'Unmute' : 'Mute',
                      onPressed: coordinator.toggleMute,
                      icon: Icon(
                        coordinator.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        color: colors.primary,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Hang up',
                      onPressed: coordinator.busy ? null : coordinator.hangUp,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFE95362),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return CircleAvatar(
      radius: 23,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .12),
      backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
      child: hasPhoto
          ? null
          : Text(
              name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
    );
  }
}
