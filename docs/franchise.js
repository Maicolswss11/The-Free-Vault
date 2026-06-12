(() => {
  function client() {
    return window.VaultAuth?.client || null;
  }

  function requireClient() {
    const db = client();
    if (!db) throw new Error("Supabase non configurato.");
    return db;
  }

  async function rpc(name, args = {}) {
    const { data, error } = await requireClient().rpc(name, args);
    if (error) throw error;
    return data;
  }

  async function getDirectory() {
    return rpc("editorial_directory");
  }

  async function getFranchise(slug) {
    return rpc("franchise_detail", { p_slug: String(slug || "").trim() });
  }

  async function getCollection(slug) {
    return rpc("editorial_collection_detail", { p_slug: String(slug || "").trim() });
  }

  async function getMemberships(gameKey) {
    return rpc("catalog_editorial_memberships", { p_key: String(gameKey || "").trim() });
  }

  async function listAdminFranchises() {
    return rpc("admin_list_franchises");
  }

  async function getAdminFranchise(id) {
    return rpc("admin_get_franchise", { p_id: id });
  }

  async function saveAdminFranchise(payload = {}) {
    return rpc("admin_save_franchise", {
      p_id: payload.id || null,
      p_slug: payload.slug || "",
      p_name: payload.name || "",
      p_description: payload.description || null,
      p_hero_image_url: payload.heroImageUrl || null,
      p_status: payload.status || "draft",
    });
  }

  async function deleteAdminFranchise(id) {
    return rpc("admin_delete_franchise", { p_id: id });
  }

  async function saveAdminFranchiseGame(franchiseId, payload = {}) {
    return rpc("admin_save_franchise_game", {
      p_franchise_id: franchiseId,
      p_game_key: payload.gameKey || "",
      p_relation_type: payload.relationType || "main",
      p_release_order: Number(payload.releaseOrder || 0),
      p_narrative_order: payload.narrativeOrder === null || payload.narrativeOrder === ""
        ? null
        : Number(payload.narrativeOrder),
      p_note: payload.note || null,
    });
  }

  async function saveAdminFranchiseGames(franchiseId, games = []) {
    const payload = (games || []).map((game) => ({
      game_key: game.gameKey || "",
      relation_type: game.relationType || "main",
      release_order: Number(game.releaseOrder || 0),
      narrative_order: game.narrativeOrder === null || game.narrativeOrder === ""
        ? null
        : Number(game.narrativeOrder),
      note: game.note || null,
    }));
    return rpc("admin_save_franchise_games_batch", {
      p_franchise_id: franchiseId,
      p_games: payload,
    });
  }

  async function removeAdminFranchiseGame(franchiseId, gameKey) {
    return rpc("admin_remove_franchise_game", {
      p_franchise_id: franchiseId,
      p_game_key: gameKey,
    });
  }

  async function enrichCatalogGames(gameKeys = []) {
    const keys = [...new Set((gameKeys || []).map((key) => String(key || "").trim()).filter(Boolean))].slice(0, 100);
    if (!keys.length) throw new Error("Nessun gioco da arricchire.");
    const { data, error } = await requireClient().functions.invoke("admin-enrich-catalog-games", {
      body: { game_keys: keys },
    });
    if (error) throw error;
    if (data?.error) throw new Error(data.error);
    return data || {};
  }

  async function listAdminCollections() {
    return rpc("admin_list_editorial_collections");
  }

  async function getAdminCollection(id) {
    return rpc("admin_get_editorial_collection", { p_id: id });
  }

  async function saveAdminCollection(payload = {}) {
    return rpc("admin_save_editorial_collection", {
      p_id: payload.id || null,
      p_slug: payload.slug || "",
      p_title: payload.title || "",
      p_description: payload.description || null,
      p_cover_image_url: payload.coverImageUrl || null,
      p_curator_note: payload.curatorNote || null,
      p_status: payload.status || "draft",
    });
  }

  async function deleteAdminCollection(id) {
    return rpc("admin_delete_editorial_collection", { p_id: id });
  }

  async function saveAdminCollectionGame(collectionId, payload = {}) {
    return rpc("admin_save_editorial_collection_game", {
      p_collection_id: collectionId,
      p_game_key: payload.gameKey || "",
      p_position: Number(payload.position || 0),
      p_editorial_note: payload.editorialNote || null,
    });
  }

  async function removeAdminCollectionGame(collectionId, gameKey) {
    return rpc("admin_remove_editorial_collection_game", {
      p_collection_id: collectionId,
      p_game_key: gameKey,
    });
  }

  window.VaultFranchises = {
    getDirectory,
    getFranchise,
    getCollection,
    getMemberships,
    listAdminFranchises,
    getAdminFranchise,
    saveAdminFranchise,
    deleteAdminFranchise,
    saveAdminFranchiseGame,
    saveAdminFranchiseGames,
    enrichCatalogGames,
    removeAdminFranchiseGame,
    listAdminCollections,
    getAdminCollection,
    saveAdminCollection,
    deleteAdminCollection,
    saveAdminCollectionGame,
    removeAdminCollectionGame,
  };
})();
