import 'package:flutter/material.dart';

import '../../../calls/presentation/widgets/incoming_call_listener.dart';

import '../../../chat/data/models/chat_user.dart';
import '../../../chat/data/services/chat_service.dart';
import '../../../chat/presentation/pages/new_chat_page.dart';
import '../../../chat/presentation/pages/real_chat_room_page.dart';
import '../../../contacts/presentation/pages/contacts_page.dart';
import '../../../contacts/data/services/contact_service.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../pet/presentation/pages/pet_home_page.dart';
import '../../../groups/presentation/pages/create_group_page.dart';
import '../../data/services/unread_service.dart';
import '../widgets/unified_recent_chats.dart';

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final service = ChatService();
  final contactService = ContactService();
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  String query = '';

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IncomingCallListener(
    child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.topRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: .18),
              Theme.of(context).colorScheme.secondary.withValues(alpha: .13),
              Theme.of(context).colorScheme.primary.withValues(alpha: .10),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'VonoTalky',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    _NotificationButton(
                      onTap: () => _notice('Unread chats are shown below.'),
                    ),
                    IconButton(
                      tooltip: 'Search',
                      onPressed: () {
                        searchFocusNode.requestFocus();
                      },
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: TextField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() => query = value.trim().toLowerCase());
                  },
                  decoration: InputDecoration(
                    hintText: 'Search contacts or groups...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? const Icon(Icons.mic_none_rounded)
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _SectionTitle(
                query.isEmpty ? 'Top Contacts' : 'Matching Contacts',
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      top: 27,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        SizedBox(
                          height: 96,
                          child: StreamBuilder<List<ChatUser>>(
                            stream: contactService.contacts(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final contacts = snapshot.data!;
                              final users = contacts
                                  .where(
                                    (user) =>
                                        query.isEmpty ||
                                        user.name.toLowerCase().contains(
                                          query,
                                        ) ||
                                        user.email.toLowerCase().contains(
                                          query,
                                        ),
                                  )
                                  .take(10)
                                  .toList();

                              if (users.isEmpty) {
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: Text(
                                      query.isEmpty
                                          ? 'No contacts yet'
                                          : 'No contacts match "$query"',
                                      style: const TextStyle(
                                        color: Color(0xFF756E7C),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: users.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 13),
                                itemBuilder: (_, index) {
                                  final user = users[index];
                                  return _TopContact(
                                    user: user,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RealChatRoomPage(user: user),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        _SectionTitle(
                          query.isEmpty ? 'Recent Chats' : 'Matching Chats',
                        ),
                        Expanded(child: UnifiedRecentChats(query: query)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _showCreateMenu,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_rounded, size: 19),
        label: const Text('New Chat'),
      ),
      bottomNavigationBar: widget.embedded
          ? null
          : NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (index) {
                if (index == 1) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactsPage()),
                  );
                }
                if (index == 2) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PetHomePage()),
                  );
                }
                if (index == 3) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProfilePage()),
                  );
                }
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_rounded),
                  label: 'Chats',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  label: 'Contacts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.pets_rounded),
                  label: 'Pet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  label: 'Profile',
                ),
              ],
            ),
    ),
  );

  void _clearSearch() {
    searchController.clear();
    setState(() => query = '');
    searchFocusNode.requestFocus();
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('New direct chat'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewChatPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_rounded),
              title: const Text('Create group'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF211B27),
        ),
      ),
    ),
  );
}

class _NotificationButton extends StatefulWidget {
  const _NotificationButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  late final Stream<int> unreadStream = UnreadService().totalUnread();

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: unreadStream,
    initialData: 0,
    builder: (_, snapshot) {
      final unread = snapshot.data ?? 0;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: widget.onTap,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          if (unread > 0)
            Positioned(
              right: 7,
              top: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFE34B62),
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _TopContact extends StatelessWidget {
  const _TopContact({required this.user, required this.onTap});
  final ChatUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      width: 58,
      child: Column(
        children: [
          _ContactAvatar(user: user, radius: 24, showRing: true),
          const SizedBox(height: 4),
          Text(
            user.name.split(' ').first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            user.isOnline ? 'online' : 'offline',
            style: TextStyle(
              fontSize: 9,
              color: user.isOnline
                  ? const Color(0xFF1EAD6A)
                  : const Color(0xFF8B8490),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({
    required this.user,
    required this.radius,
    this.showRing = false,
  });
  final ChatUser user;
  final double radius;
  final bool showRing;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        padding: EdgeInsets.all(showRing ? 2 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: showRing
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: .12),
          backgroundImage: user.photoUrl == null
              ? null
              : NetworkImage(user.photoUrl!),
          child: user.photoUrl == null
              ? Text(
                  user.name[0].toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
      ),
      if (user.isOnline)
        Positioned(
          right: 0,
          bottom: 1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF24C77A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
    ],
  );
}
