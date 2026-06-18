(() => {
  const PAGE_CACHE_TTL = 5 * 60 * 1000;
  const pageCache = new Map();
  const gameCache = new Map();
  const gameRequestCache = new Map();
  let statsCache = null;
  let discoveryCache = null;
  let recommendationsCache = null;
  const entityCache = new Map();
  const relatedCache = new Map();

  function client() {
    return window.VaultAuth?.client || null;
  }

  function configured() {
    return Boolean(client());
  }

  function cacheKey(options) {
    return JSON.stringify(options, Object.keys(options).sort());
  }

  function normalizeItem(item) {
    const listings = Array.isArray(item?.store_listings) ? item.store_listings : [];
    const primary = listings[0] || {};
    return {
      ...item,
      internal_id: item?.canonical_id || item?.internal_id,
      listing_id: item?.listing_id || primary.listing_id,
      source_kind: item?.source_kind || "catalog",
      master_game_id: item?.master_game_id || null,
      canonical_route_key: item?.canonical_route_key || item?.match_key || null,
      requested_key: item?.requested_key || null,
      store: item?.store || primary.store || null,
      stores: Array.isArray(item?.stores) ? item.stores : listings.map((entry) => entry.store),
      store_listings: listings,
      store_url: item?.store_url || primary.store_url || null,
      image_url: item?.image_url || primary.image_url || null,
      original_price: item?.original_price ?? primary.original_price ?? null,
      discount_price: item?.discount_price ?? primary.discount_price ?? null,
      currency_code: item?.currency_code || primary.currency_code || null,
      fmt_original_price: item?.fmt_original_price || primary.fmt_original_price || null,
      fmt_discount_price: item?.fmt_discount_price || primary.fmt_discount_price || null,
    };
  }



  function normalizeDuplicateText(value) {
    return String(value || "")
      .toLocaleLowerCase("it")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[™®©]/g, "")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  function catalogDuplicateMaker(item) {
    return normalizeDuplicateText(item?.developer || item?.publisher || "");
  }

  function catalogDuplicateScore(item) {
    const stores = Array.isArray(item?.stores) ? item.stores.filter(Boolean).length : 0;
    const listings = Array.isArray(item?.store_listings) ? item.store_listings.filter(Boolean).length : 0;
    return (item?.source_kind === "hybrid" ? 50 : item?.source_kind === "catalog" ? 30 : 10)
      + Math.min(40, Math.max(stores, listings) * 10)
      + (item?.description ? 6 : 0)
      + (item?.image_url ? 4 : 0)
      + (item?.release_date ? 2 : 0);
  }

  function looksLikeTechnicalDuplicate(a, b) {
    const titleA = normalizeDuplicateText(a?.canonical_title || a?.title);
    const titleB = normalizeDuplicateText(b?.canonical_title || b?.title);
    if (!titleA || titleA !== titleB) return false;
    if (a?.master_game_id && b?.master_game_id && a.master_game_id === b.master_game_id) return true;
    const makerA = catalogDuplicateMaker(a);
    const makerB = catalogDuplicateMaker(b);
    const sameMaker = makerA && makerB && makerA === makerB;
    const yearA = Number(a?.release_year || (a?.release_date || "").slice(0, 4));
    const yearB = Number(b?.release_year || (b?.release_date || "").slice(0, 4));
    const yearsClose = !yearA || !yearB || Math.abs(yearA - yearB) <= 2;
    const hasStoreRecord = [a, b].some((item) => Array.isArray(item?.stores) && item.stores.length);
    return sameMaker && yearsClose && hasStoreRecord;
  }

  function dedupeCatalogItems(items) {
    const output = [];
    for (const item of items || []) {
      const existingIndex = output.findIndex((candidate) => looksLikeTechnicalDuplicate(candidate, item));
      if (existingIndex === -1) {
        output.push(item);
        continue;
      }
      if (catalogDuplicateScore(item) > catalogDuplicateScore(output[existingIndex])) {
        output[existingIndex] = item;
      }
    }
    return output;
  }

  async function getStats({ force = false } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    if (!force && statsCache && Date.now() - statsCache.cachedAt < PAGE_CACHE_TTL) {
      return statsCache.value;
    }
    const { data, error } = await client().rpc("catalog_stats");
    if (error) throw error;
    const value = data || { total_listings: 0, total_games: 0, stores: {}, years: [], sync: [] };
    statsCache = { cachedAt: Date.now(), value };
    return value;
  }

  async function search(options = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    const normalized = {
      query: String(options.query || "").trim(),
      stores: Array.isArray(options.stores) && options.stores.length ? options.stores : null,
      category: options.category && options.category !== "all" ? options.category : null,
      segment: options.segment && options.segment !== "all" ? options.segment : null,
      price: options.price && options.price !== "all" ? options.price : null,
      year: Number.isInteger(Number(options.year)) && Number(options.year) > 1900 ? Number(options.year) : null,
      libraryKeys: Array.isArray(options.libraryKeys) && options.libraryKeys.length ? options.libraryKeys : null,
      favoriteKeys: Array.isArray(options.favoriteKeys) && options.favoriteKeys.length ? options.favoriteKeys : null,
      personalFilter: options.personalFilter && options.personalFilter !== "all" ? options.personalFilter : null,
      sort: options.sort || "relevance",
      limit: Math.max(1, Math.min(Number(options.limit) || 36, 100)),
      offset: Math.max(0, Number(options.offset) || 0),
    };
    const key = cacheKey(normalized);
    const cached = pageCache.get(key);
    if (!options.force && cached && Date.now() - cached.cachedAt < PAGE_CACHE_TTL) {
      return cached.value;
    }

    const { data, error } = await client().rpc("search_catalog", {
      p_query: normalized.query,
      p_stores: normalized.stores,
      p_category: normalized.category,
      p_segment: normalized.segment,
      p_price: normalized.price,
      p_year: normalized.year,
      p_library_keys: normalized.libraryKeys,
      p_favorite_keys: normalized.favoriteKeys,
      p_personal_filter: normalized.personalFilter,
      p_sort: normalized.sort,
      p_limit: normalized.limit,
      p_offset: normalized.offset,
    });
    if (error) throw error;
    const value = {
      items: dedupeCatalogItems((data?.items || []).map(normalizeItem)),
      total: Number(data?.total || 0),
      limit: Number(data?.limit || normalized.limit),
      offset: Number(data?.offset || normalized.offset),
    };
    pageCache.set(key, { cachedAt: Date.now(), value });
    for (const item of value.items) gameCache.set(item.canonical_id, item);
    return value;
  }

  async function getGames(keys) {
    if (!configured()) throw new Error("Supabase non configurato.");
    const unique = [...new Set((keys || []).filter(Boolean))];
    const resolved = [];
    const missing = [];
    for (const key of unique) {
      if (gameCache.has(key)) resolved.push(gameCache.get(key));
      else missing.push(key);
    }
    if (missing.length) {
      const { data, error } = await client().rpc("get_catalog_games", { p_keys: missing });
      if (error) throw error;
      for (const raw of data || []) {
        const value = normalizeItem(raw);
        gameCache.set(value.canonical_id, value);
        if (value.match_key) gameCache.set(value.match_key, value);
        for (const listing of value.store_listings || []) {
          if (listing.listing_id) gameCache.set(listing.listing_id, value);
        }
      }
    }
    return unique.map((key) => gameCache.get(key)).filter(Boolean);
  }

  function cacheResolvedGame(requestedKey, raw) {
    if (!raw) return null;
    const value = normalizeItem(raw);
    if (requestedKey) gameCache.set(requestedKey, value);
    gameCache.set(value.canonical_id, value);
    if (value.match_key) gameCache.set(value.match_key, value);
    if (value.master_game_id) gameCache.set(value.master_game_id, value);
    for (const listing of value.store_listings || []) {
      if (listing.listing_id) gameCache.set(listing.listing_id, value);
    }
    return value;
  }

  async function getGame(key, { force = false } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    const normalizedKey = String(key || "").trim();
    if (!normalizedKey) return null;
    if (!force && gameCache.has(normalizedKey)) return gameCache.get(normalizedKey);

    const requestKey = `${normalizedKey}:${force ? "force" : "normal"}`;
    if (gameRequestCache.has(requestKey)) return gameRequestCache.get(requestKey);

    const request = client()
      .rpc("get_catalog_game", { p_key: normalizedKey })
      .then(({ data, error }) => {
        if (error) throw error;
        return cacheResolvedGame(normalizedKey, data);
      })
      .finally(() => {
        gameRequestCache.delete(requestKey);
      });

    gameRequestCache.set(requestKey, request);
    return request;
  }


  async function getDiscovery({ force = false, limit = 12 } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    if (!force && discoveryCache && Date.now() - discoveryCache.cachedAt < PAGE_CACHE_TTL) {
      return discoveryCache.value;
    }
    const { data, error } = await client().rpc("catalog_discovery", {
      p_limit: Math.max(4, Math.min(Number(limit) || 12, 24)),
    });
    if (error) throw error;
    const value = {
      recent: (data?.recent || []).map(normalizeItem),
      communityTop: (data?.community_top || []).map(normalizeItem),
      mostReviewed: (data?.most_reviewed || []).map(normalizeItem),
      multiStore: (data?.multi_store || []).map(normalizeItem),
      indie: (data?.indie || []).map(normalizeItem),
      generatedAt: data?.generated_at || null,
    };
    for (const group of Object.values(value)) {
      if (!Array.isArray(group)) continue;
      for (const item of group) {
        gameCache.set(item.canonical_id, item);
        if (item.match_key) gameCache.set(item.match_key, item);
      }
    }
    discoveryCache = { cachedAt: Date.now(), value };
    return value;
  }

  async function getRecommendations({ force = false, limit = 12 } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    if (!force && recommendationsCache && Date.now() - recommendationsCache.cachedAt < PAGE_CACHE_TTL) {
      return recommendationsCache.value;
    }
    const { data, error } = await client().rpc("catalog_personalized_recommendations", {
      p_limit: Math.max(4, Math.min(Number(limit) || 12, 24)),
    });
    if (error) throw error;
    const value = {
      mode: data?.mode || "cold_start",
      generatedAt: data?.generated_at || null,
      profile: data?.profile || { positive_signals: 0, negative_signals: 0, similar_users: 0, top_genres: [], top_developers: [] },
      items: dedupeCatalogItems((data?.items || []).map(normalizeItem)),
    };
    for (const item of value.items) {
      gameCache.set(item.canonical_id, item);
      if (item.match_key) gameCache.set(item.match_key, item);
    }
    recommendationsCache = { cachedAt: Date.now(), value };
    return value;
  }

  async function getEntity(kind, name, options = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    const normalizedKind = kind === "publisher" ? "publisher" : "developer";
    const normalizedName = String(name || "").trim();
    const limit = Math.max(1, Math.min(Number(options.limit) || 36, 100));
    const offset = Math.max(0, Number(options.offset) || 0);
    const key = cacheKey({ kind: normalizedKind, name: normalizedName, limit, offset });
    const cached = entityCache.get(key);
    if (!options.force && cached && Date.now() - cached.cachedAt < PAGE_CACHE_TTL) {
      return cached.value;
    }
    const { data, error } = await client().rpc("catalog_entity", {
      p_kind: normalizedKind,
      p_name: normalizedName,
      p_limit: limit,
      p_offset: offset,
    });
    if (error) throw error;
    const value = {
      kind: data?.kind || normalizedKind,
      name: data?.name || normalizedName,
      total: Number(data?.total || 0),
      items: dedupeCatalogItems((data?.items || []).map(normalizeItem)),
      limit: Number(data?.limit || limit),
      offset: Number(data?.offset || offset),
    };
    for (const item of value.items) {
      gameCache.set(item.canonical_id, item);
      if (item.match_key) gameCache.set(item.match_key, item);
    }
    entityCache.set(key, { cachedAt: Date.now(), value });
    return value;
  }

  async function getRelated(key, { force = false, limit = 12 } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    const normalizedKey = String(key || "").trim();
    const cacheId = `${normalizedKey}:${Math.max(1, Math.min(Number(limit) || 12, 24))}`;
    const cached = relatedCache.get(cacheId);
    if (!force && cached && Date.now() - cached.cachedAt < PAGE_CACHE_TTL) {
      return cached.value;
    }
    const { data, error } = await client().rpc("catalog_related_games", {
      p_key: normalizedKey,
      p_limit: Math.max(1, Math.min(Number(limit) || 12, 24)),
    });
    if (error) throw error;
    const value = (data || []).map(normalizeItem);
    for (const item of value) {
      gameCache.set(item.canonical_id, item);
      if (item.match_key) gameCache.set(item.match_key, item);
    }
    relatedCache.set(cacheId, { cachedAt: Date.now(), value });
    return value;
  }


  function clearRecommendationCache() {
    recommendationsCache = null;
  }

  function clearCache() {
    pageCache.clear();
    gameCache.clear();
    entityCache.clear();
    relatedCache.clear();
    statsCache = null;
    discoveryCache = null;
    recommendationsCache = null;
  }

  window.VaultCatalog = {
    configured,
    getStats,
    search,
    getGame,
    getGames,
    getDiscovery,
    getRecommendations,
    getEntity,
    getRelated,
    clearRecommendationCache,
    clearCache,
  };
})();
