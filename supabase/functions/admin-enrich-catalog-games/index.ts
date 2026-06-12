import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const STEAM_CONCURRENCY = 3;
const STEAM_GROUP_DELAY_MS = 300;
const MAX_ATTEMPTS = 3;

type CatalogGame = {
  match_key: string;
  title: string | null;
  canonical_title: string | null;
  description: string | null;
  developer: string | null;
  publisher: string | null;
  image_url: string | null;
  release_date: string | null;
  release_year: number | null;
  genres: unknown;
  store_listings: unknown;
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

function sleep(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function appIdFromListing(entry: Record<string, unknown>): string | null {
  const store = text(entry.store)?.toLowerCase();
  const externalId = text(entry.external_id);
  const listingId = text(entry.listing_id);
  const storeUrl = text(entry.store_url);
  const looksLikeSteam = store === "steam"
    || /^steam[:/_-]/i.test(listingId || "")
    || /store\.steampowered\.com\/app\//i.test(storeUrl || "");
  if (!looksLikeSteam) return null;
  if (externalId && /^\d+$/.test(externalId)) return externalId;
  const listingMatch = listingId?.match(/^steam[:/_-](\d+)$/i);
  if (listingMatch) return listingMatch[1];
  const urlMatch = storeUrl?.match(/store\.steampowered\.com\/app\/(\d+)/i);
  return urlMatch?.[1] || null;
}

function steamAppId(storeListings: unknown): string | null {
  if (!Array.isArray(storeListings)) return null;
  for (const listing of storeListings) {
    if (!listing || typeof listing !== "object") continue;
    const appId = appIdFromListing(listing as Record<string, unknown>);
    if (appId) return appId;
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

function releaseYearFromTitle(...values: unknown[]): number | null {
  const upperBound = new Date().getUTCFullYear() + 5;
  for (const value of values) {
    const raw = text(value);
    if (!raw) continue;
    const parenthesized = raw.match(/[\[(]\s*((?:19|20)\d{2})\s*[\])]/);
    const generic = raw.match(/\b((?:19|20)\d{2})\b/);
    const year = Number(parenthesized?.[1] || generic?.[1] || 0);
    if (year >= 1950 && year <= upperBound) return year;
  }
  return null;
}

async function fetchSteamDetails(appId: string) {
  const endpoint = new URL("https://store.steampowered.com/api/appdetails");
  endpoint.searchParams.set("appids", appId);
  endpoint.searchParams.set("cc", "it");
  endpoint.searchParams.set("l", "english");

  let lastError: Error | null = null;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetch(endpoint, {
        headers: { "Accept": "application/json", "User-Agent": "The-Free-Vault/4.7.3" },
      });
      if (response.status === 429 || response.status >= 500) {
        throw new Error(`Steam HTTP ${response.status}`);
      }
      if (!response.ok) throw new Error(`Steam HTTP ${response.status}`);
      const payload = await response.json();
      const record = payload?.[appId];
      if (!record?.success || !record?.data) return null;
      return record.data as Record<string, any>;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error("Errore Steam sconosciuto");
      if (attempt < MAX_ATTEMPTS) await sleep(700 * (2 ** (attempt - 1)));
    }
  }
  throw lastError || new Error("Steam non disponibile");
}

async function fetchSteamDetailsMany(appIds: string[]) {
  const details = new Map<string, Record<string, any>>();
  const errors: Array<{ appid: string; error: string }> = [];
  const groups = chunks(appIds, STEAM_CONCURRENCY);

  for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
    const group = groups[groupIndex];
    const results = await Promise.allSettled(group.map(async (appId) => ({
      appId,
      value: await fetchSteamDetails(appId),
    })));

    for (const result of results) {
      if (result.status === "rejected") {
        errors.push({ appid: "unknown", error: result.reason instanceof Error ? result.reason.message : "Errore Steam sconosciuto" });
        continue;
      }
      if (result.value.value) details.set(result.value.appId, result.value.value);
      else errors.push({ appid: result.value.appId, error: "Scheda Steam non disponibile" });
    }

    if (groupIndex < groups.length - 1) await sleep(STEAM_GROUP_DELAY_MS);
  }

  return { details, errors };
}

function metadataPatch(game: CatalogGame, details: Record<string, any> | null) {
  const patch: Record<string, unknown> = {};
  let source: "steam" | "title" | null = null;

  const release = parseReleaseDate(details?.release_date?.date);
  const inferredYear = releaseYearFromTitle(game.title, game.canonical_title);

  // Per le riedizioni dei classici Steam espone spesso la data di pubblicazione
  // sullo store, mentre il titolo conserva l'anno originale del gioco.
  if (!game.release_year && inferredYear) {
    patch.release_year = inferredYear;
    source = "title";
    if (!game.release_date && release.date && release.year === inferredYear) {
      patch.release_date = release.date;
    }
  } else if (!game.release_year && release.year) {
    patch.release_year = release.year;
    source = "steam";
    if (!game.release_date && release.date) patch.release_date = release.date;
  } else if (!game.release_date && release.date && release.year === game.release_year) {
    patch.release_date = release.date;
  }

  if (details) {
    if (!text(game.description) && text(details.short_description)) patch.description = text(details.short_description);
    if (!text(game.developer) && Array.isArray(details.developers)) patch.developer = text(details.developers[0]);
    if (!text(game.publisher) && Array.isArray(details.publishers)) patch.publisher = text(details.publishers[0]);
    if (!text(game.image_url) && text(details.header_image)) patch.image_url = text(details.header_image);
    if ((!Array.isArray(game.genres) || !game.genres.length) && Array.isArray(details.genres)) {
      patch.genres = details.genres.map((genre: any) => text(genre?.description)).filter(Boolean);
    }
  }

  return { patch, source };
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

  const { data: rawGames, error: gamesError } = await admin
    .from("catalog_games")
    .select("match_key, title, canonical_title, description, developer, publisher, image_url, release_date, release_year, genres, store_listings")
    .in("match_key", gameKeys);
  if (gamesError) return json({ error: gamesError.message }, 500);
  const games = (rawGames || []) as CatalogGame[];

  const appIds = [...new Set(games.map((game) => steamAppId(game.store_listings)).filter((value): value is string => Boolean(value)))];
  const steamResult = await fetchSteamDetailsMany(appIds);
  const steamDetails = steamResult.details;

  let updated = 0;
  let updatedFromSteam = 0;
  let inferredFromTitle = 0;
  let alreadyComplete = 0;
  let withoutSteam = 0;
  let unresolvedYear = 0;
  const errors: Array<{ game_key: string; error: string }> = [];

  for (const game of games) {
    const appId = steamAppId(game.store_listings);
    const details = appId ? (steamDetails.get(appId) || null) : null;
    const { patch, source } = metadataPatch(game, details);

    if (!appId) withoutSteam += 1;
    if (!Object.keys(patch).length) {
      if (game.release_year) alreadyComplete += 1;
      else if (appId && !details) errors.push({ game_key: game.match_key, error: "Scheda Steam non disponibile" });
      else errors.push({ game_key: game.match_key, error: "Nessun anno ricavabile dalla fonte o dal titolo" });
      continue;
    }

    patch.updated_at = new Date().toISOString();
    const { error: updateError } = await admin
      .from("catalog_games")
      .update(patch)
      .eq("match_key", game.match_key);
    if (updateError) {
      errors.push({ game_key: game.match_key, error: updateError.message });
      continue;
    }
    updated += 1;
    if (!game.release_year && !patch.release_year) unresolvedYear += 1;
    if (source === "steam") updatedFromSteam += 1;
    if (source === "title") inferredFromTitle += 1;
  }

  return json({
    requested: gameKeys.length,
    found: games.length,
    steam_appids: appIds.length,
    steam_details_found: steamDetails.size,
    updated,
    updated_from_steam: updatedFromSteam,
    inferred_from_title: inferredFromTitle,
    already_complete: alreadyComplete,
    without_steam: withoutSteam,
    unresolved_year: unresolvedYear + errors.filter((item) => item.error.includes("anno")).length,
    failed: errors.length,
    steam_errors: steamResult.errors.slice(0, 20),
    errors: errors.slice(0, 20),
  });
});
