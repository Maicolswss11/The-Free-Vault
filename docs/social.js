(() => {
  function client() {
    return window.VaultAuth?.client || null;
  }

  function currentUser() {
    return window.VaultAuth?.user || null;
  }

  function requireClient() {
    const value = client();
    if (!value) throw new Error("Supabase non configurato.");
    return value;
  }

  function requireUser() {
    const user = currentUser();
    if (!user) throw new Error("Accedi per usare questa funzione.");
    return user;
  }

  function normalizeAuthor(row) {
    if (!row) return null;
    return Array.isArray(row) ? row[0] || null : row;
  }

  function normalizeReview(row) {
    if (!row) return null;
    return { ...row, author: normalizeAuthor(row.author) };
  }

  function normalizeComment(row) {
    if (!row) return null;
    return { ...row, author: normalizeAuthor(row.author) };
  }

  function normalizeActivity(row) {
    if (!row) return null;
    return { ...row, author: normalizeAuthor(row.author) };
  }

  function normalizeNotification(row) {
    if (!row) return null;
    return { ...row, actor: normalizeAuthor(row.actor) };
  }

  function normalizeKeys(value) {
    const keys = Array.isArray(value) ? value : [value];
    return [...new Set(keys.filter(Boolean).map(String))];
  }

  async function getEngagement(targetType, targetIds) {
    const db = requireClient();
    const ids = normalizeKeys(targetIds);
    if (!ids.length) return {};

    const table = targetType === "review" ? "review_likes" : "list_likes";
    const idColumn = targetType === "review" ? "review_id" : "list_id";
    const user = currentUser();

    const [likesResult, commentsResult] = await Promise.all([
      db.from(table).select(`${idColumn}, user_id`).in(idColumn, ids),
      db
        .from("content_comments")
        .select("target_id")
        .eq("target_type", targetType)
        .in("target_id", ids),
    ]);
    if (likesResult.error) throw likesResult.error;
    if (commentsResult.error) throw commentsResult.error;

    const result = Object.fromEntries(ids.map((id) => [id, {
      like_count: 0,
      comment_count: 0,
      liked_by_me: false,
    }]));

    for (const row of likesResult.data || []) {
      const id = row[idColumn];
      if (!result[id]) continue;
      result[id].like_count += 1;
      if (user && row.user_id === user.id) result[id].liked_by_me = true;
    }
    for (const row of commentsResult.data || []) {
      if (result[row.target_id]) result[row.target_id].comment_count += 1;
    }
    return result;
  }

  async function getGameReviews(gameKeys) {
    const db = requireClient();
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return [];

    let query = db
      .from("game_reviews")
      .select(`
        id, user_id, game_key, game_title, game_image_url, store_url,
        rating, title, body, contains_spoilers, created_at, updated_at,
        author:profiles!game_reviews_user_id_fkey (
          id, username, display_name, avatar_url, is_public
        )
      `);
    query = keys.length === 1
      ? query.eq("game_key", keys[0])
      : query.in("game_key", keys);

    const { data, error } = await query.order("updated_at", { ascending: false });
    if (error) throw error;

    const reviews = (data || []).map(normalizeReview);
    const engagement = await getEngagement("review", reviews.map((review) => review.id));
    return reviews.map((review) => ({ ...review, ...(engagement[review.id] || {}) }));
  }

  async function getMyReview(gameKeys) {
    const db = requireClient();
    const user = currentUser();
    if (!user) return null;
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return null;

    let query = db
      .from("game_reviews")
      .select("id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at")
      .eq("user_id", user.id);
    query = keys.length === 1
      ? query.eq("game_key", keys[0])
      : query.in("game_key", keys);

    const { data, error } = await query
      .order("updated_at", { ascending: false })
      .limit(1);
    if (error) throw error;
    return data?.[0] || null;
  }

  async function saveReview({ game, rating, title, body, containsSpoilers }) {
    const db = requireClient();
    const user = requireUser();
    const numericRating = Number(rating);
    if (!Number.isInteger(numericRating) || numericRating < 1 || numericRating > 5) {
      throw new Error("Seleziona un voto da 1 a 5.");
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
        .from("game_reviews")
        .delete()
        .eq("user_id", user.id)
        .in("game_key", legacyKeys);
      if (cleanupError) throw cleanupError;
    }

    const payload = {
      user_id: user.id,
      game_key: canonicalKey,
      game_title: String(game.title || "Gioco").slice(0, 200),
      game_image_url: game.image_url || null,
      store_url: game.store_url || null,
      rating: numericRating,
      title: title?.trim() || null,
      body: body?.trim() || null,
      contains_spoilers: Boolean(containsSpoilers),
      updated_at: new Date().toISOString(),
    };

    const { data, error } = await db
      .from("game_reviews")
      .upsert(payload, { onConflict: "user_id,game_key" })
      .select("id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at")
      .single();
    if (error) throw error;
    return data;
  }

  async function deleteReview(gameKeys) {
    const db = requireClient();
    const user = requireUser();
    const keys = normalizeKeys(gameKeys);
    if (!keys.length) return;

    let query = db.from("game_reviews").delete().eq("user_id", user.id);
    query = keys.length === 1
      ? query.eq("game_key", keys[0])
      : query.in("game_key", keys);
    const { error } = await query;
    if (error) throw error;
  }

  async function toggleReviewLike(reviewId, currentlyLiked) {
    const db = requireClient();
    const user = requireUser();
    const query = db.from("review_likes");
    const { error } = currentlyLiked
      ? await query.delete().eq("review_id", reviewId).eq("user_id", user.id)
      : await query.insert({ review_id: reviewId, user_id: user.id });
    if (error) throw error;
    return !currentlyLiked;
  }

  async function toggleListLike(listId, currentlyLiked) {
    const db = requireClient();
    const user = requireUser();
    const query = db.from("list_likes");
    const { error } = currentlyLiked
      ? await query.delete().eq("list_id", listId).eq("user_id", user.id)
      : await query.insert({ list_id: listId, user_id: user.id });
    if (error) throw error;
    return !currentlyLiked;
  }

  async function getComments(targetType, targetId) {
    const db = requireClient();
    const { data, error } = await db
      .from("content_comments")
      .select(`
        id, user_id, target_type, target_id, body, created_at, updated_at,
        author:profiles!content_comments_user_id_fkey (
          id, username, display_name, avatar_url
        )
      `)
      .eq("target_type", targetType)
      .eq("target_id", targetId)
      .order("created_at", { ascending: true });
    if (error) throw error;
    return (data || []).map(normalizeComment);
  }

  async function addComment(targetType, targetId, body) {
    const db = requireClient();
    const user = requireUser();
    const cleanBody = String(body || "").trim();
    if (!cleanBody) throw new Error("Scrivi un commento.");
    if (cleanBody.length > 2000) throw new Error("Il commento supera 2000 caratteri.");

    const { data, error } = await db
      .from("content_comments")
      .insert({
        user_id: user.id,
        target_type: targetType,
        target_id: targetId,
        body: cleanBody,
      })
      .select(`
        id, user_id, target_type, target_id, body, created_at, updated_at,
        author:profiles!content_comments_user_id_fkey (
          id, username, display_name, avatar_url
        )
      `)
      .single();
    if (error) throw error;
    return normalizeComment(data);
  }

  async function deleteComment(commentId) {
    const db = requireClient();
    const user = requireUser();
    const { error } = await db
      .from("content_comments")
      .delete()
      .eq("id", commentId)
      .eq("user_id", user.id);
    if (error) throw error;
  }

  async function getPublicProfile(username) {
    const db = requireClient();
    const normalized = decodeURIComponent(username || "").trim();
    const { data, error } = await db
      .from("profiles")
      .select("id, username, display_name, bio, avatar_url, is_public, created_at, updated_at")
      .eq("username", normalized)
      .maybeSingle();
    if (error) throw error;
    return data || null;
  }

  async function getFollowState(profileId) {
    const db = requireClient();
    const user = currentUser();
    const [countsResult, mineResult] = await Promise.all([
      db.rpc("get_follow_counts", { requested_id: profileId }),
      user
        ? db
            .from("user_follows")
            .select("follower_id")
            .eq("follower_id", user.id)
            .eq("following_id", profileId)
            .maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ]);
    if (countsResult.error) throw countsResult.error;
    if (mineResult.error) throw mineResult.error;
    const counts = Array.isArray(countsResult.data)
      ? countsResult.data[0] || {}
      : countsResult.data || {};
    return {
      followers: Number(counts.followers || 0),
      following: Number(counts.following || 0),
      is_following: Boolean(mineResult.data),
      is_self: Boolean(user && user.id === profileId),
    };
  }

  async function followUser(profileId) {
    const db = requireClient();
    const user = requireUser();
    const { error } = await db
      .from("user_follows")
      .insert({ follower_id: user.id, following_id: profileId });
    if (error) throw error;
  }

  async function unfollowUser(profileId) {
    const db = requireClient();
    const user = requireUser();
    const { error } = await db
      .from("user_follows")
      .delete()
      .eq("follower_id", user.id)
      .eq("following_id", profileId);
    if (error) throw error;
  }

  async function getPublicProfileContent(userId) {
    const db = requireClient();
    const [reviewsResult, listsResult, followState] = await Promise.all([
      db
        .from("game_reviews")
        .select("id, user_id, game_key, game_title, game_image_url, store_url, rating, title, body, contains_spoilers, created_at, updated_at")
        .eq("user_id", userId)
        .order("updated_at", { ascending: false }),
      db
        .from("user_lists")
        .select("id, user_id, name, description, visibility, game_keys, created_at, updated_at")
        .eq("user_id", userId)
        .eq("visibility", "public")
        .order("updated_at", { ascending: false }),
      getFollowState(userId),
    ]);
    if (reviewsResult.error) throw reviewsResult.error;
    if (listsResult.error) throw listsResult.error;
    return {
      reviews: reviewsResult.data || [],
      lists: listsResult.data || [],
      follow: followState,
    };
  }

  async function getSharedList(listId) {
    const db = requireClient();
    const { data: list, error } = await db
      .from("user_lists")
      .select("id, user_id, name, description, visibility, game_keys, created_at, updated_at")
      .eq("id", listId)
      .maybeSingle();
    if (error) throw error;
    if (!list) return null;

    const [{ data: author, error: authorError }, engagement] = await Promise.all([
      db
        .from("profiles")
        .select("id, username, display_name, avatar_url, is_public")
        .eq("id", list.user_id)
        .maybeSingle(),
      getEngagement("list", [list.id]),
    ]);
    if (authorError) throw authorError;
    return {
      ...list,
      author: author || null,
      ...(engagement[list.id] || {}),
    };
  }

  async function exploreUsers(search = "", limit = 36) {
    const db = requireClient();
    let query = db
      .from("profiles")
      .select("id, username, display_name, bio, avatar_url, created_at")
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(limit);

    const term = String(search || "").trim().replace(/[,%()]/g, " ");
    if (term) {
      query = query.or(`username.ilike.%${term}%,display_name.ilike.%${term}%`);
    }

    const { data, error } = await query;
    if (error) throw error;
    return data || [];
  }

  async function getActivityFeed({ followingOnly = true, limit = 60 } = {}) {
    const db = requireClient();
    const user = currentUser();
    let ids = [];

    if (user && followingOnly) {
      const { data: follows, error: followsError } = await db
        .from("user_follows")
        .select("following_id")
        .eq("follower_id", user.id);
      if (followsError) throw followsError;
      ids = [user.id, ...(follows || []).map((row) => row.following_id)];
    }

    let query = db
      .from("activities")
      .select(`
        id, user_id, activity_type, target_type, target_id, metadata, created_at,
        author:profiles!activities_user_id_fkey (
          id, username, display_name, avatar_url
        )
      `)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (followingOnly && user) {
      if (!ids.length) return [];
      query = query.in("user_id", ids);
    }

    const { data, error } = await query;
    if (error) throw error;
    return (data || []).map(normalizeActivity);
  }

  async function getNotifications(limit = 80) {
    const db = requireClient();
    const user = requireUser();
    const { data, error } = await db
      .from("user_notifications")
      .select(`
        id, user_id, actor_id, notification_type, target_type, target_id,
        metadata, read_at, created_at,
        actor:profiles!user_notifications_actor_id_fkey (
          id, username, display_name, avatar_url
        )
      `)
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) throw error;
    return (data || []).map(normalizeNotification);
  }

  async function getUnreadNotificationCount() {
    const db = requireClient();
    const user = currentUser();
    if (!user) return 0;
    const { count, error } = await db
      .from("user_notifications")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .is("read_at", null);
    if (error) throw error;
    return count || 0;
  }

  async function markNotificationRead(notificationId) {
    const db = requireClient();
    const user = requireUser();
    const { error } = await db
      .from("user_notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("id", notificationId)
      .eq("user_id", user.id);
    if (error) throw error;
  }

  async function markAllNotificationsRead() {
    const db = requireClient();
    const user = requireUser();
    const { error } = await db
      .from("user_notifications")
      .update({ read_at: new Date().toISOString() })
      .eq("user_id", user.id)
      .is("read_at", null);
    if (error) throw error;
  }

  function summarizeRatings(reviews) {
    const ratings = (reviews || [])
      .map((review) => Number(review.rating))
      .filter((value) => value >= 1 && value <= 5);
    const count = ratings.length;
    const average = count
      ? ratings.reduce((sum, value) => sum + value, 0) / count
      : 0;
    return { count, average };
  }

  window.VaultSocial = {
    getGameReviews,
    getMyReview,
    saveReview,
    deleteReview,
    toggleReviewLike,
    toggleListLike,
    getComments,
    addComment,
    deleteComment,
    getPublicProfile,
    getFollowState,
    followUser,
    unfollowUser,
    getPublicProfileContent,
    getSharedList,
    exploreUsers,
    getActivityFeed,
    getNotifications,
    getUnreadNotificationCount,
    markNotificationRead,
    markAllNotificationsRead,
    getEngagement,
    summarizeRatings,
  };
})();
