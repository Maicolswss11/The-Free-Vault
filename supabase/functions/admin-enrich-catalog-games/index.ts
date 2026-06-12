import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function steamAppId(storeListings: unknown): string | null {
  if (!Array.isArray(storeListings)) return null;
  for (const listing of storeListings) {
    if (!listing || typeof listing !== "object") continue;
    const entry = listing as Record<string, unknown>;
    if (text(entry.store)?.toLowerCase() !== "steam") continue;
    const externalId = text(entry.external_id);
    if (externalId && /^\d+$/.test(externalId)) return externalId;
    const listingId = text(entry.listing_id);
    const match = listingId?.match(/^steam:(\d+)$/);
    if (match) return match[1];
  }
  return null;
}

function parseReleaseDate(value: unknown): { date: string | null; year: number | null } {
  const raw = text(value);
  if (!raw) return { date: null, year: null };
  const yearMatch = raw.match(/\b(19|20)\d{2}\b/);
  const year = yearMatch ? Number(yearMatch[0]) : null;
  const timestamp = Date.parse(raw);
  if (Number.isNaN(timestamp)) return { date: null, year };
  const date = new Date(timestamp).toISOString().slice(0, 10);
  return { date, year: year || Number(date.slice(0, 4)) };
}

async function fetchSteamDetails(appId: string) {
  const endpoint = new URL("https://store.steampowered.com/api/appdetails");
  endpoint.searchParams.set("appids", appId);
  endpoint.searchParams.set("cc", "it");
  endpoint.searchParams.set("l", "english");
  const response = await fetch(endpoint, {
    headers: { "Accept": "application/json", "User-Agent": "The-Free-Vault/4.7.2" },
  });
  if (!response.ok) throw new Error(`Steam HTTP ${response.status}`);
  const payload = await response.json();
  const record = payload?.[appId];
  if (!record?.success || !record?.data) throw new Error("Scheda Steam non disponibile");
  return record.data as Record<string, any>;
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

  const { data: adminUser, error: adminError } = await admin
    .from("admin_users")
    .select("user_id, role")
    .eq("user_id", userData.user.id)
    .maybeSingle();
  if (adminError || !adminUser) return json({ error: "Permessi amministratore richiesti" }, 403);

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    return json({ error: "Payload JSON non valido" }, 400);
  }

  const requestedKeys = Array.isArray(body.game_keys) ? body.game_keys : [];
  const gameKeys = [...new Set(requestedKeys
    .map((value) => text(value))
    .filter((value): value is string => Boolean(value)))]
    .slice(0, 100);
  if (!gameKeys.length) return json({ error: "Nessun gioco indicato" }, 400);

  const { data: games, error: gamesError } = await admin
    .from("catalog_games")
    .select("match_key, title, description, developer, publisher, image_url, release_date, release_year, genres, store_listings")
    .in("match_key", gameKeys);
  if (gamesError) return json({ error: gamesError.message }, 500);

  let updated = 0;
  let alreadyComplete = 0;
  let withoutSteam = 0;
  const errors: Array<{ game_key: string; error: string }> = [];

  for (const game of games || []) {
    if (game.release_year) {
      alreadyComplete += 1;
      continue;
    }
    const appId = steamAppId(game.store_listings);
    if (!appId) {
      withoutSteam += 1;
      continue;
    }

    try {
      const details = await fetchSteamDetails(appId);
      const release = parseReleaseDate(details?.release_date?.date);
      const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
      if (!game.release_date && release.date) patch.release_date = release.date;
      if (!game.release_year && release.year) patch.release_year = release.year;
      if (!text(game.description) && text(details.short_description)) patch.description = text(details.short_description);
      if (!text(game.developer) && Array.isArray(details.developers)) patch.developer = text(details.developers[0]);
      if (!text(game.publisher) && Array.isArray(details.publishers)) patch.publisher = text(details.publishers[0]);
      if (!text(game.image_url) && text(details.header_image)) patch.image_url = text(details.header_image);
      if ((!Array.isArray(game.genres) || !game.genres.length) && Array.isArray(details.genres)) {
        patch.genres = details.genres.map((genre: any) => text(genre?.description)).filter(Boolean);
      }

      if (Object.keys(patch).length === 1) {
        errors.push({ game_key: game.match_key, error: "Steam non ha restituito una data di uscita" });
        continue;
      }

      const { error: updateError } = await admin
        .from("catalog_games")
        .update(patch)
        .eq("match_key", game.match_key);
      if (updateError) throw updateError;
      updated += 1;
    } catch (error) {
      errors.push({
        game_key: game.match_key,
        error: error instanceof Error ? error.message : "Errore sconosciuto",
      });
    }
  }

  return json({
    requested: gameKeys.length,
    found: games?.length || 0,
    updated,
    already_complete: alreadyComplete,
    without_steam: withoutSteam,
    failed: errors.length,
    errors: errors.slice(0, 20),
  });
});
