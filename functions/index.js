const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

async function getEnabledDeviceTokens(
  userId,
  {
    excludeConversationId = null,
  } = {},
) {
  const snapshot = await db
    .collection("users")
    .doc(userId)
    .collection("devices")
    .get();

  const tokens = [];

  for (const document of snapshot.docs) {
    const data = document.data();

    if (data.notificationsEnabled === false) {
      continue;
    }

    if (
      excludeConversationId &&
      data.activeConversationId === excludeConversationId
    ) {
      logger.info("Skipping FCM for device already viewing conversation.", {
        userId,
        conversationId: excludeConversationId,
        deviceId: document.id,
      });
      continue;
    }

    const token = data.fcmToken;
    if (typeof token === "string" && token.trim().length > 0) {
      tokens.push(token.trim());
    }
  }

  return [...new Set(tokens)];
}

async function removeInvalidTokens(userId, tokens, response) {
  const invalidCodes = new Set([
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
  ]);

  const writes = [];

  response.responses.forEach((result, index) => {
    if (result.success) return;

    const code = result.error?.code;
    if (!invalidCodes.has(code)) return;

    const token = tokens[index];
    if (!token) return;

    const deviceId = token.replaceAll("/", "_");

    writes.push(
      db
        .collection("users")
        .doc(userId)
        .collection("devices")
        .doc(deviceId)
        .set(
          {
            notificationsEnabled: false,
            invalidatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
    );
  });

  await Promise.all(writes);
}

async function sendToUser({
  userId,
  title,
  body,
  data,
  excludeConversationId = null,
}) {
  const tokens = await getEnabledDeviceTokens(userId, {
    excludeConversationId,
  });

  if (tokens.length === 0) {
    logger.info("No enabled FCM devices for user.", { userId });
    return {
      successCount: 0,
      failureCount: 0,
    };
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title,
      body,
    },
    data: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [
        key,
        value == null ? "" : String(value),
      ]),
    ),
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });

  await removeInvalidTokens(userId, tokens, response);

  logger.info("FCM multicast completed.", {
    userId,
    successCount: response.successCount,
    failureCount: response.failureCount,
    type: data.type,
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}


async function sendDataOnlyToUser({
  userId,
  data,
}) {
  const tokens = await getEnabledDeviceTokens(userId);

  if (tokens.length === 0) {
    logger.info("No enabled FCM devices for data-only message.", {
      userId,
      type: data.type,
    });
    return {
      successCount: 0,
      failureCount: 0,
    };
  }

  const response = await messaging.sendEachForMulticast({
    tokens,
    data: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [
        key,
        value == null ? "" : String(value),
      ]),
    ),
    android: {
      priority: "high",
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          "content-available": 1,
        },
      },
    },
  });

  await removeInvalidTokens(userId, tokens, response);

  logger.info("Data-only FCM multicast completed.", {
    userId,
    successCount: response.successCount,
    failureCount: response.failureCount,
    type: data.type,
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

exports.onPetInviteCreated = onDocumentCreated(
  "petInvites/{inviteId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const invite = snapshot.data();
    if (invite.status !== "pending") return;

    const receiverId = invite.receiverId;
    const senderId = invite.senderId;

    if (
      typeof receiverId !== "string" ||
      receiverId.length === 0 ||
      typeof senderId !== "string" ||
      senderId.length === 0 ||
      receiverId === senderId
    ) {
      logger.warn("Invalid pet invite notification payload.", {
        inviteId: event.params.inviteId,
      });
      return;
    }

    const senderName =
      typeof invite.senderName === "string" &&
      invite.senderName.trim().length > 0
        ? invite.senderName.trim()
        : "A friend";

    const petName =
      typeof invite.petName === "string" &&
      invite.petName.trim().length > 0
        ? invite.petName.trim()
        : "a pet";

    await sendToUser({
      userId: receiverId,
      title: "Raise a pet together 🐾",
      body: `${senderName} invited you to raise ${petName} together.`,
      data: {
        type: "pet_invite",
        inviteId: event.params.inviteId,
        friendId: senderId,
        petId: "",
      },
    });
  },
);

exports.onPetCareRequestCreated = onDocumentCreated(
  "sharedPets/{petId}/careRequests/{requestId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const request = snapshot.data();
    if (request.status !== "pending") return;

    const receiverId = request.receiverId;
    const senderId = request.senderId;

    if (
      typeof receiverId !== "string" ||
      receiverId.length === 0 ||
      typeof senderId !== "string" ||
      senderId.length === 0 ||
      receiverId === senderId
    ) {
      logger.warn("Invalid care request notification payload.", {
        petId: event.params.petId,
        requestId: event.params.requestId,
      });
      return;
    }

    const petSnapshot = await db
      .collection("sharedPets")
      .doc(event.params.petId)
      .get();

    if (!petSnapshot.exists) {
      logger.warn("Care request references missing pet.", {
        petId: event.params.petId,
      });
      return;
    }

    const pet = petSnapshot.data();
    const members = Array.isArray(pet.memberIds) ? pet.memberIds : [];

    if (!members.includes(receiverId) || !members.includes(senderId)) {
      logger.warn("Care request users are not pet members.", {
        petId: event.params.petId,
        receiverId,
        senderId,
      });
      return;
    }

    const petName =
      typeof pet.petName === "string" && pet.petName.trim().length > 0
        ? pet.petName.trim()
        : "your pet";

    const memberNames =
      pet.memberNames && typeof pet.memberNames === "object"
        ? pet.memberNames
        : {};

    const senderName =
      typeof memberNames[senderId] === "string" &&
      memberNames[senderId].trim().length > 0
        ? memberNames[senderId].trim()
        : "Your friend";

    const action = (() => {
      switch (request.type) {
        case "feed":
          return {
            title: `${petName} is hungry 🍪`,
            body: `${senderName} asked you to feed ${petName}.`,
          };
        case "play":
          return {
            title: `${petName} wants to play 🎮`,
            body: `${senderName} asked you to play with ${petName}.`,
          };
        default:
          return {
            title: `${petName} needs some love 💗`,
            body: `${senderName} asked you to pet ${petName}.`,
          };
      }
    })();

    await sendToUser({
      userId: receiverId,
      title: action.title,
      body: action.body,
      data: {
        type: "care_request",
        petId: event.params.petId,
        careRequestId: event.params.requestId,
        friendId: senderId,
        inviteId: "",
      },
    });
  },
);

exports.onDirectMessageCreated = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const senderId = message.senderId;

    if (typeof senderId !== "string" || senderId.length === 0) {
      logger.warn("Direct message has no valid senderId.", {
        conversationId: event.params.conversationId,
        messageId: event.params.messageId,
      });
      return;
    }

    const conversationSnapshot = await db
      .collection("conversations")
      .doc(event.params.conversationId)
      .get();

    if (!conversationSnapshot.exists) {
      logger.warn("Message references a missing conversation.", {
        conversationId: event.params.conversationId,
      });
      return;
    }

    const conversation = conversationSnapshot.data();
    const members = Array.isArray(conversation.memberIds)
      ? conversation.memberIds
      : [];

    if (!members.includes(senderId) || members.length !== 2) {
      logger.warn("Invalid direct-message membership.", {
        conversationId: event.params.conversationId,
        senderId,
        memberIds: members,
      });
      return;
    }

    const receiverId = members.find((uid) => uid !== senderId);
    if (!receiverId) return;

    const senderSnapshot = await db.collection("users").doc(senderId).get();
    const sender = senderSnapshot.exists ? senderSnapshot.data() : {};

    const senderName =
      typeof sender.name === "string" && sender.name.trim().length > 0
        ? sender.name.trim()
        : typeof sender.displayName === "string" &&
            sender.displayName.trim().length > 0
          ? sender.displayName.trim()
          : typeof sender.username === "string" &&
              sender.username.trim().length > 0
            ? sender.username.trim()
            : "New message";

    const type =
      typeof message.type === "string" ? message.type.toLowerCase() : "text";

    let body;
    switch (type) {
      case "image":
        body = "📷 Sent a photo";
        break;
      case "voice":
      case "audio":
        body = "🎤 Voice message";
        break;
      case "file":
        body =
          typeof message.fileName === "string" &&
          message.fileName.trim().length > 0
            ? `📎 ${message.fileName.trim()}`
            : "📎 Sent a file";
        break;
      default: {
        const text =
          typeof message.text === "string" ? message.text.trim() : "";
        body = text.length > 0 ? text.slice(0, 160) : "Sent you a message";
      }
    }

    await sendToUser({
      userId: receiverId,
      title: senderName,
      body,
      excludeConversationId: event.params.conversationId,
      data: {
        type: "direct_message",
        conversationId: event.params.conversationId,
        messageId: event.params.messageId,
        friendId: senderId,
        petId: "",
        inviteId: "",
        careRequestId: "",
      },
    });
  },
);
exports.onGroupMessageCreated = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const senderId = message.senderId;
    const groupId = event.params.groupId;
    const messageId = event.params.messageId;

    if (typeof senderId !== "string" || senderId.length === 0) {
      logger.warn("Group message has no valid senderId.", {
        groupId,
        messageId,
      });
      return;
    }

    const groupSnapshot = await db.collection("groups").doc(groupId).get();
    if (!groupSnapshot.exists) {
      logger.warn("Group message references a missing group.", {
        groupId,
        messageId,
      });
      return;
    }

    const group = groupSnapshot.data();
    const members = Array.isArray(group.memberIds) ? group.memberIds : [];

    if (!members.includes(senderId)) {
      logger.warn("Group message sender is not a group member.", {
        groupId,
        messageId,
        senderId,
      });
      return;
    }

    const receivers = [...new Set(members)].filter(
      (uid) => typeof uid === "string" && uid.length > 0 && uid !== senderId,
    );
    if (receivers.length === 0) return;

    const groupName =
      typeof group.name === "string" && group.name.trim().length > 0
        ? group.name.trim()
        : "Group chat";

    let senderName =
      typeof message.senderName === "string" &&
      message.senderName.trim().length > 0
        ? message.senderName.trim()
        : "VonoTalky user";

    if (senderName === "VonoTalky user") {
      const senderSnapshot = await db.collection("users").doc(senderId).get();
      const sender = senderSnapshot.exists ? senderSnapshot.data() : {};
      senderName =
        typeof sender.name === "string" && sender.name.trim().length > 0
          ? sender.name.trim()
          : typeof sender.displayName === "string" &&
              sender.displayName.trim().length > 0
            ? sender.displayName.trim()
            : typeof sender.username === "string" &&
                sender.username.trim().length > 0
              ? sender.username.trim()
              : "VonoTalky user";
    }

    const type =
      typeof message.type === "string" ? message.type.toLowerCase() : "text";
    let preview;
    switch (type) {
      case "image":
        preview = "馃摲 Photo";
        break;
      case "voice":
      case "audio":
        preview = "馃帳 Voice message";
        break;
      case "file":
        preview =
          typeof message.fileName === "string" &&
          message.fileName.trim().length > 0
            ? `馃搸 ${message.fileName.trim()}`
            : "馃搸 File";
        break;
      default: {
        const text =
          typeof message.text === "string" ? message.text.trim() : "";
        preview = text.length > 0 ? text.slice(0, 140) : "New message";
      }
    }

    const results = await Promise.allSettled(
      receivers.map((receiverId) =>
        sendToUser({
          userId: receiverId,
          title: groupName,
          body: `${senderName}: ${preview}`,
          excludeConversationId: `group_${groupId}`,
          data: {
            type: "group_message",
            groupId,
            messageId,
            senderId,
            conversationId: `group_${groupId}`,
            friendId: "",
            petId: "",
            inviteId: "",
            careRequestId: "",
          },
        }),
      ),
    );

    const failed = results.filter((result) => result.status === "rejected");
    if (failed.length > 0) {
      logger.error("Some group notifications failed.", {
        groupId,
        messageId,
        senderId,
        receiverCount: receivers.length,
        failureCount: failed.length,
      });
    } else {
      logger.info("Group notification fan-out completed.", {
        groupId,
        messageId,
        senderId,
        receiverCount: receivers.length,
      });
    }
  },
);

exports.onCallCreated = onDocumentCreated(
  "calls/{callId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const call = snapshot.data();

    // Do not require a specific call.type value here. Existing clients may
    // omit it or use a legacy value. The signaling status + participants are
    // the reliable compatibility contract.
    if (call.status !== "ringing") return;

    const callerId = call.callerId;
    const calleeId = call.calleeId;

    if (
      typeof callerId !== "string" ||
      callerId.length === 0 ||
      typeof calleeId !== "string" ||
      calleeId.length === 0 ||
      callerId === calleeId
    ) {
      logger.warn("Invalid incoming call payload.", {
        callId: event.params.callId,
        callerId,
        calleeId,
        status: call.status,
      });
      return;
    }

    const callerName =
      typeof call.callerName === "string" &&
      call.callerName.trim().length > 0
        ? call.callerName.trim()
        : "VonoTalky user";

    const callerPhotoUrl =
      typeof call.callerPhotoUrl === "string"
        ? call.callerPhotoUrl
        : "";

    // Reliability-first delivery:
    // - foreground: FirebaseMessaging.onMessage + Firestore signaling
    // - background/killed: Android/iOS receives a normal high-priority push
    //   which the user can tap to open the call
    //
    // NotificationService explicitly ignores foreground banners, so this
    // will not recreate the intrusive in-app "Open / X" MaterialBanner.
    await sendToUser({
      userId: calleeId,
      title: callerName,
      body: "Incoming voice call",
      data: {
        type: "incoming_call",
        callId: event.params.callId,
        callerId,
        callerName,
        callerPhotoUrl,
        friendId: callerId,
      },
    });
  },
);

