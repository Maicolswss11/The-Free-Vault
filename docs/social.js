(() => {
  function client() {
    return window.VaultAuth?.client || null;
  }

  function currentUser() {
    return window.VaultAuth?.user || null;
  }

  function requireClient() {
    const value = client();
    if (!value) throw new Error('Supabase non configurato.');
    return value;
  }

  function normalizeReview(row) {
    if (!row) return null;
    const author = Array.isArray(row.author) ? row.author[0] : row.author;
    return { ...row, author: author || null };
  }

  function normalizeKeys(value) {
    const keys = Array.isArray(value) ? value : [value];
    return [...new Set(keys.filter(Boolean).map(String))];
  }

  async function getGameReviews(gameKeys) {
    const db = requireClient();
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return [];
    let query = db
      .from('game_reviews')
      .select(`
        id, user_id, game_key, game_title, game_image_url, store_url,
        rating, title, body, contains_spoilers, created_at, updated_at,
        author:profiles!game_reviews_user_id_fkey (
          username, display_name, avatar_url, is_public
        )
      `);
    query = keys.length === 1
      ? query.eq('game_key', keys[0])
      : query.in('game_key', keys);
    const { data, error } = await query.order('updated_at', { ascending: false });
    if (error) throw error;
    return (data || []).map(normalizeReview);
  }

  async function getMyReview(gameKeys) {
    const db = requireClient();
    const user = currentUser();
    if (!user) return null;
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return null;
    let query = db
      .from('game_reviews')
      .select('id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at')
      .eq('user_id', user.id);
    query = keys.length === 1
      ? query.eq('game_key', keys[0])
      : query.in('game_key', keys);
    const { data, error } = await query
      .order('updated_at', { ascending: false })
      .limit(1);
    if (error) throw error;
    return data?.[0] || null;
  }

  async function saveReview({ game, rating, title, body, containsSpoilers }) {
    const db = requireClient();
    const user = currentUser();
    if (!user) throw new Error('Accedi per pubblicare una recensione.');
    const numericRating = Number(rating);
    if (!Number.isInteger(numericRating) || numericRating < 1 || numericRating > 5) {
      throw new Error('Seleziona un voto da 1 a 5.');
    }

    const canonicalKey = game.canonical_id || game.internal_id || game.listing_id || game.epic_id || game.promotion_key || game.title;
    const legacyKeys = normalizeKeys([
      game.internal_id,
      game.listing_id,
      game.epic_id,
      game.promotion_key,
      game.external_id,
      game.namespace && (game.external_id || game.epic_id)
        ? `epic:${game.namespace}:${game.external_id || game.epic_id}`
        : null,
    ]).filter((key) => key !== canonicalKey);

    if (legacyKeys.length) {
      const { error: cleanupError } = await db
        .from('game_reviews')
        .delete()
        .eq('user_id', user.id)
        .in('game_key', legacyKeys);
      if (cleanupError) throw cleanupError;
    }

    const payload = {
      user_id: user.id,
      game_key: canonicalKey,
      game_title: String(game.title || 'Gioco').slice(0, 200),
      game_image_url: game.image_url || null,
      store_url: game.store_url || null,
      rating: numericRating,
      title: title?.trim() || null,
      body: body?.trim() || null,
      contains_spoilers: Boolean(containsSpoilers),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await db
      .from('game_reviews')
      .upsert(payload, { onConflict: 'user_id,game_key' })
      .select('id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at')
      .single();
    if (error) throw error;
    return data;
  }

  async function deleteReview(gameKeys) {
    const db = requireClient();
    const user = currentUser();
    if (!user) throw new Error('Utente non autenticato.');
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return;
    let query = db
      .from('game_reviews')
      .delete()
      .eq('user_id', user.id);
    query = keys.length === 1
      ? query.eq('game_key', keys[0])
      : query.in('game_key', keys);
    const { error } = await query;
    if (error) throw error;
  }

  async function getPublicProfile(username) {
    const db = requireClient();
    const normalized = decodeURIComponent(username || '').trim();
    const { data, error } = await db
      .from('profiles')
      .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
      .eq('username', normalized)
      .maybeSingle();
    if (error) throw error;
    return data || null;
  }

  async function getPublicProfileContent(userId) {
    const db = requireClient();
    const [reviewsResult, listsResult] = await Promise.all([
      db
        .from('game_reviews')
        .select('id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at')
        .eq('user_id', userId)
        .order('updated_at', { ascending: false }),
      db
        .from('user_lists')
        .select('id, user_id, name, description, visibility, game_keys, created_at, updated_at')
        .eq('user_id', userId)
        .eq('visibility', 'public')
        .order('updated_at', { ascending: false }),
    ]);
    if (reviewsResult.error) throw reviewsResult.error;
    if (listsResult.error) throw listsResult.error;
    return {
      reviews: reviewsResult.data || [],
      lists: listsResult.data || [],
    };
  }

  async function getSharedList(listId) {
    const db = requireClient();
    const { data: list, error } = await db
      .from('user_lists')
      .select('id, user_id, name, description, visibility, game_keys, created_at, updated_at')
      .eq('id', listId)
      .maybeSingle();
    if (error) throw error;
    if (!list) return null;

    const { data: author, error: authorError } = await db
      .from('profiles')
      .select('id, username, display_name, avatar_url, is_public')
      .eq('id', list.user_id)
      .maybeSingle();
    if (authorError) throw authorError;
    return { ...list, author: author || null };
  }

  function summarizeRatings(reviews) {
    const ratings = (reviews || []).map((review) => Number(review.rating)).filter((value) => value >= 1 && value <= 5);
    const count = ratings.length;
    const average = count ? ratings.reduce((sum, value) => sum + value, 0) / count : 0;
    return { count, average };
  }

  window.VaultSocial = {
    getGameReviews,
    getMyReview,
    saveReview,
    deleteReview,
    getPublicProfile,
    getPublicProfileContent,
    getSharedList,
    summarizeRatings,
  };
})();
