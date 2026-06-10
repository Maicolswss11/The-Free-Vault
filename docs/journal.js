(() => {
  const STORAGE_VERSION = 1;
  const GUEST_SCOPE = "guest";
  const STATUS_VALUES = new Set([
    "saved",
    "backlog",
    "playing",
    "paused",
    "completed",
    "abandoned",
    "replay",
  ]);
  const VISIBILITY_VALUES = new Set(["private", "public"]);

  let activeUserId = null;
  let generation = 0;
  let cache = emptyCache();

  function emptyCache() {
    return { progress: {}, entries: {} };
  }

  function scopeKey(userId = activeUserId) {
    const scope = userId || GUEST_SCOPE;
    return `tfv:${scope}:journal:v${STORAGE_VERSION}`;
  }

  function clone(value) {
    if (typeof structuredClone === "function") return structuredClone(value);
    return JSON.parse(JSON.stringify(value));
  }

  function readLocal(userId = activeUserId) {
    try {
      const parsed = JSON.parse(localStorage.getItem(scopeKey(userId)) || "null");
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return emptyCache();
      return {
        progress: parsed.progress && typeof parsed.progress === "object" ? parsed.progress : {},
        entries: parsed.entries && typeof parsed.entries === "object" ? parsed.entries : {},
      };
    } catch {
      return emptyCache();
    }
  }

  function persistLocal() {
    localStorage.setItem(scopeKey(), JSON.stringify(cache));
  }

  function authContext() {
    const auth = window.VaultAuth;
    return {
      client: auth?.client || null,
      user: auth?.user || null,
    };
  }

  function isCurrentCloudUser(expectedUserId = activeUserId) {
    const { client, user } = authContext();
    return Boolean(client && user && expectedUserId && user.id === expectedUserId);
  }

  function normalizeDate(value) {
    if (!value) return null;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
  }

  function normalizeTimestamp(value) {
    const date = value ? new Date(value) : new Date();
    return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
  }

  function numberInRange(value, min, max, fallback = 0) {
    const number = Number(value);
    if (!Number.isFinite(number)) return fallback;
    return Math.min(max, Math.max(min, Math.round(number)));
  }

  function stringOrNull(value, maxLength = 255) {
    const normalized = String(value || "").trim();
    return normalized ? normalized.slice(0, maxLength) : null;
  }

  function normalizeStatus(value) {
    return STATUS_VALUES.has(value) ? value : "saved";
  }

  function normalizeVisibility(value) {
    return VISIBILITY_VALUES.has(value) ? value : "private";
  }

  function progressFromRow(row) {
    return {
      userId: row.user_id,
      gameKey: row.game_key,
      gameTitle: row.game_title,
      gameImageUrl: row.game_image_url,
      status: row.status,
      progressPercent: row.progress_percent,
      startedAt: row.started_at,
      completedAt: row.completed_at,
      completionCount: row.completion_count,
      manualPlaytimeMinutes: row.manual_playtime_minutes,
      primaryPlatform: row.primary_platform,
      difficulty: row.difficulty,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  function progressToRow(progress, userId) {
    return {
      user_id: userId,
      game_key: progress.gameKey,
      game_title: progress.gameTitle,
      game_image_url: progress.gameImageUrl,
      status: progress.status,
      progress_percent: progress.progressPercent,
      started_at: progress.startedAt,
      completed_at: progress.completedAt,
      completion_count: progress.completionCount,
      manual_playtime_minutes: progress.manualPlaytimeMinutes,
      primary_platform: progress.primaryPlatform,
      difficulty: progress.difficulty,
      updated_at: progress.updatedAt,
    };
  }

  function entryFromRow(row) {
    return {
      id: row.id,
      userId: row.user_id,
      gameKey: row.game_key,
      gameTitle: row.game_title,
      gameImageUrl: row.game_image_url,
      playedAt: row.played_at,
      minutesPlayed: row.minutes_played,
      progressPercent: row.progress_percent,
      platform: row.platform,
      note: row.note,
      containsSpoilers: row.contains_spoilers,
      visibility: row.visibility,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  function entryToRow(entry, userId) {
    return {
      id: entry.id,
      user_id: userId,
      game_key: entry.gameKey,
      game_title: entry.gameTitle,
      game_image_url: entry.gameImageUrl,
      played_at: entry.playedAt,
      minutes_played: entry.minutesPlayed,
      progress_percent: entry.progressPercent,
      platform: entry.platform,
      note: entry.note,
      contains_spoilers: entry.containsSpoilers,
      visibility: entry.visibility,
      updated_at: entry.updatedAt,
    };
  }

  function updatedAt(value) {
    return new Date(value?.updatedAt || value?.updated_at || 0).getTime();
  }

  function mergeByUpdatedAt(local, remote) {
    const merged = { ...local };
    for (const [key, value] of Object.entries(remote)) {
      if (!merged[key] || updatedAt(value) >= updatedAt(merged[key])) merged[key] = value;
    }
    return merged;
  }

  async function pullCloud(expectedUserId) {
    const { client, user } = authContext();
    if (!client || !user || user.id !== expectedUserId) return;

    const [progressResult, entriesResult] = await Promise.all([
      client
        .from("user_game_progress")
        .select("user_id, game_key, game_title, game_image_url, status, progress_percent, started_at, completed_at, completion_count, manual_playtime_minutes, primary_platform, difficulty, created_at, updated_at")
        .eq("user_id", expectedUserId),
      client
        .from("game_diary_entries")
        .select("id, user_id, game_key, game_title, game_image_url, played_at, minutes_played, progress_percent, platform, note, contains_spoilers, visibility, created_at, updated_at")
        .eq("user_id", expectedUserId),
    ]);

    if (progressResult.error) throw progressResult.error;
    if (entriesResult.error) throw entriesResult.error;
    if (!isCurrentCloudUser(expectedUserId)) return;

    const remoteProgress = Object.fromEntries(
      (progressResult.data || []).map((row) => [row.game_key, progressFromRow(row)]),
    );
    const remoteEntries = Object.fromEntries(
      (entriesResult.data || []).map((row) => [row.id, entryFromRow(row)]),
    );

    const localBeforeMerge = clone(cache);
    cache.progress = mergeByUpdatedAt(cache.progress, remoteProgress);
    cache.entries = mergeByUpdatedAt(cache.entries, remoteEntries);
    persistLocal();

    const localProgressToPush = Object.values(localBeforeMerge.progress)
      .filter((item) => !remoteProgress[item.gameKey] || updatedAt(item) > updatedAt(remoteProgress[item.gameKey]));
    const localEntriesToPush = Object.values(localBeforeMerge.entries)
      .filter((item) => !remoteEntries[item.id] || updatedAt(item) > updatedAt(remoteEntries[item.id]));

    if (localProgressToPush.length) {
      const { error } = await client.from("user_game_progress").upsert(
        localProgressToPush.map((item) => progressToRow(item, expectedUserId)),
        { onConflict: "user_id,game_key" },
      );
      if (error) throw error;
    }
    if (localEntriesToPush.length) {
      const { error } = await client.from("game_diary_entries").upsert(
        localEntriesToPush.map((item) => entryToRow(item, expectedUserId)),
        { onConflict: "id" },
      );
      if (error) throw error;
    }
  }

  async function setUser(userId) {
    generation += 1;
    const currentGeneration = generation;
    activeUserId = userId || null;
    cache = readLocal(activeUserId);

    if (!activeUserId || !isCurrentCloudUser(activeUserId)) {
      window.dispatchEvent(new CustomEvent("tfv:journal-changed"));
      return snapshot();
    }

    try {
      await pullCloud(activeUserId);
    } catch (error) {
      console.error("Sincronizzazione diario fallita", error);
      window.dispatchEvent(new CustomEvent("tfv:journal-sync-error", { detail: error }));
    }
    if (currentGeneration !== generation) return snapshot();
    window.dispatchEvent(new CustomEvent("tfv:journal-changed"));
    return snapshot();
  }

  function snapshot() {
    return clone(cache);
  }

  function getProgress(gameKey) {
    return cache.progress[gameKey] ? clone(cache.progress[gameKey]) : null;
  }

  function listProgress() {
    return Object.values(cache.progress).map(clone);
  }

  function listEntries({ gameKey = null, limit = null, visibility = null } = {}) {
    let entries = Object.values(cache.entries);
    if (gameKey) entries = entries.filter((entry) => entry.gameKey === gameKey);
    if (visibility) entries = entries.filter((entry) => entry.visibility === visibility);
    entries.sort((a, b) => {
      const played = String(b.playedAt || "").localeCompare(String(a.playedAt || ""));
      return played || String(b.createdAt || "").localeCompare(String(a.createdAt || ""));
    });
    return (limit ? entries.slice(0, limit) : entries).map(clone);
  }

  async function saveProgress(input) {
    const gameKey = String(input.gameKey || "").trim();
    const gameTitle = String(input.gameTitle || "").trim();
    if (!gameKey || !gameTitle) throw new Error("Gioco non valido.");

    const previous = cache.progress[gameKey] || {};
    const now = new Date().toISOString();
    const status = normalizeStatus(input.status ?? previous.status);
    const progressPercent = numberInRange(input.progressPercent ?? previous.progressPercent, 0, 100, 0);
    const completedAt = normalizeDate(input.completedAt ?? previous.completedAt);

    const progress = {
      ...previous,
      gameKey,
      gameTitle,
      gameImageUrl: stringOrNull(input.gameImageUrl ?? previous.gameImageUrl, 2000),
      status,
      progressPercent,
      startedAt: normalizeDate(input.startedAt ?? previous.startedAt),
      completedAt,
      completionCount: numberInRange(input.completionCount ?? previous.completionCount, 0, 999, 0),
      manualPlaytimeMinutes: numberInRange(input.manualPlaytimeMinutes ?? previous.manualPlaytimeMinutes, 0, 10000000, 0),
      primaryPlatform: stringOrNull(input.primaryPlatform ?? previous.primaryPlatform, 80),
      difficulty: stringOrNull(input.difficulty ?? previous.difficulty, 80),
      createdAt: previous.createdAt || now,
      updatedAt: now,
    };

    if (status === "completed" && !progress.completedAt) {
      progress.completedAt = new Date().toISOString().slice(0, 10);
    }
    if (["playing", "completed", "paused", "replay"].includes(status) && !progress.startedAt) {
      progress.startedAt = new Date().toISOString().slice(0, 10);
    }

    cache.progress[gameKey] = progress;
    persistLocal();
    window.dispatchEvent(new CustomEvent("tfv:journal-changed", { detail: { gameKey } }));

    if (isCurrentCloudUser()) {
      const { client, user } = authContext();
      const { error } = await client.from("user_game_progress").upsert(
        progressToRow(progress, user.id),
        { onConflict: "user_id,game_key" },
      );
      if (error) throw error;
    }
    return clone(progress);
  }

  async function addEntry(input) {
    const gameKey = String(input.gameKey || "").trim();
    const gameTitle = String(input.gameTitle || "").trim();
    if (!gameKey || !gameTitle) throw new Error("Gioco non valido.");

    const now = new Date().toISOString();
    const entry = {
      id: input.id || crypto.randomUUID(),
      gameKey,
      gameTitle,
      gameImageUrl: stringOrNull(input.gameImageUrl, 2000),
      playedAt: normalizeDate(input.playedAt) || now.slice(0, 10),
      minutesPlayed: numberInRange(input.minutesPlayed, 1, 1440, 1),
      progressPercent: input.progressPercent === null || input.progressPercent === ""
        ? null
        : numberInRange(input.progressPercent, 0, 100, 0),
      platform: stringOrNull(input.platform, 80),
      note: stringOrNull(input.note, 3000),
      containsSpoilers: Boolean(input.containsSpoilers),
      visibility: normalizeVisibility(input.visibility),
      createdAt: input.createdAt || now,
      updatedAt: now,
    };

    cache.entries[entry.id] = entry;
    persistLocal();
    window.dispatchEvent(new CustomEvent("tfv:journal-changed", { detail: { gameKey } }));

    if (isCurrentCloudUser()) {
      const { client, user } = authContext();
      const { error } = await client.from("game_diary_entries").upsert(
        entryToRow(entry, user.id),
        { onConflict: "id" },
      );
      if (error) throw error;
    }
    return clone(entry);
  }

  async function deleteEntry(id) {
    const entry = cache.entries[id];
    if (!entry) return;
    delete cache.entries[id];
    persistLocal();
    window.dispatchEvent(new CustomEvent("tfv:journal-changed", { detail: { gameKey: entry.gameKey } }));

    if (isCurrentCloudUser()) {
      const { client, user } = authContext();
      const { error } = await client
        .from("game_diary_entries")
        .delete()
        .eq("id", id)
        .eq("user_id", user.id);
      if (error) throw error;
    }
  }

  async function deleteProgress(gameKey) {
    delete cache.progress[gameKey];
    persistLocal();
    if (isCurrentCloudUser()) {
      const { client, user } = authContext();
      const { error } = await client
        .from("user_game_progress")
        .delete()
        .eq("user_id", user.id)
        .eq("game_key", gameKey);
      if (error) throw error;
    }
  }

  async function getPublicEntries(userId, limit = 12) {
    const { client } = authContext();
    if (!client || !userId) return [];
    const { data, error } = await client
      .from("game_diary_entries")
      .select("id, user_id, game_key, game_title, game_image_url, played_at, minutes_played, progress_percent, platform, note, contains_spoilers, visibility, created_at, updated_at")
      .eq("user_id", userId)
      .eq("visibility", "public")
      .order("played_at", { ascending: false })
      .limit(limit);
    if (error) throw error;
    return (data || []).map(entryFromRow);
  }

  function summarize({ ownedListings = [] } = {}) {
    const progress = listProgress();
    const entries = listEntries();
    const statusCounts = {};
    for (const item of progress) statusCounts[item.status] = (statusCounts[item.status] || 0) + 1;

    const sessionMinutes = entries.reduce((sum, entry) => sum + Number(entry.minutesPlayed || 0), 0);
    const steamMinutes = (ownedListings || []).reduce((sum, item) => sum + Number(item.playtime_minutes || 0), 0);
    const completed = statusCounts.completed || 0;
    const backlog = statusCounts.backlog || 0;
    const started = progress.filter((item) => ["playing", "paused", "completed", "abandoned", "replay"].includes(item.status)).length;

    const monthly = new Map();
    const platforms = new Map();
    const games = new Map();
    for (const entry of entries) {
      const month = String(entry.playedAt || "").slice(0, 7);
      if (month) monthly.set(month, (monthly.get(month) || 0) + Number(entry.minutesPlayed || 0));
      const platform = entry.platform || "Non indicata";
      platforms.set(platform, (platforms.get(platform) || 0) + Number(entry.minutesPlayed || 0));
      const game = games.get(entry.gameKey) || {
        gameKey: entry.gameKey,
        gameTitle: entry.gameTitle,
        gameImageUrl: entry.gameImageUrl,
        minutes: 0,
        sessions: 0,
      };
      game.minutes += Number(entry.minutesPlayed || 0);
      game.sessions += 1;
      games.set(entry.gameKey, game);
    }

    return {
      progressCount: progress.length,
      sessions: entries.length,
      sessionMinutes,
      steamMinutes,
      totalMinutes: Math.max(sessionMinutes, 0) + Math.max(steamMinutes, 0),
      completed,
      backlog,
      started,
      completionRate: started ? Math.round((completed / started) * 100) : 0,
      statusCounts,
      monthly: [...monthly.entries()].sort(([a], [b]) => a.localeCompare(b)),
      platforms: [...platforms.entries()].sort((a, b) => b[1] - a[1]),
      topGames: [...games.values()].sort((a, b) => b.minutes - a.minutes).slice(0, 8),
    };
  }


  async function importData(data) {
    const incoming = data && typeof data === "object" ? data : {};
    const progress = incoming.progress && typeof incoming.progress === "object" ? incoming.progress : {};
    const entries = incoming.entries && typeof incoming.entries === "object" ? incoming.entries : {};
    cache.progress = mergeByUpdatedAt(cache.progress, progress);
    cache.entries = mergeByUpdatedAt(cache.entries, entries);
    persistLocal();

    if (isCurrentCloudUser()) {
      const { client, user } = authContext();
      const progressRows = Object.values(progress).map((item) => progressToRow(item, user.id));
      const entryRows = Object.values(entries).map((item) => entryToRow(item, user.id));
      if (progressRows.length) {
        const { error } = await client.from("user_game_progress").upsert(progressRows, { onConflict: "user_id,game_key" });
        if (error) throw error;
      }
      if (entryRows.length) {
        const { error } = await client.from("game_diary_entries").upsert(entryRows, { onConflict: "id" });
        if (error) throw error;
      }
    }
    window.dispatchEvent(new CustomEvent("tfv:journal-changed"));
    return snapshot();
  }

  function clearScope(userId = activeUserId) {
    localStorage.removeItem(scopeKey(userId));
    if ((userId || null) === activeUserId) cache = emptyCache();
  }

  cache = readLocal(null);

  window.VaultJournal = Object.freeze({
    setUser,
    snapshot,
    getProgress,
    listProgress,
    listEntries,
    saveProgress,
    deleteProgress,
    addEntry,
    deleteEntry,
    getPublicEntries,
    summarize,
    importData,
    clearScope,
  });
})();
