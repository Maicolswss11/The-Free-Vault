(() => {
  let timer = null;
  let syncingUserId = null;
  let syncedLibrary = {};
  let syncedLists = {};

  const LIBRARY_BATCH_SIZE = 75;
  const LIST_BATCH_SIZE = 50;

  function clientAndUser() {
    const auth = window.VaultAuth;
    return { client: auth?.client, user: auth?.user };
  }

  function cloneValue(value) {
    if (typeof structuredClone === "function") return structuredClone(value);
    return JSON.parse(JSON.stringify(value));
  }

  function assertCurrentUser(expectedUserId) {
    const { client, user } = clientAndUser();
    if (!client || !user) return { client: null, user: null };
    if (expectedUserId && user.id !== expectedUserId) {
      throw new Error("Sessione cambiata durante la sincronizzazione cloud.");
    }
    return { client, user };
  }

  function entryUpdatedAt(entry) {
    return entry?.updatedAt || entry?.updated_at || entry?.addedAt || new Date(0).toISOString();
  }

  function validTimestamp(value, fallback) {
    const parsed = Date.parse(value || "");
    return Number.isFinite(parsed) ? new Date(parsed).toISOString() : fallback;
  }

  function chunks(values, size) {
    const output = [];
    for (let index = 0; index < values.length; index += size) {
      output.push(values.slice(index, index + size));
    }
    return output;
  }

  function sameValue(left, right) {
    return JSON.stringify(left ?? null) === JSON.stringify(right ?? null);
  }

  function mergeLibrary(localLibrary, rows) {
    const merged = { ...localLibrary };
    for (const row of rows || []) {
      const remote = row.data || {};
      const local = merged[row.game_key];
      if (!local || new Date(row.updated_at) >= new Date(entryUpdatedAt(local))) {
        merged[row.game_key] = { ...remote, updatedAt: row.updated_at };
      }
    }
    return merged;
  }

  function mergeLists(localLists, rows) {
    const merged = { ...localLists };
    for (const row of rows || []) {
      const remote = {
        id: row.id,
        name: row.name,
        description: row.description || "",
        visibility: row.visibility || "private",
        games: row.game_keys || [],
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      };
      const local = merged[row.id];
      if (!local || new Date(row.updated_at) >= new Date(local.updatedAt || 0)) {
        merged[row.id] = remote;
      }
    }
    return merged;
  }

  function pendingLibraryChanges(localLibrary, remoteRows) {
    const remoteByKey = new Map((remoteRows || []).map((row) => [row.game_key, row]));
    const pending = {};
    for (const [gameKey, entry] of Object.entries(localLibrary || {})) {
      const remote = remoteByKey.get(gameKey);
      if (!remote || new Date(entryUpdatedAt(entry)) > new Date(remote.updated_at || 0)) {
        pending[gameKey] = entry;
      }
    }
    return pending;
  }

  function pendingListChanges(localLists, remoteRows) {
    const remoteById = new Map((remoteRows || []).map((row) => [row.id, row]));
    const pending = {};
    for (const [listId, list] of Object.entries(localLists || {})) {
      const remote = remoteById.get(listId);
      if (!remote || new Date(list.updatedAt || 0) > new Date(remote.updated_at || 0)) {
        pending[listId] = list;
      }
    }
    return pending;
  }

  function changedLibraryEntries(library) {
    const changed = {};
    for (const [gameKey, entry] of Object.entries(library || {})) {
      if (!sameValue(entry, syncedLibrary[gameKey])) changed[gameKey] = entry;
    }
    return changed;
  }

  function changedLists(lists) {
    const changed = {};
    for (const [listId, list] of Object.entries(lists || {})) {
      if (!sameValue(list, syncedLists[listId])) changed[listId] = list;
    }
    return changed;
  }

  async function pull(localLibrary, localLists, expectedUserId = null) {
    const { client, user } = assertCurrentUser(expectedUserId);
    if (!client || !user) {
      return {
        library: localLibrary,
        lists: localLists,
        pendingLibrary: localLibrary,
        pendingLists: localLists,
      };
    }
    const userId = user.id;

    const [libraryResult, listsResult] = await Promise.all([
      client.from("user_library").select("game_key, data, updated_at").eq("user_id", userId),
      client.from("user_lists").select("id, name, description, visibility, game_keys, created_at, updated_at").eq("user_id", userId),
    ]);
    if (libraryResult.error) throw libraryResult.error;
    if (listsResult.error) throw listsResult.error;

    assertCurrentUser(userId);
    const pendingLibrary = pendingLibraryChanges(localLibrary, libraryResult.data);
    const pendingLists = pendingListChanges(localLists, listsResult.data);
    const library = mergeLibrary(localLibrary, libraryResult.data);
    const lists = mergeLists(localLists, listsResult.data);

    syncedLibrary = Object.fromEntries((libraryResult.data || []).map((row) => [
      row.game_key,
      { ...(row.data || {}), updatedAt: row.updated_at },
    ]));
    syncedLists = Object.fromEntries((listsResult.data || []).map((row) => [
      row.id,
      {
        id: row.id,
        name: row.name,
        description: row.description || "",
        visibility: row.visibility || "private",
        games: row.game_keys || [],
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
    ]));

    return { library, lists, pendingLibrary, pendingLists };
  }

  function explainListSyncError(error) {
    if (error?.code === "42501") {
      return new Error(
        "Una lista locale appartiene a un altro account. Esportala e importala nuovamente per crearne una copia con un nuovo ID.",
        { cause: error },
      );
    }
    return error;
  }

  async function pushLibraryRows(client, userId, rows) {
    for (const batch of chunks(rows, LIBRARY_BATCH_SIZE)) {
      assertCurrentUser(userId);
      const payload = batch.map(({ game_key, data, updated_at }) => ({ game_key, data, updated_at }));
      const { error } = await client.rpc("sync_user_library_batch", { p_rows: payload });
      if (error) throw error;
    }
  }

  async function pushListRows(client, userId, rows) {
    for (const batch of chunks(rows, LIST_BATCH_SIZE)) {
      assertCurrentUser(userId);
      const { error } = await client.from("user_lists").upsert(batch, { onConflict: "id" });
      if (error) throw explainListSyncError(error);
    }
  }

  async function push(library, lists, expectedUserId = null) {
    const { client, user } = assertCurrentUser(expectedUserId);
    if (!client || !user) return;
    const userId = user.id;

    if (syncingUserId) {
      if (syncingUserId === userId) return;
      throw new Error("È ancora in corso la sincronizzazione di un altro account.");
    }

    syncingUserId = userId;
    try {
      const now = new Date().toISOString();
      const libraryRows = Object.entries(library || {}).map(([gameKey, entry]) => ({
        game_key: gameKey,
        data: entry,
        updated_at: validTimestamp(entryUpdatedAt(entry), now),
      }));
      const listRows = Object.values(lists || {}).map((list) => ({
        id: list.id,
        user_id: userId,
        name: list.name,
        description: list.description || null,
        visibility: list.visibility || "private",
        game_keys: list.games || [],
        created_at: validTimestamp(list.createdAt, now),
        updated_at: validTimestamp(list.updatedAt, now),
      }));

      if (libraryRows.length) await pushLibraryRows(client, userId, libraryRows);
      if (listRows.length) await pushListRows(client, userId, listRows);

      for (const [gameKey, entry] of Object.entries(library || {})) syncedLibrary[gameKey] = cloneValue(entry);
      for (const [listId, list] of Object.entries(lists || {})) syncedLists[listId] = cloneValue(list);
    } finally {
      if (syncingUserId === userId) syncingUserId = null;
    }
  }

  function cancelScheduledPush() {
    clearTimeout(timer);
    timer = null;
  }

  function schedulePush(library, lists, delay = 900) {
    cancelScheduledPush();
    const { user } = clientAndUser();
    if (!user) return;

    const expectedUserId = user.id;
    const librarySnapshot = cloneValue(library);
    const listsSnapshot = cloneValue(lists);

    timer = setTimeout(() => {
      timer = null;
      const libraryChanges = changedLibraryEntries(librarySnapshot);
      const listChanges = changedLists(listsSnapshot);
      if (!Object.keys(libraryChanges).length && !Object.keys(listChanges).length) return;
      push(libraryChanges, listChanges, expectedUserId).catch((error) => {
        console.error("Sincronizzazione cloud fallita", error);
        window.dispatchEvent(new CustomEvent("tfv:sync-error", { detail: error }));
      });
    }, delay);
  }

  async function deleteLibraryItem(gameKey) {
    const { client, user } = assertCurrentUser();
    if (!client || !user) return;
    const { error } = await client
      .from("user_library")
      .delete()
      .eq("user_id", user.id)
      .eq("game_key", gameKey);
    if (error) throw error;
    delete syncedLibrary[gameKey];
  }

  async function deleteList(listId) {
    const { client, user } = assertCurrentUser();
    if (!client || !user) return;
    const { error } = await client
      .from("user_lists")
      .delete()
      .eq("user_id", user.id)
      .eq("id", listId);
    if (error) throw error;
    delete syncedLists[listId];
  }

  window.VaultCloud = {
    pull,
    push,
    schedulePush,
    cancelScheduledPush,
    deleteLibraryItem,
    deleteList,
  };
})();
