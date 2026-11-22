// Supabase Edge Function: r2-presign
// Generates a 60-second Presigned PUT URL for Cloudflare R2 using AWS S3 v3
// after JWT auth, MIME allowlist, path isolation, and content-length enforcement.
// Always returns a clean, normalized HTTPS publicUrl (never a presigned GET URL
// and never containing duplicate path slashes).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "npm:@aws-sdk/client-s3@3.682.0";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3.682.0";

const PRESIGN_EXPIRES_SECONDS = 60;
const MAX_AVATAR_BYTES = 2 * 1024 * 1024;
const MAX_COMMUNITY_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_COMMUNITY_VIDEO_BYTES = 50 * 1024 * 1024;

const UUID_PATTERN = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const UUID_RE = new RegExp(`^${UUID_PATTERN}$`, "i");
const SAFE_KEY_RE = /^[A-Za-z0-9/_.-]+$/;
const COMMUNITY_AVATAR_KEY_RE = new RegExp(
  `^community-avatars/(${UUID_PATTERN})\\.webp$`,
  "i",
);
const GROUP_AVATAR_KEY_RE = new RegExp(
  `^group-avatars/(${UUID_PATTERN})\\.webp$`,
  "i",
);
const COMMUNITY_MEDIA_KEY_RE = new RegExp(
  `^community-media/(${UUID_PATTERN})/(?:(${UUID_PATTERN})/)?((?:\\d+_)?${UUID_PATTERN}\\.(webp|jpg|jpeg|png|mp4|mov|webm))$`,
  "i",
);

const AVATAR_READ_KEY_RE = new RegExp(
  `^avatars/${UUID_PATTERN}\\.(webp|jpg|jpeg|png)$`,
  "i",
);

const COMMUNITY_AVATAR_READ_KEY_RE = new RegExp(
  `^community-avatars/${UUID_PATTERN}\\.(webp|jpg|jpeg|png)$`,
  "i",
);

const GROUP_AVATAR_READ_KEY_RE = new RegExp(
  `^group-avatars/${UUID_PATTERN}\\.(webp|jpg|jpeg|png)$`,
  "i",
);

const MAX_PROXY_BYTES = 25 * 1024 * 1024;
const GET_PRESIGN_EXPIRES_SECONDS = 3600;

function extractKeyFromUrlOrKey(
  rawKey: unknown,
  rawUrl: unknown,
  bucketName?: string,
): string {
  const direct = normalizeObjectKey(String(rawKey ?? ""));
  if (direct) return direct;
  const urlStr = String(rawUrl ?? "").trim();
  if (!urlStr) return "";
  try {
    const parsed = new URL(urlStr);
    if (parsed.protocol !== "https:") return "";
    let key = normalizeObjectKey(decodeURIComponent(parsed.pathname));
    const lowerHost = parsed.hostname.toLowerCase();
    const cleanBucket = normalizeObjectKey(bucketName ?? "");
    if (
      cleanBucket &&
      lowerHost.endsWith(".r2.cloudflarestorage.com") &&
      key.startsWith(`${cleanBucket}/`)
    ) {
      key = normalizeObjectKey(key.substring(cleanBucket.length + 1));
    }
    return key;
  } catch {
    return "";
  }
}

function inferContentTypeFromKey(key: string): string {
  const lower = key.toLowerCase();
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".mov")) return "video/quicktime";
  if (lower.endsWith(".webm")) return "video/webm";
  return "application/octet-stream";
}

const ALLOWED_COMMUNITY_MEDIA_MIME: Record<string, { exts: string[]; maxBytes: number }> = {
  "image/webp": { exts: ["webp"], maxBytes: MAX_COMMUNITY_IMAGE_BYTES },
  "image/jpeg": { exts: ["jpg", "jpeg"], maxBytes: MAX_COMMUNITY_IMAGE_BYTES },
  "image/png": { exts: ["png"], maxBytes: MAX_COMMUNITY_IMAGE_BYTES },
  "video/mp4": { exts: ["mp4"], maxBytes: MAX_COMMUNITY_VIDEO_BYTES },
  "video/quicktime": { exts: ["mov"], maxBytes: MAX_COMMUNITY_VIDEO_BYTES },
  "video/webm": { exts: ["webm"], maxBytes: MAX_COMMUNITY_VIDEO_BYTES },
};

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function normalizePublicBaseUrl(raw: string): string | null {
  let trimmed = raw.trim().replace(/\/+$/, "");
  if (!trimmed) return null;
  if (trimmed.toLowerCase().startsWith("http://")) {
    trimmed = `https://${trimmed.slice(7)}`;
  }
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:") return null;
  // Never emit S3 API endpoint URLs (which require signed headers) as publicUrl.
  if (parsed.hostname.toLowerCase().endsWith(".r2.cloudflarestorage.com")) {
    return null;
  }
  const cleanPath = parsed.pathname.replace(/\/+/g, "/").replace(/\/+$/, "");
  return `${parsed.origin}${cleanPath}`;
}

function normalizeObjectKey(raw: string): string {
  return raw.trim().replace(/^\/+/, "").replace(/\/+/g, "/");
}

function hasUnsafeKeyChars(key: string): boolean {
  if (!key || key.startsWith("/") || key.endsWith("/")) return true;
  if (key.includes("..") || key.includes("\\") || key.includes("\0")) return true;
  if (key.includes("?") || key.includes("#") || /\s/.test(key)) return true;
  return !SAFE_KEY_RE.test(key);
}

function parseContentLength(raw: unknown): number | null {
  if (typeof raw !== "number" || !Number.isFinite(raw) || !Number.isInteger(raw) || raw <= 0) {
    return null;
  }
  return raw;
}

function resolveLegacyKey(
  kind: string,
  uid: string,
  communityId: string,
  contentType: string,
): string | null {
  if (kind === "avatar" && contentType === "image/webp") {
    return `avatars/${uid}.webp`;
  }
  if (
    kind === "community-avatar" &&
    contentType === "image/webp" &&
    UUID_RE.test(communityId)
  ) {
    return `community-avatars/${communityId}.webp`;
  }
  if (
    kind === "group-avatar" &&
    contentType === "image/webp" &&
    UUID_RE.test(communityId)
  ) {
    return `group-avatars/${communityId}.webp`;
  }
  if (kind === "community-media" && UUID_RE.test(communityId)) {
    const rule = ALLOWED_COMMUNITY_MEDIA_MIME[contentType];
    if (!rule) return null;
    return `community-media/${communityId}/${uid}/${Date.now()}_${crypto.randomUUID()}.${rule.exts[0]}`;
  }
  return null;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const r2AccountId = Deno.env.get("R2_ACCOUNT_ID");
  const r2AccessKeyId = Deno.env.get("R2_ACCESS_KEY_ID");
  const r2SecretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const r2BucketName =
    Deno.env.get("R2_BUCKET_NAME") ?? Deno.env.get("R2_BUCKET");
  const rawR2PublicUrl =
    Deno.env.get("R2_PUBLIC_URL") ??
    Deno.env.get("R2_PUBLIC_BASE_URL") ??
    "";

  if (
    !supabaseUrl ||
    !serviceRoleKey ||
    !r2AccountId ||
    !r2AccessKeyId ||
    !r2SecretAccessKey ||
    !r2BucketName
  ) {
    return json({ error: "r2_not_configured" }, 500);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  const user = authData?.user;
  if (authError || !user?.id || !UUID_RE.test(user.id)) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const action = String(body.action ?? "put").trim().toLowerCase() || "put";
  if (action !== "put" && action !== "get-url" && action !== "proxy") {
    return json({ error: "unsupported_action" }, 400);
  }

  const s3 = new S3Client({
    region: "auto",
    endpoint: `https://${r2AccountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: r2AccessKeyId,
      secretAccessKey: r2SecretAccessKey,
    },
  });

  if (action === "get-url" || action === "proxy") {
    const readKey = extractKeyFromUrlOrKey(body.objectKey, body.url, r2BucketName);
    if (hasUnsafeKeyChars(readKey)) {
      return json({ error: "invalid_object_key" }, 400);
    }

    const isUserAvatar = AVATAR_READ_KEY_RE.test(readKey);
    const isCommAvatar = COMMUNITY_AVATAR_READ_KEY_RE.test(readKey);
    const isGroupAvatar = GROUP_AVATAR_READ_KEY_RE.test(readKey);
    const commMediaMatch = COMMUNITY_MEDIA_KEY_RE.exec(readKey);

    if (isUserAvatar || isCommAvatar || isGroupAvatar) {
      // Authenticated users may fetch profile, group, and community avatars.
    } else if (commMediaMatch) {
      const communityId = commMediaMatch[1];
      const { data: communityExists } = await admin
        .from("communities")
        .select("id")
        .eq("id", communityId)
        .maybeSingle();

      if (!communityExists) {
        return json({ error: "forbidden_object_key" }, 403);
      }
    } else {
      return json({ error: "forbidden_object_key" }, 403);
    }

    if (action === "get-url") {
      const getCmd = new GetObjectCommand({
        Bucket: r2BucketName,
        Key: readKey,
      });
      const downloadUrl = await getSignedUrl(s3, getCmd, {
        expiresIn: GET_PRESIGN_EXPIRES_SECONDS,
      });
      return json({
        downloadUrl,
        objectKey: readKey,
        expiresIn: GET_PRESIGN_EXPIRES_SECONDS,
      });
    }

    let obj;
    try {
      obj = await s3.send(
        new GetObjectCommand({
          Bucket: r2BucketName,
          Key: readKey,
        }),
      );
    } catch (err: unknown) {
      const e = err as { name?: string; $metadata?: { httpStatusCode?: number } };
      if (e?.name === "NoSuchKey" || e?.$metadata?.httpStatusCode === 404) {
        return json({ error: "not_found" }, 404);
      }
      return json({ error: "r2_read_failed" }, 502);
    }

    if (
      typeof obj.ContentLength === "number" &&
      obj.ContentLength > MAX_PROXY_BYTES
    ) {
      return json({ error: "file_too_large" }, 413);
    }

    if (!obj.Body) {
      return json({ error: "not_found" }, 404);
    }

    const rawStream =
      typeof (obj.Body as { transformToWebStream?: () => ReadableStream<Uint8Array> })
        .transformToWebStream === "function"
        ? (obj.Body as { transformToWebStream: () => ReadableStream<Uint8Array> })
            .transformToWebStream()
        : (obj.Body as ReadableStream<Uint8Array>);

    let totalBytes = 0;
    const boundedStream = rawStream.pipeThrough(
      new TransformStream<Uint8Array, Uint8Array>({
        transform(chunk, controller) {
          totalBytes += chunk.byteLength;
          if (totalBytes > MAX_PROXY_BYTES) {
            controller.error(new Error("file_too_large"));
            return;
          }
          controller.enqueue(chunk);
        },
      }),
    );

    const headers: Record<string, string> = {
      ...CORS_HEADERS,
      "Content-Type": obj.ContentType || inferContentTypeFromKey(readKey),
      "Cache-Control": "private, max-age=3600",
      "X-Content-Type-Options": "nosniff",
    };
    if (typeof obj.ContentLength === "number" && obj.ContentLength > 0) {
      headers["Content-Length"] = String(obj.ContentLength);
    }

    return new Response(boundedStream, { status: 200, headers });
  }

  if (!rawR2PublicUrl.trim()) {
    return json({ error: "r2_not_configured" }, 500);
  }
  const r2PublicUrl = normalizePublicBaseUrl(rawR2PublicUrl);
  if (!r2PublicUrl) {
    return json({ error: "r2_public_url_invalid" }, 500);
  }

  const contentType = String(body.contentType ?? "").trim().toLowerCase();
  if (!contentType) {
    return json({ error: "missing_content_type" }, 400);
  }

  const contentLength = parseContentLength(body.contentLength ?? body.size);
  if (contentLength === null) {
    return json({ error: "invalid_content_length" }, 400);
  }

  let objectKey = normalizeObjectKey(String(body.objectKey ?? ""));
  if (!objectKey && body.kind) {
    objectKey = normalizeObjectKey(
      resolveLegacyKey(
        String(body.kind ?? ""),
        user.id,
        String(body.communityId ?? ""),
        contentType,
      ) ?? "",
    );
  }

  if (hasUnsafeKeyChars(objectKey)) {
    return json({ error: "invalid_object_key" }, 400);
  }

  const expectedAvatarKey = `avatars/${user.id}.webp`;
  const commAvatarMatch = COMMUNITY_AVATAR_KEY_RE.exec(objectKey);
  const groupAvatarMatch = GROUP_AVATAR_KEY_RE.exec(objectKey);
  const commMediaMatch = COMMUNITY_MEDIA_KEY_RE.exec(objectKey);

  let finalKey = objectKey;

  if (objectKey === expectedAvatarKey) {
    if (contentType !== "image/webp") {
      return json({ error: "avatar_must_be_webp" }, 400);
    }
    if (contentLength > MAX_AVATAR_BYTES) {
      return json({ error: "file_too_large" }, 413);
    }
  } else if (groupAvatarMatch) {
    if (contentType !== "image/webp") {
      return json({ error: "group_avatar_must_be_webp" }, 400);
    }
    if (contentLength > MAX_AVATAR_BYTES) {
      return json({ error: "file_too_large" }, 413);
    }
    const groupId = groupAvatarMatch[1];
    const { data: grp } = await admin
      .from("groups")
      .select("owner_id")
      .eq("id", groupId)
      .maybeSingle();
    let allowed = grp?.owner_id === user.id;
    if (!allowed) {
      const { data: gm } = await admin
        .from("group_members")
        .select("role")
        .eq("group_id", groupId)
        .eq("user_id", user.id)
        .maybeSingle();
      allowed = gm?.role === "owner";
    }
    if (!allowed) {
      return json({ error: "forbidden_group_avatar" }, 403);
    }
  } else if (commAvatarMatch) {
    if (contentType !== "image/webp") {
      return json({ error: "community_avatar_must_be_webp" }, 400);
    }
    if (contentLength > MAX_AVATAR_BYTES) {
      return json({ error: "file_too_large" }, 413);
    }
    const communityId = commAvatarMatch[1];
    const { data: community } = await admin
      .from("communities")
      .select("owner_id")
      .eq("id", communityId)
      .maybeSingle();
    if (!community || community.owner_id !== user.id) {
      return json({ error: "forbidden_community_avatar" }, 403);
    }
  } else if (commMediaMatch) {
    const communityId = commMediaMatch[1];
    const suppliedUserId = commMediaMatch[2];
    const filePart = commMediaMatch[3];
    const keyExt = commMediaMatch[4].toLowerCase();

    // Prevent writing under another user's prefix inside community-media.
    if (suppliedUserId && suppliedUserId.toLowerCase() !== user.id.toLowerCase()) {
      return json({ error: "forbidden_object_key" }, 403);
    }

    const mediaRule = ALLOWED_COMMUNITY_MEDIA_MIME[contentType];
    if (!mediaRule || !mediaRule.exts.includes(keyExt)) {
      return json({ error: "unsupported_media_content_type" }, 400);
    }
    if (contentLength > mediaRule.maxBytes) {
      return json({ error: "file_too_large" }, 413);
    }

    const { data: membership } = await admin
      .from("community_members")
      .select("user_id")
      .eq("community_id", communityId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!membership) {
      return json({ error: "forbidden_community_media" }, 403);
    }

    // Isolate all community media objects under the authenticated user's prefix.
    finalKey = normalizeObjectKey(`community-media/${communityId}/${user.id}/${filePart}`);
  } else {
    return json({ error: "forbidden_object_key" }, 403);
  }

  const command = new PutObjectCommand({
    Bucket: r2BucketName,
    Key: finalKey,
    ContentType: contentType,
    ContentLength: contentLength,
  });

  const uploadUrl = await getSignedUrl(s3, command, {
    expiresIn: PRESIGN_EXPIRES_SECONDS,
  });

  const publicUrl = `${r2PublicUrl}/${finalKey}`;

  return json({
    uploadUrl,
    publicUrl,
    objectKey: finalKey,
    headers: {
      "Content-Type": contentType,
    },
  });
});
