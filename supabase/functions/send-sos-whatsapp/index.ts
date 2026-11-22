// Supabase Edge Function: send-sos-whatsapp
// Sends automatic WhatsApp emergency alerts via WhatsApp Business Cloud API
// when `WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_PHONE_NUMBER_ID` are configured in
// Supabase Edge Function secrets. Returns `{ configured: false, sent: 0 }`
// immediately when unconfigured so SOS dispatch is never blocked.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const E164_RE = /^\+[0-9]{8,15}$/;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function toWaNumber(phoneE164: string): string {
  return phoneE164.replace(/^\+/, "").trim();
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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? serviceRoleKey;
  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return json({ error: "supabase_not_configured" }, 500);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ error: "unauthorized" }, 401);
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: userErr } = await authClient.auth.getUser(
    token,
  );
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN")?.trim() ?? "";
  const phoneNumberId =
    Deno.env.get("WHATSAPP_PHONE_NUMBER_ID")?.trim() ?? "";
  const templateName = Deno.env.get("WHATSAPP_SOS_TEMPLATE_NAME")?.trim() ?? "";

  if (!accessToken || !phoneNumberId) {
    return json({
      configured: false,
      sent: 0,
      skipped: "whatsapp_not_configured",
    });
  }

  let body: { sos_id?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const message = String(body.message ?? "").trim();
  if (!message) {
    return json({ error: "missing_message" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: contactRows } = await admin
    .from("emergency_contacts")
    .select("phone_e164")
    .eq("user_id", userData.user.id)
    .eq("contact_kind", "phone")
    .eq("consent_status", "granted");

  const phones = Array.from(
    new Set(
      (contactRows ?? [])
        .map((r: { phone_e164?: string | null }) =>
          String(r.phone_e164 ?? "").trim()
        )
        .filter((p: string) => E164_RE.test(p)),
    ),
  );

  if (phones.length === 0) {
    return json({
      configured: true,
      sent: 0,
      total: 0,
      reason: "no_granted_phone_contacts",
    });
  }

  const endpoint =
    `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`;

  const results = await Promise.allSettled(
    phones.map(async (phone) => {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      try {
        const waPayload = templateName
          ? {
              messaging_product: "whatsapp",
              to: toWaNumber(phone),
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
              to: toWaNumber(phone),
              type: "text",
              text: { preview_url: true, body: message },
            };

        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(waPayload),
          signal: controller.signal,
        });
        return res.ok;
      } finally {
        clearTimeout(timeout);
      }
    }),
  );

  const sent = results.filter(
    (r) => r.status === "fulfilled" && r.value === true,
  ).length;

  return json({
    configured: true,
    sent,
    total: phones.length,
  });
});
