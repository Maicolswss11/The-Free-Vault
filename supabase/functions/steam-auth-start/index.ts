import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};


function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authorization = request.headers.get("Authorization") || "";

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const admin = createClient(supabaseUrl, serviceRole);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  const payload = await request.json().catch(() => ({}));
  const defaultBase = "https://maicolswss11.github.io/The-Free-Vault/";
  const allowedBase = (Deno.env.get("APP_BASE_URL") || defaultBase).replace(/\/$/, "/");
  const returnUrl = String(payload.returnUrl || `${allowedBase}#/settings/connections?steam=linked`);
  if (!returnUrl.startsWith(allowedBase)) {
    return json({ error: "Return URL non consentito" }, 400);
  }

  const state = crypto.randomUUID();
  const { error: insertError } = await admin.from("steam_link_states").insert({
    state,
    user_id: userData.user.id,
    return_url: returnUrl,
  });
  if (insertError) return json({ error: insertError.message }, 500);

  const callback = `${supabaseUrl}/functions/v1/steam-auth-callback?state=${encodeURIComponent(state)}`;
  const realm = new URL(callback).origin;
  const openIdUrl = new URL("https://steamcommunity.com/openid/login");
  openIdUrl.search = new URLSearchParams({
    "openid.ns": "http://specs.openid.net/auth/2.0",
    "openid.mode": "checkid_setup",
    "openid.return_to": callback,
    "openid.realm": realm,
    "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
    "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
  }).toString();

  return json({ url: openIdUrl.toString() });
});
