import 'package:flutter/material.dart';

import '../../application/call_coordinator.dart';
import '../../data/models/incoming_call_invite.dart';
import 'active_call_page.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({
    super.key,
    required this.invite,
    this.autoAccept = false,
  });

  final IncomingCallInvite invite;
  final bool autoAccept;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  final CallCoordinator coordinator = CallCoordinator.instance;
  bool _handled = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _handled) return;
      _handled = true;

      coordinator.presentIncoming(widget.invite);

      if (widget.autoAccept) {
        await coordinator.acceptIncoming();
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
