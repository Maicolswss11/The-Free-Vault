(() => {
  const PAGE_CACHE_TTL = 5 * 60 * 1000;
  const pageCache = new Map();
  const gameCache = new Map();
  let statsCache = null;

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
      source_kind: "catalog",
      store: item?.store || primary.store || "epic",
      stores: Array.isArray(item?.stores) ? item.stores : listings.map((entry) => entry.store),
      store_listings: listings,
      store_url: item?.store_url || primary.store_url || "#",
      image_url: item?.image_url || primary.image_url || null,
      original_price: item?.original_price ?? primary.original_price ?? null,
      discount_price: item?.discount_price ?? primary.discount_price ?? null,
      currency_code: item?.currency_code || primary.currency_code || null,
      fmt_original_price: item?.fmt_original_price || primary.fmt_original_price || null,
      fmt_discount_price: item?.fmt_discount_price || primary.fmt_discount_price || null,
    };
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
      items: (data?.items || []).map(normalizeItem),
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

  async function getGame(key, { force = false } = {}) {
    if (!configured()) throw new Error("Supabase non configurato.");
    if (!force && gameCache.has(key)) return gameCache.get(key);
    const { data, error } = await client().rpc("get_catalog_game", { p_key: key });
    if (error) throw error;
    if (!data) return null;
    const value = normalizeItem(data);
    gameCache.set(key, value);
    gameCache.set(value.canonical_id, value);
    if (value.match_key) gameCache.set(value.match_key, value);
    for (const listing of value.store_listings || []) {
      if (listing.listing_id) gameCache.set(listing.listing_id, value);
    }
    return value;
  }

  function clearCache() {
    pageCache.clear();
    gameCache.clear();
    statsCache = null;
  }

  window.VaultCatalog = {
    configured,
    getStats,
    search,
    getGame,
    getGames,
    clearCache,
  };
})();
