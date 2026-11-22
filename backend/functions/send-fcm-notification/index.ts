// Supabase Edge Function: send-fcm-notification
// Dipicu otomatis oleh Supabase Database Webhook / pg_net trigger untuk:
// 1. Pesan grup baru (`group_messages`)
// 2. Pesan komunitas baru (`community_messages`)
// 3. Permintaan pertemanan (`friendships`)
// 4. Ajakan tombol "Siap" pendakian grup (`group_hike_prep`)
// 5. Sinyal darurat SOS (`sos_events`)
// 6. Permintaan kontak darurat akun Hiqeo (`emergency_contacts`)
//
// Hanya memakai Supabase REST SDK (tanpa koneksi Postgres langsung). Bila nanti
// memakai koneksi PostgreSQL langsung di backend, WAJIB memakai Transaction
// Pooler (port 6543).
//
// Secrets (`supabase secrets set ...`):
// - FIREBASE_SERVICE_ACCOUNT_JSON : isi JSON service account Firebase
// - WEBHOOK_SECRET                : opsional, verifikasi x-hiqeo-webhook-secret

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function b64Url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
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
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const jwt = `${unsigned}.${b64Url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`oauth_token_failed_${res.status}`);
  }
  const data = await res.json();
  return String(data.access_token ?? "");
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
  if (!expectedSecret) return false;
  const headerSecret =
    req.headers.get("x-webhook-secret")?.trim() ??
    req.headers.get("x-hiqeo-webhook-secret")?.trim() ??
    "";
  return headerSecret.length > 0 && timingSafeEqual(headerSecret, expectedSecret);
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  if (!verifyWebhookAuth(req)) {
    return json({ error: "unauthorized" }, 401);
  }

  let payload: { table?: string; type?: string; record?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const table = String(payload.table ?? "");
  const record = payload.record;
  if (!record) return json({ error: "missing_record" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let targetUserIds: string[] = [];
  let title = "Hiqeo";
  let body = "";
  let data: Record<string, string> = {};
  let channelId = "hiqeo_social";

  if (table === "group_messages") {
    const groupId = String(record.group_id ?? "");
    const senderId = String(record.sender_id ?? "");
    if (!groupId) return json({ skipped: "missing_group_id" });

    const [{ data: groupRow }, { data: members }] = await Promise.all([
      admin.from("groups").select("name").eq("id", groupId).maybeSingle(),
      admin.from("group_members").select("user_id").eq("group_id", groupId),
    ]);
    targetUserIds = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== senderId);
    const groupName = String(groupRow?.name ?? "Grup Pendakian");
    title = groupName;
    body = "Ada pesan terenkripsi baru di grup.";
    data = {
      kind: "group_message",
      group_id: groupId,
      route: "/grup",
    };
  } else if (table === "community_messages") {
    const communityId = String(record.community_id ?? "");
    const senderId = String(record.sender_id ?? "");
    if (!communityId) return json({ skipped: "missing_community_id" });

    const [{ data: commRow }, { data: members }] = await Promise.all([
      admin.from("communities").select("name").eq("id", communityId).maybeSingle(),
      admin
        .from("community_members")
        .select("user_id")
        .eq("community_id", communityId),
    ]);
    targetUserIds = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== senderId);
    const commName = String(commRow?.name ?? "Komunitas Hiqeo");
    const senderName = String(record.sender_name ?? "Pendaki").trim() || "Pendaki";
    const msgType = String(record.message_type ?? "text");
    const content = String(record.content ?? "").trim();
    const snippet = msgType === "image"
      ? "📷 Foto"
      : msgType === "video"
      ? "🎥 Video"
      : (content.length > 80 ? `${content.slice(0, 77)}…` : content || "Pesan baru");

    title = commName;
    body = `${senderName}: ${snippet}`;
    data = {
      kind: "community_message",
      community_id: communityId,
      route: "/grup",
    };
  } else if (table === "friendships") {
    if (record.status !== "pending") {
      return json({ skipped: "friendship_not_pending" });
    }
    const requesterId = String(record.requester_id ?? "");
    const addresseeId = String(record.addressee_id ?? "");
    if (!addresseeId) return json({ skipped: "missing_addressee" });

    const { data: reqProf } = await admin
      .from("profiles")
      .select("username, full_name")
      .eq("id", requesterId)
      .maybeSingle();
    const senderLabel = reqProf?.full_name?.trim()
      ? String(reqProf.full_name).trim()
      : (reqProf?.username ? `@${reqProf.username}` : "Pendaki");

    targetUserIds = [addresseeId];
    title = "Permintaan Pertemanan";
    body = `${senderLabel} ingin berteman denganmu.`;
    data = {
      kind: "friend_request",
      friendship_id: String(record.id ?? ""),
      requester_id: requesterId,
      route: "/teman",
    };
  } else if (table === "group_hike_prep") {
    if (record.status !== "active") {
      return json({ skipped: "prep_not_active" });
    }
    const groupId = String(record.group_id ?? "");
    const organizerId = String(record.organizer_user_id ?? "");
    const organizerName = String(record.organizer_name ?? "Ketua Rombongan");
    const mountainName = String(record.mountain_name ?? "Gunung");
    if (!groupId) return json({ skipped: "missing_group_id" });

    const [{ data: groupRow }, { data: members }] = await Promise.all([
      admin.from("groups").select("name").eq("id", groupId).maybeSingle(),
      admin.from("group_members").select("user_id").eq("group_id", groupId),
    ]);
    targetUserIds = (members ?? [])
      .map((m: { user_id?: string }) => String(m.user_id ?? ""))
      .filter((uid: string) => uid.length > 0 && uid !== organizerId);
    const groupName = String(groupRow?.name ?? "Grup Pendakian");
    title = `Ajakan Mendaki · ${groupName}`;
    body = `${organizerName} mengajak mendaki ${mountainName}. Ketuk Siap di chat grup!`;
    data = {
      kind: "group_hike_invite",
      group_id: groupId,
      invite_id: String(record.invite_id ?? ""),
      mountain_name: mountainName,
      route: "/grup",
    };
  } else if (table === "sos_events") {
    if (record.status && record.status !== "active") {
      return json({ skipped: "sos_not_active" });
    }
    const userId = String(record.author_id ?? record.user_id ?? "");
    const groupId = String(record.group_id ?? "");
    const mountainName = String(record.mountain_name ?? "").trim();
    const lat = record.lat != null ? Number(record.lat).toFixed(5) : "";
    const lon = record.lon != null ? Number(record.lon).toFixed(5) : "";
    const alt = record.altitude_m != null ? `${Math.round(Number(record.altitude_m))} mdpl` : "";
    const bat = record.battery_pct != null ? `Baterai ${record.battery_pct}%` : "";
    const recipients = new Set<string>();

    if (groupId) {
      const { data: members } = await admin
        .from("group_members")
        .select("user_id")
        .eq("group_id", groupId);
      for (const m of members ?? []) {
        const uid = String((m as { user_id?: string }).user_id ?? "");
        if (uid && uid !== userId) recipients.add(uid);
      }
    }
    if (userId) {
      const { data: contacts } = await admin
        .from("emergency_contacts")
        .select("contact_user_id")
        .eq("user_id", userId)
        .eq("contact_kind", "hiqeo_account")
        .eq("consent_status", "granted");
      for (const c of contacts ?? []) {
        const uid = String((c as { contact_user_id?: string }).contact_user_id ?? "");
        if (uid && uid !== userId) recipients.add(uid);
      }
    }

    const { data: senderProf } = await admin
      .from("profiles")
      .select("username, full_name")
      .eq("id", userId)
      .maybeSingle();
    const senderLabel = senderProf?.full_name?.trim()
      ? String(senderProf.full_name).trim()
      : (senderProf?.username ? `@${senderProf.username}` : "Pendaki");

    targetUserIds = Array.from(recipients);
    channelId = "hiqeo_sos_urgent";
    title = "🚨 SINYAL SOS DARURAT";
    const metaParts = [
      mountainName,
      lat && lon ? `${lat}, ${lon}` : "",
      alt,
      bat,
    ].filter((s) => s.length > 0);
    body = metaParts.length > 0
      ? `${senderLabel} mengirim SOS (${metaParts.join(" · ")})`
      : `${senderLabel} membutuhkan bantuan darurat sekarang!`;
    data = {
      kind: "sos_alert",
      sos_id: String(record.id ?? ""),
      group_id: groupId,
      sender_id: userId,
      route: groupId ? "/grup" : "/sos",
    };
  } else if (table === "emergency_contacts") {
    if (record.contact_kind !== "hiqeo_account" || record.consent_status !== "pending") {
      return json({ skipped: "not_pending_hiqeo_request" });
    }
    const requesterId = String(record.user_id ?? "");
    const targetId = String(record.contact_user_id ?? "");
    if (!targetId) return json({ skipped: "missing_target" });

    const { data: reqProf } = await admin
      .from("profiles")
      .select("username, full_name")
      .eq("id", requesterId)
      .maybeSingle();
    const senderLabel = reqProf?.username
      ? `@${reqProf.username}`
      : (reqProf?.full_name ?? "Pengguna Hiqeo");

    targetUserIds = [targetId];
    title = "Permintaan Kontak Darurat";
    body = `${senderLabel} ingin menambahkanmu sebagai kontak darurat SOS.`;
    data = {
      kind: "emergency_contact_request",
      request_id: String(record.id ?? ""),
      requester_id: requesterId,
      route: "/profil",
    };
  } else {
    return json({ skipped: `unhandled_table_${table}` });
  }

  if (targetUserIds.length === 0) return json({ sent: 0, reason: "no_recipients" });

  const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!saRaw) {
    return json({ skipped: "fcm_not_configured", recipients: targetUserIds.length });
  }

  const { data: tokenRows } = await admin
    .from("user_fcm_tokens")
    .select("token")
    .in("user_id", targetUserIds);
  const tokens = Array.from(
    new Set(
      (tokenRows ?? [])
        .map((r: { token?: string }) => String(r.token ?? ""))
        .filter((t: string) => t.length > 0),
    ),
  );
  if (tokens.length === 0) return json({ sent: 0 });

  const sa = JSON.parse(saRaw) as ServiceAccount;
  const accessToken = await fetchGoogleAccessToken(sa);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  let sent = 0;
  for (const token of tokens) {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: { channel_id: channelId },
          },
        },
      }),
    });
    if (res.ok) sent++;
  }

  return json({ sent, total: tokens.length });
});
