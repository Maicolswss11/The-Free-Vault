(() => {
  function authState() {
    return {
      client: window.VaultAuth?.client || null,
      user: window.VaultAuth?.user || null,
    };
  }

  async function getConnection() {
    const { client, user } = authState();
    if (!client || !user) return null;
    const { data, error } = await client
      .from("steam_accounts")
      .select("user_id, steam_id, persona_name, profile_url, avatar_url, last_sync_at, created_at, updated_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) throw error;
    return data;
  }

  async function beginLink() {
    const { client, user } = authState();
    if (!client || !user) throw new Error("Accedi prima di collegare Steam.");

    const appBase = `${window.location.origin}${window.location.pathname}`;
    const returnUrl = `${appBase}#/settings/connections?steam=linked`;
    const { data, error } = await client.functions.invoke("steam-auth-start", {
      body: { returnUrl },
    });
    if (error) throw error;
    if (!data?.url) throw new Error("URL di collegamento Steam non ricevuto.");
    window.location.assign(data.url);
  }

  async function syncLibrary() {
    const { client, user } = authState();
    if (!client || !user) throw new Error("Accedi prima di sincronizzare Steam.");
    const { data, error } = await client.functions.invoke("steam-sync-library", {
      body: {},
    });
    if (error) throw error;
    if (!data || !Array.isArray(data.games)) {
      throw new Error("Risposta Steam non valida.");
    }
    window.dispatchEvent(new CustomEvent("tfv:steam-library-import", {
      detail: data,
    }));
    return data;
  }

  async function disconnect() {
    const { client, user } = authState();
    if (!client || !user) throw new Error("Utente non autenticato.");

    const { error: ownedError } = await client
      .from("user_owned_listings")
      .delete()
      .eq("user_id", user.id)
      .eq("store", "steam");
    if (ownedError) throw ownedError;

    const { error } = await client
      .from("steam_accounts")
      .delete()
      .eq("user_id", user.id);
    if (error) throw error;
  }

  async function getOwnedListings() {
    const { client, user } = authState();
    if (!client || !user) return [];
    const { data, error } = await client
      .from("user_owned_listings")
      .select("store, external_id, playtime_minutes, acquired_at, metadata, updated_at")
      .eq("user_id", user.id)
      .eq("store", "steam");
    if (error) throw error;
    return data || [];
  }

  window.VaultSteam = {
    getConnection,
    getOwnedListings,
    beginLink,
    syncLibrary,
    disconnect,
  };
})();
