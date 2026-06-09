import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};


function redirect(url: string, params: Record<string, string>) {
  const target = new URL(url);
  for (const [key, value] of Object.entries(params)) target.searchParams.set(key, value);
  return Response.redirect(target.toString(), 302);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const requestUrl = new URL(request.url);
  const state = requestUrl.searchParams.get("state");
  if (!state) return new Response("Missing state", { status: 400 });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const steamKey = Deno.env.get("STEAM_WEB_API_KEY")!;
  const admin = createClient(supabaseUrl, serviceRole);

  const { data: linkState, error: stateError } = await admin
    .from("steam_link_states")
    .select("state, user_id, return_url, expires_at, consumed_at")
    .eq("state", state)
    .maybeSingle();

  if (stateError || !linkState) return new Response("Invalid state", { status: 400 });
  if (linkState.consumed_at || new Date(linkState.expires_at) <= new Date()) {
    return redirect(linkState.return_url, { steam: "expired" });
  }

  const verification = new URLSearchParams();
  requestUrl.searchParams.forEach((value, key) => {
    if (key.startsWith("openid.")) verification.set(key, value);
  });
  verification.set("openid.mode", "check_authentication");

  const verifyResponse = await fetch("https://steamcommunity.com/openid/login", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: verification,
  });
  const verifyText = await verifyResponse.text();
  if (!verifyResponse.ok || !verifyText.includes("is_valid:true")) {
    return redirect(linkState.return_url, { steam: "invalid" });
  }

  const claimedId = requestUrl.searchParams.get("openid.claimed_id") || "";
  const match = claimedId.match(/steamcommunity\.com\/openid\/id\/(\d{17})$/);
  if (!match) return redirect(linkState.return_url, { steam: "invalid-id" });
  const steamId = match[1];

  let personaName: string | null = null;
  let profileUrl: string | null = null;
  let avatarUrl: string | null = null;
  if (steamKey) {
    const profileEndpoint = new URL("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/");
    profileEndpoint.searchParams.set("key", steamKey);
    profileEndpoint.searchParams.set("steamids", steamId);
    const profileResponse = await fetch(profileEndpoint);
    if (profileResponse.ok) {
      const profilePayload = await profileResponse.json();
      const player = profilePayload?.response?.players?.[0];
      personaName = player?.personaname || null;
      profileUrl = player?.profileurl || null;
      avatarUrl = player?.avatarfull || player?.avatarmedium || null;
    }
  }

  const now = new Date().toISOString();
  const { error: upsertError } = await admin.from("steam_accounts").upsert({
    user_id: linkState.user_id,
    steam_id: steamId,
    persona_name: personaName,
    profile_url: profileUrl,
    avatar_url: avatarUrl,
    updated_at: now,
  }, { onConflict: "user_id" });

  if (upsertError) return redirect(linkState.return_url, { steam: "database-error" });

  await admin.from("steam_link_states").update({ consumed_at: now }).eq("state", state);
  return redirect(linkState.return_url, { steam: "linked" });
});
