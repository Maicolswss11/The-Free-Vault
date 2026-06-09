(() => {
  let timer = null;
  let syncing = false;

  function clientAndUser() {
    const auth = window.VaultAuth;
    return { client: auth?.client, user: auth?.user };
  }

  function entryUpdatedAt(entry) {
    return entry?.updatedAt || entry?.updated_at || entry?.addedAt || new Date(0).toISOString();
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

  async function pull(localLibrary, localLists) {
    const { client, user } = clientAndUser();
    if (!client || !user) return { library: localLibrary, lists: localLists };

    const [libraryResult, listsResult] = await Promise.all([
      client.from("user_library").select("game_key, data, updated_at").eq("user_id", user.id),
      client.from("user_lists").select("id, name, description, visibility, game_keys, created_at, updated_at").eq("user_id", user.id),
    ]);
    if (libraryResult.error) throw libraryResult.error;
    if (listsResult.error) throw listsResult.error;

    return {
      library: mergeLibrary(localLibrary, libraryResult.data),
      lists: mergeLists(localLists, listsResult.data),
    };
  }

  async function push(library, lists) {
    const { client, user } = clientAndUser();
    if (!client || !user || syncing) return;
    syncing = true;
    try {
      const now = new Date().toISOString();
      const libraryRows = Object.entries(library).map(([gameKey, entry]) => ({
        user_id: user.id,
        game_key: gameKey,
        data: entry,
        updated_at: entryUpdatedAt(entry) > now ? entryUpdatedAt(entry) : now,
      }));
      const listRows = Object.values(lists).map((list) => ({
        id: list.id,
        user_id: user.id,
        name: list.name,
        description: list.description || null,
        visibility: list.visibility || "private",
        game_keys: list.games || [],
        created_at: list.createdAt || now,
        updated_at: list.updatedAt || now,
      }));

      if (libraryRows.length) {
        const { error } = await client.from("user_library").upsert(libraryRows, {
          onConflict: "user_id,game_key",
        });
        if (error) throw error;
      }
      if (listRows.length) {
        const { error } = await client.from("user_lists").upsert(listRows, {
          onConflict: "id",
        });
        if (error) throw error;
      }
    } finally {
      syncing = false;
    }
  }

  function schedulePush(library, lists, delay = 900) {
    clearTimeout(timer);
    timer = setTimeout(() => {
      push(library, lists).catch((error) => {
        console.error("Sincronizzazione cloud fallita", error);
        window.dispatchEvent(new CustomEvent("tfv:sync-error", { detail: error }));
      });
    }, delay);
  }

  async function deleteLibraryItem(gameKey) {
    const { client, user } = clientAndUser();
    if (!client || !user) return;
    const { error } = await client
      .from("user_library")
      .delete()
      .eq("user_id", user.id)
      .eq("game_key", gameKey);
    if (error) throw error;
  }

  async function deleteList(listId) {
    const { client, user } = clientAndUser();
    if (!client || !user) return;
    const { error } = await client
      .from("user_lists")
      .delete()
      .eq("user_id", user.id)
      .eq("id", listId);
    if (error) throw error;
  }

  window.VaultCloud = { pull, push, schedulePush, deleteLibraryItem, deleteList };
})();
