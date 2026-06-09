(() => {
  const config = window.TFV_CONFIG || {};
  const configured = Boolean(config.supabaseUrl && config.supabasePublishableKey);
  const client = configured && window.supabase
    ? window.supabase.createClient(config.supabaseUrl, config.supabasePublishableKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      })
    : null;

  let session = null;
  let profile = null;
  const listeners = new Set();

  function emit() {
    const snapshot = { configured, client, session, user: session?.user || null, profile };
    listeners.forEach((listener) => listener(snapshot));
  }

  async function loadProfile() {
    if (!client || !session?.user) {
      profile = null;
      return null;
    }
    const { data, error } = await client
      .from("profiles")
      .select("id, username, display_name, bio, avatar_url, updated_at")
      .eq("id", session.user.id)
      .maybeSingle();
    if (error) throw error;
    profile = data;
    return data;
  }

  async function initialize() {
    if (!client) {
      emit();
      return { configured: false };
    }
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    session = data.session;
    if (session) await loadProfile();
    emit();

    client.auth.onAuthStateChange(async (_event, nextSession) => {
      session = nextSession;
      try {
        await loadProfile();
      } catch (error) {
        console.error("Caricamento profilo fallito", error);
      }
      emit();
    });
    return { configured: true, session };
  }

  async function signUp({ email, password, username, displayName }) {
    if (!client) throw new Error("Supabase non configurato.");
    const { data, error } = await client.auth.signUp({
      email,
      password,
      options: {
        data: {
          username,
          display_name: displayName || username,
        },
      },
    });
    if (error) throw error;
    return data;
  }

  async function signIn({ email, password }) {
    if (!client) throw new Error("Supabase non configurato.");
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }

  async function signOut() {
    if (!client) return;
    const { error } = await client.auth.signOut();
    if (error) throw error;
  }

  async function updateProfile(patch) {
    if (!client || !session?.user) throw new Error("Utente non autenticato.");
    const payload = {
      id: session.user.id,
      username: patch.username?.trim(),
      display_name: patch.display_name?.trim(),
      bio: patch.bio?.trim() || null,
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await client
      .from("profiles")
      .upsert(payload)
      .select("id, username, display_name, bio, avatar_url, updated_at")
      .single();
    if (error) throw error;
    profile = data;
    emit();
    return data;
  }

  function subscribe(listener) {
    listeners.add(listener);
    listener({ configured, client, session, user: session?.user || null, profile });
    return () => listeners.delete(listener);
  }

  window.VaultAuth = {
    configured,
    client,
    initialize,
    signUp,
    signIn,
    signOut,
    updateProfile,
    subscribe,
    get session() { return session; },
    get user() { return session?.user || null; },
    get profile() { return profile; },
  };
})();
