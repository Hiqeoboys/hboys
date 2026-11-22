// Supabase Edge Function: notify-moderation-report
// Triggered by Supabase Database Webhook on INSERT into public.moderation_reports.
//
// Required secret: WEBHOOK_SECRET (verified via x-webhook-secret / x-hiqeo-webhook-secret).
// Optional secrets: DISCORD_WEBHOOK_URL, TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID, RESEND_API_KEY + ADMIN_EMAIL.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

interface ModerationReport {
  id: string;
  report_type: "group_message" | "community_message" | "community" | "user_account";
  target_id: string;
  reporter_id: string;
  reason: string;
  content_snippet?: string | null;
  created_at: string;
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

function sanitizeExcerpt(value: string, maxLen = 300): string {
  const cleaned = value
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/```+/g, "'''")
    .trim();
  return cleaned.length > maxLen ? `${cleaned.slice(0, maxLen - 3)}...` : cleaned;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  if (!verifyWebhookAuth(req)) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: { record?: ModerationReport };
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const report = body.record;
  if (!report) {
    return new Response("Missing record", { status: 400 });
  }

  const typeLabel: Record<string, string> = {
    group_message: "Pesan Grup",
    community_message: "Pesan Komunitas",
    community: "Komunitas",
    user_account: "Akun Pengguna",
  };

  // Never forward plaintext group message excerpts in admin webhook alerts.
  const safeSnippet =
    report.report_type === "group_message"
      ? "[Terenkripsi E2EE]"
      : report.content_snippet
      ? sanitizeExcerpt(report.content_snippet)
      : "";

  const summary = [
    `[Hiqeo Moderasi] Laporan Baru (${typeLabel[report.report_type] ?? report.report_type})`,
    `ID Laporan : ${sanitizeExcerpt(String(report.id ?? ""), 64)}`,
    `Target ID  : ${sanitizeExcerpt(String(report.target_id ?? ""), 64)}`,
    `Pelapor ID : ${sanitizeExcerpt(String(report.reporter_id ?? ""), 64)}`,
    `Alasan     : ${sanitizeExcerpt(String(report.reason ?? ""))}`,
    ...(safeSnippet ? [`Cuplikan   : ${safeSnippet}`] : []),
    `Waktu      : ${sanitizeExcerpt(String(report.created_at ?? ""), 64)}`,
  ].join("\n");

  const dispatches: Promise<Response>[] = [];

  const discordUrl = Deno.env.get("DISCORD_WEBHOOK_URL");
  if (discordUrl) {
    dispatches.push(
      fetch(discordUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: "```\n" + summary + "\n```" }),
      }),
    );
  }

  const tgToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
  const tgChatId = Deno.env.get("TELEGRAM_CHAT_ID");
  if (tgToken && tgChatId) {
    dispatches.push(
      fetch(`https://api.telegram.org/bot${tgToken}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: tgChatId, text: summary }),
      }),
    );
  }

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const adminEmail = Deno.env.get("ADMIN_EMAIL");
  if (resendKey && adminEmail) {
    dispatches.push(
      fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${resendKey}`,
        },
        body: JSON.stringify({
          from: "Hiqeo Moderation <moderation@hiqeo.app>",
          to: [adminEmail],
          subject: `[Hiqeo Moderasi] Laporan ${typeLabel[report.report_type] ?? report.report_type}`,
          text: summary,
        }),
      }),
    );
  }

  await Promise.allSettled(dispatches);

  return new Response(
    JSON.stringify({ ok: true, report_id: report.id, notified_channels: dispatches.length }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
