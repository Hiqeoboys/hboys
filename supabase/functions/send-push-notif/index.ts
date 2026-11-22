// Supabase Edge Function: send-push-notif
// Sends Firebase Cloud Messaging (FCM HTTP v1 API) push notifications triggered
// by Supabase Database Webhooks and records Home Inbox items in `user_notifications`.
//
// Supported tables:
//   - group_messages     -> data.type = "group_chat" (checks mutes; never stored in user_notifications)
//   - community_messages -> data.type = "community_mention" (breaks through temp mute, stored in user_notifications)
//                        -> data.type = "community_chat" (checks mutes; never stored in user_notifications)
//   - group_hike_prep    -> data.type = "group_ready" | "group_hike_cancelled" (checks mutes; stored in user_notifications)
//   - invitations        -> data.type = "group_invitation" (stored in user_notifications)
//   - friendships        -> data.type = "friend_request" (stored in user_notifications)
//   - emergency_contacts -> data.type = "emergency_contact_request" (stored in user_notifications)
//   - sos_events         -> data.type = "sos" (NEVER muted; urgent HIGH/MAX priority; stored in user_notifications)
//
// Enriched FCM payload includes `room_type`, `room_id`, `room_name`, `sender_id`,
// `sender_name`, `sender_avatar_url`, and `message_id` for grouping & unread counts.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

interface WebhookPayload {
  type?: string;
  table?: string;
  record?: Record<string, unknown>;
  old_record?: Record<string, unknown> | null;
}

interface SenderProfile {
  name: string;
  username: string;
  avatarUrl: string;
}

interface MuteState {
  muted: boolean;
  forever: boolean;
}

interface InboxInsertRow {
  user_id: string;
  type: string;
  title: string;
  body: string;
  actor_id?: string | null;
  target_id?: string | null;
  room_type?: "group" | "community" | null;
  room_id?: string | null;
  message_id?: string | null;
  data: Record<string, string>;
}

interface FcmDispatch {
  userIds: string[];
  title: string;
  body: string;
  data: Record<string, string>;
  channelId: string;
  urgent: boolean;
  silent?: boolean;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-secret, x-hiqeo-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function loadServiceAccount(): ServiceAccount | null {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")?.trim() ?? "";
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")?.trim() ?? "";
  const rawPrivateKey = Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "";
  if (projectId && clientEmail && rawPrivateKey) {
    return {
      projectId,
      clientEmail,
      privateKey: rawPrivateKey.replace(/\\n/g, "\n"),
    };
  }
  const rawJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")?.trim() ?? "";
  if (!rawJson) return null;
  try {
    const parsed = JSON.parse(rawJson) as {
      project_id?: string;
      client_email?: string;
      private_key?: string;
    };
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      return null;
    }
    return {
      projectId: parsed.project_id,
      clientEmail: parsed.client_email,
      privateKey: parsed.private_key.replace(/\\n/g, "\n"),
    };
  } catch {
    return null;
  }
}

function b64Url(data: Uint8Array | string): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}

async function fetchGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64Url(
    JSON.stringify({
      iss: sa.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      new TextEncoder().encode(unsigned),
    ),
  );
  const jwt = `${unsigned}.${b64Url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`oauth_token_failed_${res.status}: ${errText}`);
  }
  const data = await res.json();
  return String(data.access_token ?? "");
}

function isUnregisteredFcmError(status: number, bodyText: string): boolean {
  if (status === 404) return true;
  if (!bodyText) return false;
  try {
    const parsed = JSON.parse(bodyText) as {
      error?: {
        status?: string;
        message?: string;
        details?: Array<{ errorCode?: string }>;
      };
    };
    const err = parsed.error;
    if (!err) return false;
    if (err.status === "NOT_FOUND") return true;
    for (const d of err.details ?? []) {
      if (d.errorCode === "UNREGISTERED") return true;
    }
    const msg = (err.message ?? "").toLowerCase();
    return (
      msg.includes("unregistered") ||
      msg.includes("not a valid fcm registration token")
    );
  } catch {
    return bodyText.includes("UNREGISTERED");
  }
}

function stringifyData(raw: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (v !== null && v !== undefined) {
      const s = String(v).trim();
      if (s.length > 0) out[k] = s;
    }
  }
  return out;
}

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  const maxLen = Math.max(ab.length, bb.length);
  let diff = ab.length ^ bb.length;
  for (let i = 0; i < maxLen; i++) {
    diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  }
  return diff === 0;
}

function verifyWebhookAuth(req: Request): boolean {
  const expectedSecret = Deno.env.get("WEBHOOK_SECRET")?.trim() ?? "";
  // Fail closed when WEBHOOK_SECRET is missing so unauthenticated callers cannot trigger push notifications.
  if (!expectedSecret) return false;
  const headerSecret =
    req.headers.get("x-webhook-secret")?.trim() ??
    req.headers.get("x-hiqeo-webhook-secret")?.trim() ??
    "";
  return headerSecret.length > 0 && timingSafeEqual(headerSecret, expectedSecret);
}

function parseUuidArray(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw
      .map((item) => String(item ?? "").trim())
      .filter((s) => UUID_RE.test(s));
  }
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
      return trimmed
        .slice(1, -1)
        .split(",")
        .map((s) => s.replace(/^"+|"+$/g, "").trim())
        .filter((s) => UUID_RE.test(s));
    }
  }
  return [];
}

async function fetchSenderProfile(
  admin: ReturnType<typeof createClient>,
  userId: string,
  fallbackName = "Pendaki",
): Promise<SenderProfile> {
  if (!UUID_RE.test(userId)) {
    return { name: fallbackName, username: "", avatarUrl: "" };
  }
  try {
    const { data } = await admin
      .from("profiles")
      .select("full_name, username, avatar_url")
      .eq("id", userId)
      .maybeSingle();
    const fullName = String(data?.full_name ?? "").trim();
    const username = String(data?.username ?? "").trim();
    const avatarUrl = String(data?.avatar_url ?? "").trim();
    const name = fullName || (username ? username : fallbackName);
    return { name, username, avatarUrl };
  } catch {
    return { name: fallbackName, username: "", avatarUrl: "" };
  }
}

async function fetchRoomMutes(
  admin: ReturnType<typeof createClient>,
  roomType: "group" | "community",
  roomId: string,
  userIds: string[],
): Promise<Map<string, MuteState>> {
  const mutes = new Map<string, MuteState>();
  if (!roomId || userIds.length === 0) return mutes;

  try {
    const { data } = await admin
      .from("chat_notification_mutes")
      .select("user_id, muted_until")
      .eq("room_type", roomType)
      .eq("room_id", roomId)
      .in("user_id", userIds);

    const nowMs = Date.now();
    for (const row of data ?? []) {
      const uid = String((row as { user_id?: string }).user_id ?? "").trim();
      const rawUntil = (row as { muted_until?: string | null }).muted_until;
      if (!uid || !rawUntil) continue;
      const untilDate = new Date(rawUntil);
      const untilMs = untilDate.getTime();
      if (!Number.isFinite(untilMs) || untilMs <= nowMs) continue;
      const forever = untilDate.getUTCFullYear() >= 9999;
      mutes.set(uid, { muted: true, forever });
    }
  } catch {
    // Fail open for notifications if mute table is not yet migrated.
  }

  return mutes;
}

async function insertInboxNotifications(
  admin: ReturnType<typeof createClient>,
  rows: InboxInsertRow[],
): Promise<number> {
  if (rows.length === 0) return 0;
  try {
    const { error } = await admin.from("user_notifications").insert(rows);
    if (error) return 0;
    return rows.length;
  } catch {
    return 0;
  }
}

async function sendFcmDispatches(
  admin: ReturnType<typeof createClient>,
  sa: ServiceAccount,
  dispatches: FcmDispatch[],
): Promise<{ sent: number; total: number; cleanedStaleTokens: number }> {
  const allRecipients = new Set<string>();
  for (const d of dispatches) {
    for (const uid of d.userIds) {
      if (uid) allRecipients.add(uid);
    }
  }
  if (allRecipients.size === 0) {
    return { sent: 0, total: 0, cleanedStaleTokens: 0 };
  }

  const recipientArray = Array.from(allRecipients);
  const [{ data: profileRows }, { data: deviceTokenRows }] = await Promise.all([
    admin.from("profiles").select("id, fcm_token").in("id", recipientArray),
    admin
      .from("user_fcm_tokens")
      .select("user_id, token, platform")
      .in("user_id", recipientArray),
  ]);

  const tokensByUser = new Map<string, Map<string, "android" | "ios">>();
  for (const row of profileRows ?? []) {
    const uid = String((row as { id?: string }).id ?? "").trim();
    const token = String(
      (row as { fcm_token?: string | null }).fcm_token ?? "",
    ).trim();
    if (uid && token) {
      let map = tokensByUser.get(uid);
      if (!map) {
        map = new Map<string, "android" | "ios">();
        tokensByUser.set(uid, map);
      }
      if (!map.has(token)) {
        map.set(token, "android");
      }
    }
  }
  for (const row of deviceTokenRows ?? []) {
    const uid = String((row as { user_id?: string }).user_id ?? "").trim();
    const token = String((row as { token?: string | null }).token ?? "").trim();
    const rawPlatform = String(
      (row as { platform?: string | null }).platform ?? "",
    ).trim().toLowerCase();
    const platform: "android" | "ios" = rawPlatform === "ios" ? "ios" : "android";
    if (uid && token) {
      let map = tokensByUser.get(uid);
      if (!map) {
        map = new Map<string, "android" | "ios">();
        tokensByUser.set(uid, map);
      }
      map.set(token, platform);
    }
  }

  let totalTokens = 0;
  const dispatchTokenLists: Array<{
    dispatch: FcmDispatch;
    tokens: Array<{ token: string; platform: "android" | "ios" }>;
  }> = [];
  for (const d of dispatches) {
    const tokenMap = new Map<string, "android" | "ios">();
    for (const uid of d.userIds) {
      const userTokens = tokensByUser.get(uid);
      if (userTokens) {
        for (const [t, plat] of userTokens.entries()) {
          if (!tokenMap.has(t) || plat === "ios") {
            tokenMap.set(t, plat);
          }
        }
      }
    }
    if (tokenMap.size > 0) {
      const tokens = Array.from(tokenMap.entries()).map(([token, platform]) => ({
        token,
        platform,
      }));
      totalTokens += tokens.length;
      dispatchTokenLists.push({ dispatch: d, tokens });
    }
  }

  if (totalTokens === 0) {
    return { sent: 0, total: 0, cleanedStaleTokens: 0 };
  }

  const accessToken = await fetchGoogleAccessToken(sa);
  const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.projectId}/messages:send`;

  let sent = 0;
  const staleTokens = new Set<string>();

  for (const item of dispatchTokenLists) {
    const { dispatch, tokens } = item;
    const baseData = {
      ...dispatch.data,
      title: dispatch.title,
      body: dispatch.body,
      channel_id: dispatch.channelId,
      urgent: dispatch.urgent ? "true" : "false",
      silent: dispatch.silent ? "true" : "false",
    };
    const threadId =
      dispatch.data.room_type && dispatch.data.room_id
        ? `${dispatch.data.room_type}:${dispatch.data.room_id}`
        : undefined;

    for (const { token, platform } of tokens) {
      const fcmMessage =
        platform === "ios"
          ? dispatch.silent
            ? {
                message: {
                  token,
                  data: baseData,
                  apns: {
                    headers: {
                      "apns-push-type": "background",
                      "apns-priority": "5",
                    },
                    payload: {
                      aps: {
                        "content-available": 1,
                      },
                    },
                  },
                },
              }
            : {
                message: {
                  token,
                  notification: { title: dispatch.title, body: dispatch.body },
                  data: baseData,
                  apns: {
                    headers: {
                      "apns-priority": "10",
                    },
                    payload: {
                      aps: {
                        sound: "default",
                        ...(threadId ? { "thread-id": threadId } : {}),
                        ...(dispatch.urgent
                          ? { "interruption-level": "time-sensitive" }
                          : {}),
                      },
                    },
                  },
                },
              }
          : {
              // Android data-only HIGH priority agar hiqeoFirebaseMessagingBackgroundHandler
              // selalu dipanggil untuk mengelompokkan & menghitung pesan belum dibaca.
              message: {
                token,
                data: baseData,
                android: {
                  priority: "HIGH",
                },
              },
            };

      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmMessage),
      });

      if (res.ok) {
        sent++;
      } else {
        const errText = await res.text();
        if (isUnregisteredFcmError(res.status, errText)) {
          staleTokens.add(token);
        }
      }
    }
  }

  const staleList = Array.from(staleTokens);
  if (staleList.length > 0) {
    await Promise.all([
      admin
        .from("profiles")
        .update({ fcm_token: null })
        .in("fcm_token", staleList),
      admin.from("user_fcm_tokens").delete().in("token", staleList),
    ]);
  }

  return { sent, total: totalTokens, cleanedStaleTokens: staleList.length };
}

async function dispatchSosWhatsAppHook(
  admin: ReturnType<typeof createClient>,
  authorId: string,
  message: string,
): Promise<{ configured: boolean; sent: number }> {
  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN")?.trim() ?? "";
  const phoneNumberId =
    Deno.env.get("WHATSAPP_PHONE_NUMBER_ID")?.trim() ?? "";
  const templateName =
    Deno.env.get("WHATSAPP_SOS_TEMPLATE_NAME")?.trim() ?? "";
  if (!accessToken || !phoneNumberId || !UUID_RE.test(authorId) || !message) {
    return { configured: false, sent: 0 };
  }

  try {
    const { data: rows } = await admin
      .from("emergency_contacts")
      .select("phone_e164")
      .eq("user_id", authorId)
      .eq("contact_kind", "phone")
      .eq("consent_status", "granted");

    const e164Re = /^\+[0-9]{8,15}$/;
    const phones = Array.from(
      new Set(
        (rows ?? [])
          .map((r: { phone_e164?: string | null }) =>
            String(r.phone_e164 ?? "").trim()
          )
          .filter((p: string) => e164Re.test(p)),
      ),
    );
    if (phones.length === 0) return { configured: true, sent: 0 };

    const endpoint =
      `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`;
    const settled = await Promise.allSettled(
      phones.map(async (phone) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 4000);
        try {
          const waBody = templateName
            ? {
                messaging_product: "whatsapp",
                to: phone.replace(/^\+/, ""),
                type: "template",
                template: {
                  name: templateName,
                  language: { code: "id" },
                  components: [
                    {
                      type: "body",
                      parameters: [{ type: "text", text: message.slice(0, 900) }],
                    },
                  ],
                },
              }
            : {
                messaging_product: "whatsapp",
                to: phone.replace(/^\+/, ""),
                type: "text",
                text: { preview_url: true, body: message },
              };
          const res = await fetch(endpoint, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify(waBody),
            signal: controller.signal,
          });
          return res.ok;
        } finally {
          clearTimeout(timer);
        }
      }),
    );
    const sent = settled.filter(
      (r) => r.status === "fulfilled" && r.value === true,
    ).length;
    return { configured: true, sent };
  } catch {
    return { configured: true, sent: 0 };
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  if (!verifyWebhookAuth(req)) {
    return json({ error: "unauthorized" }, 401);
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const table = String(payload.table ?? "").trim();
  const eventType = String(payload.type ?? "INSERT").toUpperCase();
  const record = payload.record;
  const oldRecord = payload.old_record ?? null;
  if (!record) {
    return json({ error: "missing_record" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "supabase_not_configured" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const dispatches: FcmDispatch[] = [];
  const inboxRows: InboxInsertRow[] = [];

  if (table === "group_messages") {
    if (eventType !== "INSERT" || record.is_deleted === true) {
      return json({ skipped: "group_message_not_new_active_insert" });
    }
    const groupId = String(record.group_id ?? "").trim();
    const senderId = String(record.sender_id ?? "").trim();
    const messageId = String(record.client_id ?? record.id ?? "").trim();
    if (!groupId) return json({ skipped: "missing_group_id" });

    const [{ data: groupRow }, { data: members }, senderProf] =
      await Promise.all([
        admin
          .from("groups")
          .select("name, avatar_url")
          .eq("id", groupId)
          .maybeSingle(),
        admin.from("group_members").select("user_id").eq("group_id", groupId),
        fetchSenderProfile(admin, senderId, "Anggota"),
      ]);

    const rawRecipients = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== senderId);

    const mutes = await fetchRoomMutes(admin, "group", groupId, rawRecipients);
    const pushUserIds = rawRecipients.filter((uid) => !mutes.get(uid)?.muted);

    const groupName = String(groupRow?.name ?? "Grup Pendakian");
    const groupAvatarUrl = String(groupRow?.avatar_url ?? "").trim();
    const senderHandle =
      (senderProf.username || senderProf.name || "anggota").replace(/^@+/, "");
    const messageText = `Ada pesan baru dari ${senderHandle}`;
    const body = messageText;

    if (pushUserIds.length > 0) {
      dispatches.push({
        userIds: pushUserIds,
        title: groupName,
        body,
        channelId: "hiqeo_group_messages",
        urgent: false,
        data: stringifyData({
          type: "group_chat",
          target_id: groupId,
          group_id: groupId,
          room_type: "group",
          room_id: groupId,
          room_name: groupName,
          room_avatar_url: groupAvatarUrl,
          sender_id: senderId,
          sender_name: senderProf.name,
          sender_username: senderHandle,
          sender_avatar_url: senderProf.avatarUrl,
          message_text: messageText,
          message_id: messageId,
          sent_at: String(record.created_at ?? ""),
        }),
      });
    }
  } else if (table === "community_messages") {
    const isSoftDelete =
      eventType === "UPDATE" &&
      record.is_deleted === true &&
      oldRecord?.is_deleted !== true;
    if (!isSoftDelete && (eventType !== "INSERT" || record.is_deleted === true)) {
      return json({ skipped: "community_message_not_new_active_insert" });
    }
    const communityId = String(record.community_id ?? "").trim();
    const senderId = String(record.sender_id ?? "").trim();
    const messageId = String(record.id ?? "").trim();
    if (!communityId) return json({ skipped: "missing_community_id" });

    const [{ data: commRow }, { data: members }, senderProf] =
      await Promise.all([
        admin
          .from("communities")
          .select("name, avatar_url")
          .eq("id", communityId)
          .maybeSingle(),
        admin
          .from("community_members")
          .select("user_id")
          .eq("community_id", communityId),
        fetchSenderProfile(
          admin,
          senderId,
          String(record.sender_name ?? "Pendaki").trim() || "Pendaki",
        ),
      ]);

    const memberIds = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== senderId);
    const commName = String(commRow?.name ?? "Komunitas Hiqeo");
    const commAvatarUrl = String(commRow?.avatar_url ?? "").trim();

    if (isSoftDelete) {
      if (messageId) {
        try {
          await admin
            .from("user_notifications")
            .update({ body: "Pesan telah dihapus" })
            .eq("room_type", "community")
            .eq("room_id", communityId)
            .eq("message_id", messageId);
        } catch {
          // Best-effort inbox text alignment.
        }
      }

      if (memberIds.length > 0 && messageId) {
        dispatches.push({
          userIds: memberIds,
          title: commName,
          body: "Pesan telah dihapus",
          channelId: "hiqeo_community_messages",
          urgent: false,
          silent: true,
          data: stringifyData({
            type: "community_message_deleted",
            target_id: communityId,
            community_id: communityId,
            room_type: "community",
            room_id: communityId,
            room_name: commName,
            room_avatar_url: commAvatarUrl,
            sender_id: senderId,
            message_id: messageId,
            replacement_text: "Pesan telah dihapus",
          }),
        });
      }
    } else {
      const memberSet = new Set(memberIds);

      const mentionedSet = new Set(
        parseUuidArray(record.mentioned_user_ids).filter((uid) =>
          memberSet.has(uid)
        ),
      );
      const mentionRecipients = Array.from(mentionedSet);
      const regularRecipients = memberIds.filter((uid) => !mentionedSet.has(uid));

      const mutes = await fetchRoomMutes(
        admin,
        "community",
        communityId,
        memberIds,
      );
      const msgType = String(record.message_type ?? "text");
      const content = String(record.content ?? "").trim();
      const snippet =
        msgType === "image"
          ? "Foto baru"
          : msgType === "video"
          ? "Video baru"
          : content.length > 80
          ? `${content.slice(0, 77)}...`
          : content || "Pesan baru";

      if (mentionRecipients.length > 0) {
        const mentionTitle = `${senderProf.name} menyebutmu di ${commName}`;
        const mentionBody = snippet;
        const mentionData = stringifyData({
          type: "community_mention",
          target_id: communityId,
          community_id: communityId,
          room_type: "community",
          room_id: communityId,
          room_name: commName,
          room_avatar_url: commAvatarUrl,
          sender_id: senderId,
          sender_name: senderProf.name,
          sender_avatar_url: senderProf.avatarUrl,
          message_text: snippet,
          message_id: messageId,
          sent_at: String(record.created_at ?? ""),
        });

        // Record @username mention in Home Inbox regardless of mute state.
        for (const uid of mentionRecipients) {
          inboxRows.push({
            user_id: uid,
            type: "community_mention",
            title: mentionTitle,
            body: mentionBody,
            actor_id: UUID_RE.test(senderId) ? senderId : null,
            target_id: communityId,
            room_type: "community",
            room_id: communityId,
            message_id: messageId || null,
            data: mentionData,
          });
        }

        // Mentions break through temporary mutes (1 day / 1 week), suppressed only on forever mute (9999-12-31).
        const mentionPushIds = mentionRecipients.filter(
          (uid) => !mutes.get(uid)?.forever,
        );
        if (mentionPushIds.length > 0) {
          dispatches.push({
            userIds: mentionPushIds,
            title: mentionTitle,
            body: mentionBody,
            channelId: "hiqeo_mentions",
            urgent: false,
            data: mentionData,
          });
        }
      }

      const regularPushIds = regularRecipients.filter(
        (uid) => !mutes.get(uid)?.muted,
      );
      if (regularPushIds.length > 0) {
        dispatches.push({
          userIds: regularPushIds,
          title: commName,
          body: `${senderProf.name}: ${snippet}`,
          channelId: "hiqeo_community_messages",
          urgent: false,
          data: stringifyData({
            type: "community_chat",
            target_id: communityId,
            community_id: communityId,
            room_type: "community",
            room_id: communityId,
            room_name: commName,
            room_avatar_url: commAvatarUrl,
            sender_id: senderId,
            sender_name: senderProf.name,
            sender_avatar_url: senderProf.avatarUrl,
            message_text: snippet,
            message_id: messageId,
            sent_at: String(record.created_at ?? ""),
          }),
        });
      }
    }
  } else if (table === "group_hike_prep") {
    const groupId = String(record.group_id ?? "").trim();
    const organizerId = String(record.organizer_user_id ?? "").trim();
    const inviteId = String(record.invite_id ?? "").trim();
    const mountainId = String(record.mountain_id ?? "").trim();
    const mountainName = String(record.mountain_name ?? "Gunung");
    const trailId = String(record.trail_id ?? "").trim();
    const trailName = String(record.trail_name ?? "").trim();
    if (!groupId) return json({ skipped: "missing_group_id" });

    const isBecomingActive =
      record.status === "active" &&
      !(
        eventType === "UPDATE" &&
        oldRecord &&
        oldRecord.status === "active" &&
        oldRecord.invite_id === record.invite_id
      );
    const isBecomingStarted =
      eventType === "UPDATE" &&
      record.status === "started" &&
      oldRecord?.status !== "started";
    const isBecomingCancelled =
      eventType === "UPDATE" &&
      record.status === "cancelled" &&
      oldRecord?.status === "active";

    if (!isBecomingActive && !isBecomingStarted && !isBecomingCancelled) {
      return json({ skipped: "prep_status_update_ignored" });
    }

    const startedBy = String(record.started_by ?? organizerId).trim() || organizerId;
    const [{ data: groupRow }, { data: members }, organizerProf, starterProf] =
      await Promise.all([
        admin
          .from("groups")
          .select("name, avatar_url")
          .eq("id", groupId)
          .maybeSingle(),
        admin.from("group_members").select("user_id").eq("group_id", groupId),
        fetchSenderProfile(
          admin,
          organizerId,
          String(record.organizer_name ?? "Ketua Rombongan"),
        ),
        isBecomingStarted
          ? fetchSenderProfile(
              admin,
              startedBy,
              String(record.organizer_name ?? "Ketua Rombongan"),
            )
          : Promise.resolve({ name: "", username: "", avatarUrl: "" }),
      ]);

    const actorId = isBecomingStarted ? startedBy : organizerId;
    const recipients = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== actorId);
    const mutes = await fetchRoomMutes(admin, "group", groupId, recipients);
    const pushUserIds = recipients.filter((uid) => !mutes.get(uid)?.muted);

    const groupName = String(groupRow?.name ?? "Grup Pendakian");
    const groupAvatarUrl = String(groupRow?.avatar_url ?? "").trim();
    const msgId = String(record.invite_message_id ?? inviteId);

    if (isBecomingStarted) {
      const startedAt =
        String(record.started_at ?? "").trim() || new Date().toISOString();
      const title = `Pendakian Dimulai · ${groupName}`;
      const body = `${starterProf.name} memulai pendakian ${mountainName}. Peta jalur & tracking dibuka otomatis.`;
      const payloadData = stringifyData({
        type: "hike_started",
        target_id: groupId,
        group_id: groupId,
        room_type: "group",
        room_id: groupId,
        room_name: groupName,
        room_avatar_url: groupAvatarUrl,
        invite_id: inviteId,
        mountain_id: mountainId,
        mountain_name: mountainName,
        route_id: trailId,
        trail_id: trailId,
        trail_name: trailName,
        started_at: startedAt,
        started_by: startedBy,
        sender_id: startedBy,
        sender_name: starterProf.name,
        sender_avatar_url: starterProf.avatarUrl,
        route: "/peta/jalur",
        message_id: msgId,
      });

      for (const uid of recipients) {
        inboxRows.push({
          user_id: uid,
          type: "hike_started",
          title,
          body,
          actor_id: UUID_RE.test(startedBy) ? startedBy : null,
          target_id: groupId,
          room_type: "group",
          room_id: groupId,
          message_id: msgId || null,
          data: payloadData,
        });
      }

      // Bypass soft room mutes so every group member auto-joins tracking cleanly.
      if (recipients.length > 0) {
        dispatches.push({
          userIds: recipients,
          title,
          body,
          channelId: "hiqeo_social_prep",
          urgent: true,
          data: payloadData,
        });
      }
    } else if (isBecomingActive) {
      const title = `Ajakan Mendaki · ${groupName}`;
      const body = `${organizerProf.name} mengajak mendaki ${mountainName}. Ketuk Siap di chat grup!`;
      const payloadData = stringifyData({
        type: "group_ready",
        target_id: groupId,
        group_id: groupId,
        room_type: "group",
        room_id: groupId,
        room_name: groupName,
        room_avatar_url: groupAvatarUrl,
        invite_id: inviteId,
        mountain_name: mountainName,
        sender_id: organizerId,
        sender_name: organizerProf.name,
        sender_avatar_url: organizerProf.avatarUrl,
        message_id: msgId,
      });

      for (const uid of recipients) {
        inboxRows.push({
          user_id: uid,
          type: "group_ready",
          title,
          body,
          actor_id: UUID_RE.test(organizerId) ? organizerId : null,
          target_id: groupId,
          room_type: "group",
          room_id: groupId,
          message_id: msgId || null,
          data: payloadData,
        });
      }

      if (pushUserIds.length > 0) {
        dispatches.push({
          userIds: pushUserIds,
          title,
          body,
          channelId: "hiqeo_social_prep",
          urgent: false,
          data: payloadData,
        });
      }
    } else if (isBecomingCancelled) {
      const title = `Ajakan Dibatalkan · ${groupName}`;
      const body = `${organizerProf.name} membatalkan ajakan mendaki ${mountainName}.`;
      const payloadData = stringifyData({
        type: "group_hike_cancelled",
        target_id: groupId,
        group_id: groupId,
        room_type: "group",
        room_id: groupId,
        room_name: groupName,
        room_avatar_url: groupAvatarUrl,
        invite_id: inviteId,
        mountain_name: mountainName,
        sender_id: organizerId,
        sender_name: organizerProf.name,
        sender_avatar_url: organizerProf.avatarUrl,
        message_id: msgId,
      });

      for (const uid of recipients) {
        inboxRows.push({
          user_id: uid,
          type: "group_hike_cancelled",
          title,
          body,
          actor_id: UUID_RE.test(organizerId) ? organizerId : null,
          target_id: groupId,
          room_type: "group",
          room_id: groupId,
          message_id: msgId || null,
          data: payloadData,
        });
      }

      if (pushUserIds.length > 0) {
        dispatches.push({
          userIds: pushUserIds,
          title,
          body,
          channelId: "hiqeo_social_prep",
          urgent: false,
          data: payloadData,
        });
      }
    }
  } else if (table === "invitations") {
    if (eventType !== "INSERT" || record.status !== "pending") {
      return json({ skipped: "invitation_not_pending_insert" });
    }
    const invitationId = String(record.id ?? "").trim();
    const groupId = String(record.group_id ?? "").trim();
    const inviterId = String(record.inviter_id ?? "").trim();
    const inviteeId = String(record.invitee_id ?? "").trim();
    if (!inviteeId || !groupId) return json({ skipped: "missing_invitation_party" });

    const [{ data: groupRow }, inviterProf] = await Promise.all([
      admin
        .from("groups")
        .select("name, avatar_url")
        .eq("id", groupId)
        .maybeSingle(),
      fetchSenderProfile(admin, inviterId, "Pendaki"),
    ]);

    const groupName = String(groupRow?.name ?? "Grup Pendakian");
    const groupAvatarUrl = String(groupRow?.avatar_url ?? "").trim();
    const title = "Undangan Grup Pendakian";
    const body = `${inviterProf.name} mengundangmu bergabung ke grup ${groupName}.`;
    const payloadData = stringifyData({
      type: "group_invitation",
      target_id: invitationId || groupId,
      invitation_id: invitationId,
      group_id: groupId,
      room_type: "group",
      room_id: groupId,
      room_name: groupName,
      room_avatar_url: groupAvatarUrl,
      sender_id: inviterId,
      sender_name: inviterProf.name,
      sender_avatar_url: inviterProf.avatarUrl,
      message_id: invitationId,
    });

    inboxRows.push({
      user_id: inviteeId,
      type: "group_invitation",
      title,
      body,
      actor_id: UUID_RE.test(inviterId) ? inviterId : null,
      target_id: invitationId || groupId,
      room_type: "group",
      room_id: groupId,
      message_id: invitationId || null,
      data: payloadData,
    });

    dispatches.push({
      userIds: [inviteeId],
      title,
      body,
      channelId: "hiqeo_social_prep",
      urgent: false,
      data: payloadData,
    });
  } else if (table === "friendships") {
    if (record.status !== "pending") {
      return json({ skipped: "friendship_not_pending" });
    }
    const requesterId = String(record.requester_id ?? "").trim();
    const addresseeId = String(record.addressee_id ?? "").trim();
    const friendshipId = String(record.id ?? "").trim();
    if (!addresseeId) return json({ skipped: "missing_addressee" });

    const reqProf = await fetchSenderProfile(admin, requesterId, "Pendaki");
    const title = "Permintaan Pertemanan";
    const body = `${reqProf.name} ingin berteman denganmu.`;
    const payloadData = stringifyData({
      type: "friend_request",
      target_id: friendshipId || requesterId,
      friendship_id: friendshipId,
      requester_id: requesterId,
      sender_id: requesterId,
      sender_name: reqProf.name,
      sender_avatar_url: reqProf.avatarUrl,
      message_id: friendshipId,
    });

    inboxRows.push({
      user_id: addresseeId,
      type: "friend_request",
      title,
      body,
      actor_id: UUID_RE.test(requesterId) ? requesterId : null,
      target_id: friendshipId || requesterId,
      message_id: friendshipId || null,
      data: payloadData,
    });

    dispatches.push({
      userIds: [addresseeId],
      title,
      body,
      channelId: "hiqeo_social_prep",
      urgent: false,
      data: payloadData,
    });
  } else if (table === "sos_events") {
    if (record.status && record.status !== "active") {
      return json({ skipped: "sos_not_active" });
    }
    if (eventType === "UPDATE" && oldRecord?.status === "active") {
      return json({ skipped: "sos_already_active" });
    }
    const authorId = String(record.author_id ?? record.user_id ?? "").trim();
    const groupId = String(record.group_id ?? "").trim();
    const sosId = String(record.id ?? "").trim();
    const mountainName = String(record.mountain_name ?? "").trim();
    const lat = record.lat != null ? Number(record.lat).toFixed(5) : "";
    const lon = record.lon != null ? Number(record.lon).toFixed(5) : "";
    const alt =
      record.altitude_m != null
        ? `${Math.round(Number(record.altitude_m))} mdpl`
        : "";
    const bat =
      record.battery_pct != null ? `Baterai ${record.battery_pct}%` : "";

    const recipients = new Set<string>();
    let groupName = "";
    let groupAvatarUrl = "";
    if (groupId) {
      const [{ data: groupRow }, { data: members }] = await Promise.all([
        admin
          .from("groups")
          .select("name, avatar_url")
          .eq("id", groupId)
          .maybeSingle(),
        admin.from("group_members").select("user_id").eq("group_id", groupId),
      ]);
      groupName = String(groupRow?.name ?? "").trim();
      groupAvatarUrl = String(groupRow?.avatar_url ?? "").trim();
      for (const m of members ?? []) {
        const uid = String((m as { user_id?: string }).user_id ?? "");
        if (uid && uid !== authorId) recipients.add(uid);
      }
    }
    if (authorId) {
      const { data: contacts } = await admin
        .from("emergency_contacts")
        .select("contact_user_id")
        .eq("user_id", authorId)
        .eq("contact_kind", "hiqeo_account")
        .eq("consent_status", "granted");
      for (const c of contacts ?? []) {
        const uid = String(
          (c as { contact_user_id?: string }).contact_user_id ?? "",
        );
        if (uid && uid !== authorId) recipients.add(uid);
      }
    }

    const senderProf = await fetchSenderProfile(admin, authorId, "Pendaki");
    const targetUserIds = Array.from(recipients);
    const title = "DARURAT SOS HIQEO";
    const metaParts = [
      mountainName,
      lat && lon ? `${lat}, ${lon}` : "",
      alt,
      bat,
    ].filter((s) => s.length > 0);
    const body =
      metaParts.length > 0
        ? `${senderProf.name} mengirim sinyal SOS (${metaParts.join(" · ")})`
        : `${senderProf.name} membutuhkan bantuan darurat sekarang!`;
    const payloadData = stringifyData({
      type: "sos",
      target_id: sosId || groupId,
      sos_id: sosId,
      group_id: groupId,
      room_type: groupId ? "group" : "",
      room_id: groupId,
      room_name: groupName,
      room_avatar_url: groupAvatarUrl,
      sender_id: authorId,
      sender_name: senderProf.name,
      sender_avatar_url: senderProf.avatarUrl,
      message_id: sosId,
      mountain_name: mountainName,
      lat,
      lon,
      altitude_m: record.altitude_m != null ? String(record.altitude_m) : "",
      battery_pct: record.battery_pct != null ? String(record.battery_pct) : "",
    });

    for (const uid of targetUserIds) {
      inboxRows.push({
        user_id: uid,
        type: "sos",
        title,
        body,
        actor_id: UUID_RE.test(authorId) ? authorId : null,
        target_id: sosId || groupId || null,
        room_type: groupId ? "group" : null,
        room_id: UUID_RE.test(groupId) ? groupId : null,
        message_id: sosId || null,
        data: payloadData,
      });
    }

    // SOS ALWAYS bypasses all room mutes.
    if (targetUserIds.length > 0) {
      dispatches.push({
        userIds: targetUserIds,
        title,
        body,
        channelId: "hiqeo_sos_urgent",
        urgent: true,
        data: payloadData,
      });
    }
  } else if (table === "emergency_contacts") {
    if (
      record.contact_kind !== "hiqeo_account" ||
      record.consent_status !== "pending"
    ) {
      return json({ skipped: "not_pending_hiqeo_request" });
    }
    const requesterId = String(record.user_id ?? "").trim();
    const targetId = String(record.contact_user_id ?? "").trim();
    const reqId = String(record.id ?? "").trim();
    if (!targetId) return json({ skipped: "missing_target" });

    const reqProf = await fetchSenderProfile(admin, requesterId, "Pengguna Hiqeo");
    const senderLabel = reqProf.username ? `@${reqProf.username}` : reqProf.name;
    const title = "Permintaan Kontak Darurat";
    const body = `${senderLabel} ingin menambahkanmu sebagai kontak darurat SOS.`;
    const payloadData = stringifyData({
      type: "emergency_contact_request",
      target_id: reqId,
      requester_id: requesterId,
      sender_id: requesterId,
      sender_name: reqProf.name,
      sender_avatar_url: reqProf.avatarUrl,
      message_id: reqId,
    });

    inboxRows.push({
      user_id: targetId,
      type: "emergency_contact_request",
      title,
      body,
      actor_id: UUID_RE.test(requesterId) ? requesterId : null,
      target_id: reqId || null,
      message_id: reqId || null,
      data: payloadData,
    });

    dispatches.push({
      userIds: [targetId],
      title,
      body,
      channelId: "hiqeo_social_prep",
      urgent: false,
      data: payloadData,
    });
  } else {
    return json({ skipped: `unhandled_table_${table}` });
  }

  const inboxRecorded = await insertInboxNotifications(admin, inboxRows);

  if (dispatches.length === 0) {
    return json({ sent: 0, inboxRecorded, reason: "no_push_recipients" });
  }

  const sa = loadServiceAccount();
  if (!sa) {
    return json({
      skipped: "fcm_not_configured",
      inboxRecorded,
      dispatches: dispatches.length,
    });
  }

  const fcmPromise = sendFcmDispatches(admin, sa, dispatches);
  const waPromise =
    table === "sos_events" &&
    (!record.status || record.status === "active") &&
    String(record.author_id ?? record.user_id ?? "").trim().length > 0
      ? dispatchSosWhatsAppHook(
          admin,
          String(record.author_id ?? record.user_id ?? "").trim(),
          String(record.message ?? "").trim(),
        )
      : Promise.resolve({ configured: false, sent: 0 });

  const [fcmResult, whatsappResult] = await Promise.all([fcmPromise, waPromise]);
  return json({
    ...fcmResult,
    inboxRecorded,
    whatsapp: whatsappResult,
  });
});
