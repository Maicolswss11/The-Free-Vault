(() => {
  function client() {
    return window.VaultAuth?.client || null;
  }

  function requireClient() {
    const db = client();
    if (!db) throw new Error("Supabase non configurato.");
    return db;
  }

  function requireUser() {
    const user = window.VaultAuth?.user;
    if (!user) throw new Error("Accedi per aprire gli strumenti amministrativi.");
    return user;
  }

  async function rpc(name, args = {}) {
    requireUser();
    const { data, error } = await requireClient().rpc(name, args);
    if (error) throw error;
    return data;
  }

  async function getContext() {
    if (!window.VaultAuth?.user || !client()) {
      return { role: null, is_admin: false, can_moderate: false };
    }
    const data = await rpc("admin_context");
    return {
      role: data?.role || null,
      is_admin: Boolean(data?.is_admin),
      can_moderate: Boolean(data?.can_moderate),
    };
  }

  async function getCatalogRecord(key) {
    return rpc("admin_get_catalog_record", { p_key: String(key || "").trim() });
  }

  async function saveCatalogOverride(matchKey, patch, lockedFields) {
    return rpc("admin_save_catalog_override", {
      p_match_key: matchKey,
      p_patch: patch || {},
      p_locked_fields: Array.isArray(lockedFields) ? lockedFields : [],
    });
  }

  async function clearCatalogOverride(matchKey) {
    return rpc("admin_clear_catalog_override", { p_match_key: matchKey });
  }

  async function listMatches({ status = "pending", limit = 50, offset = 0 } = {}) {
    return rpc("admin_list_match_queue", {
      p_status: status,
      p_limit: limit,
      p_offset: offset,
    });
  }

  async function reviewMatch(id, status, { resolvedGameId = null, note = null } = {}) {
    return rpc("admin_review_match", {
      p_id: id,
      p_status: status,
      p_resolved_game_id: resolvedGameId || null,
      p_note: note || null,
    });
  }

  async function listReports({ status = "open", limit = 50, offset = 0 } = {}) {
    return rpc("admin_list_reports", {
      p_status: status,
      p_limit: limit,
      p_offset: offset,
    });
  }

  async function resolveReport(id, action, note = null) {
    return rpc("admin_resolve_report", {
      p_report_id: id,
      p_action: action,
      p_note: note || null,
    });
  }

  async function getSystemStatus() {
    return rpc("admin_system_status");
  }

  window.VaultAdmin = {
    getContext,
    getCatalogRecord,
    saveCatalogOverride,
    clearCatalogOverride,
    listMatches,
    reviewMatch,
    listReports,
    resolveReport,
    getSystemStatus,
  };
})();
