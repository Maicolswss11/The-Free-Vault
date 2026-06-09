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
  const steamKey = Deno.env.get("STEAM_WEB_API_KEY");
  if (!steamKey) return json({ error: "STEAM_WEB_API_KEY non configurata" }, 500);

  const authorization = request.headers.get("Authorization") || "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const admin = createClient(supabaseUrl, serviceRole);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  const { data: account, error: accountError } = await admin
    .from("steam_accounts")
    .select("steam_id")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (accountError || !account?.steam_id) return json({ error: "Steam non collegato" }, 400);

  const endpoint = new URL("https://partner.steam-api.com/IPlayerService/GetOwnedGames/v1/");
  endpoint.searchParams.set("key", steamKey);
  endpoint.searchParams.set("input_json", JSON.stringify({
    steamid: account.steam_id,
    include_appinfo: true,
    include_played_free_games: true,
  }));

  const steamResponse = await fetch(endpoint);
  if (!steamResponse.ok) {
    return json({ error: `Steam HTTP ${steamResponse.status}. Verifica la privacy del profilo.` }, 502);
  }
  const payload = await steamResponse.json();
  const games = Array.isArray(payload?.response?.games) ? payload.response.games : [];
  const now = new Date().toISOString();

  if (games.length) {
    const rows = games.map((game: any) => ({
      user_id: userData.user.id,
      store: "steam",
      external_id: String(game.appid),
      listing_id: `steam:${game.appid}`,
      playtime_minutes: Number(game.playtime_forever || 0),
      metadata: {
        name: game.name || null,
        img_icon_url: game.img_icon_url || null,
        img_logo_url: game.img_logo_url || null,
        playtime_2weeks: Number(game.playtime_2weeks || 0),
        rtime_last_played: Number(game.rtime_last_played || 0),
      },
      updated_at: now,
    }));
    const { error: upsertError } = await admin
      .from("user_owned_listings")
      .upsert(rows, { onConflict: "user_id,store,external_id" });
    if (upsertError) return json({ error: upsertError.message }, 500);
  }

  await admin.from("steam_accounts")
    .update({ last_sync_at: now, updated_at: now })
    .eq("user_id", userData.user.id);

  return json({
    game_count: Number(payload?.response?.game_count || games.length),
    games,
    synced_at: now,
  });
});
