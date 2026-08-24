import 'package:flutter/material.dart';

import '../../../chat/data/models/chat_user.dart';
import '../../application/call_coordinator.dart';
import 'active_call_page.dart';

class AudioCallPage extends StatefulWidget {
  const AudioCallPage({super.key, required this.user});

  final ChatUser user;

  @override
  State<AudioCallPage> createState() => _AudioCallPageState();
}

class _AudioCallPageState extends State<AudioCallPage> {
  final CallCoordinator coordinator = CallCoordinator.instance;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _started) return;
      _started = true;

      if (!coordinator.hasCall) {
        await coordinator.startOutgoing(widget.user);
      }

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ActiveCallPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF2ECFA),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
