## [Unreleased]

### Fixed

- Fixed global incoming-call listening being initialized before Firebase Auth had restored the signed-in user.
- `IncomingCallListener` now rebinds its Firestore `calls` subscription whenever authentication changes, instead of permanently subscribing to an empty stream when mounted from `MaterialApp.builder`.
- Incoming-call FCM resolution now requires an authenticated user before reading the call document.
- Preserved duplicate-listener protection for older ChatHome builds.


### Fixed

- Promoted the WhatsApp-style incoming/ongoing call surface to `MaterialApp.builder`, so the call bar remains visible above every Navigator route instead of only on Recent Chats.
- Direct chats, group chats, Contacts, Space, Profile, Settings, and other pushed routes now share the same global call overlay.
- Converted `IncomingCallListener` into a listener-only wrapper and added duplicate-listener protection for compatibility with older ChatHome builds that may still mount it locally.


### Added

- Added a WhatsApp-style pure voice call flow with a persistent call coordinator.
- Foreground incoming calls now appear as a top call bar with Accept and Decline actions.
- Active calls can be minimized back into VonoTalky without hanging up.
- Minimized calls remain accessible through an ongoing top call bar with mute and hang-up controls.
- Tapping the ongoing call bar reopens the full call screen.
- Call controller ownership is moved out of the call page so route changes no longer end the active voice session.
- Enforced one active VonoTalky call session at a time.

