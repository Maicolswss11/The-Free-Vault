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

  function confirmationRedirectUrl() {
    const url = new URL(window.location.href);
    url.hash = "";
    url.search = "";
    url.searchParams.set("auth", "confirmed");
    return url.toString();
  }

  function hasAuthReturnParameters() {
    const url = new URL(window.location.href);
    return (
      url.searchParams.get("auth") === "confirmed" ||
      url.searchParams.has("code") ||
      /(?:access_token|refresh_token|error_description)=/.test(window.location.hash)
    );
  }

  function clearAuthReturnParameters(destination = "#/profile?confirmed=1") {
    const url = new URL(window.location.href);
    url.search = "";
    url.hash = destination;
    window.history.replaceState({}, "", url.toString());
    window.dispatchEvent(new CustomEvent("tfv:auth-return"));
  }

  async function loadProfile() {
    if (!client || !session?.user) {
      profile = null;
      return null;
    }
    const { data, error } = await client
      .from("profiles")
      .select("id, username, display_name, bio, avatar_url, created_at, updated_at")
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

    const returnedFromConfirmation = hasAuthReturnParameters();
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    session = data.session;
    if (session) await loadProfile();
    emit();

    client.auth.onAuthStateChange(async (_event, nextSession) => {
      session = nextSession;
      try {
        await loadProfile();
      } catch (profileError) {
        console.error("Caricamento profilo fallito", profileError);
      }
      emit();
      if (session && hasAuthReturnParameters()) {
        clearAuthReturnParameters();
      }
    });

    if (returnedFromConfirmation && session) {
      clearAuthReturnParameters();
    }
    return { configured: true, session, returnedFromConfirmation };
  }

  async function signUp({ email, password, username }) {
    if (!client) throw new Error("Supabase non configurato.");
    const { data, error } = await client.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: confirmationRedirectUrl(),
        data: {
          username,
          display_name: username,
        },
      },
    });
    if (error) throw error;
    return data;
  }

  async function resendConfirmation(email) {
    if (!client) throw new Error("Supabase non configurato.");
    const { data, error } = await client.auth.resend({
      type: "signup",
      email,
      options: { emailRedirectTo: confirmationRedirectUrl() },
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
    const username = patch.username?.trim();
    const displayName = patch.display_name?.trim();
    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username || "")) {
      throw new Error("Username: 3–30 caratteri, solo lettere, numeri e underscore.");
    }
    if (!displayName) throw new Error("Inserisci un nome visualizzato.");

    const payload = {
      id: session.user.id,
      username,
      display_name: displayName,
      bio: patch.bio?.trim() || null,
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await client
      .from("profiles")
      .upsert(payload)
      .select("id, username, display_name, bio, avatar_url, created_at, updated_at")
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
    resendConfirmation,
    signIn,
    signOut,
    updateProfile,
    confirmationRedirectUrl,
    subscribe,
    get session() { return session; },
    get user() { return session?.user || null; },
    get profile() { return profile; },
  };
})();
