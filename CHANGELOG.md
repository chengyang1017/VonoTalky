## [Unreleased]

### Added

- Rebuilt the WhatsApp-style pure voice-call lifecycle on top of the current stable call baseline.
- Added a global incoming/ongoing call bar using the root Navigator's real `Overlay`, so it remains visible above direct chats, group chats, Contacts, Space, Profile, Settings, and other pushed routes.
- Foreground incoming calls now expose Accept and Decline directly from the global call bar.
- Active calls can be minimized by leaving the full call page without ending the call; tapping the ongoing call bar returns to the full call page.
- Added a persistent `CallCoordinator` so call media/controller lifetime is no longer tied to a single route.

### Fixed

- Avoided the previous `MaterialApp.builder` overlay placement that caused `No Overlay widget found` / Tooltip red screens.
- Rebound incoming Firestore call listening to Firebase Auth changes so mounting before AuthGate resolves cannot permanently subscribe to an empty UID.
- Preserved early outgoing ICE candidates until the Firestore call ID exists instead of dropping them.
- Hardened incoming and outgoing call controllers against asynchronous callbacks after disposal.
- Kept Android CallKit for background/locked-device calls while using the in-app call bar when VonoTalky is foregrounded.


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

