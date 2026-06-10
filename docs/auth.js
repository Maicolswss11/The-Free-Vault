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

  const DEFAULT_SETTINGS = Object.freeze({
    show_library: true,
    show_lists: true,
    show_activity: true,
    show_diary: true,
    email_notifications: true,
  });

  let session = null;
  let profile = null;
  let settings = { ...DEFAULT_SETTINGS };
  let recoveryMode = false;
  const listeners = new Set();

  function snapshot() {
    return {
      configured,
      client,
      session,
      user: session?.user || null,
      profile,
      settings,
      recoveryMode,
    };
  }

  function emit() {
    const value = snapshot();
    listeners.forEach((listener) => listener(value));
  }

  function baseRedirectUrl(flag, hash = '') {
    const url = new URL(window.location.href);
    url.hash = hash;
    url.search = '';
    if (flag) url.searchParams.set('auth', flag);
    return url.toString();
  }

  function confirmationRedirectUrl() {
    const url = new URL(window.location.href);
    url.hash = "";
    url.search = "";
    url.searchParams.set("auth", "confirmed");
    return url.toString();
  }

  function passwordRecoveryRedirectUrl() {
    return baseRedirectUrl('recovery');
  }

  function authReturnKind() {
    const url = new URL(window.location.href);
    const hash = window.location.hash;
    if (url.searchParams.get('auth') === 'recovery' || /type=recovery/.test(hash)) {
      return 'recovery';
    }
    if (
      url.searchParams.get('auth') === 'confirmed' ||
      url.searchParams.has('code') ||
      /(?:access_token|refresh_token|error_description)=/.test(hash)
    ) {
      return 'confirmation';
    }
    return null;
  }

  function clearAuthReturnParameters(destination) {
    const url = new URL(window.location.href);
    url.search = '';
    url.hash = destination;
    window.history.replaceState({}, '', url.toString());
    window.dispatchEvent(new CustomEvent('tfv:auth-return'));
  }

  async function loadProfile() {
    if (!client || !session?.user) {
      profile = null;
      settings = { ...DEFAULT_SETTINGS };
      return null;
    }

    const [profileResult, settingsResult] = await Promise.all([
      client
        .from('profiles')
        .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
        .eq('id', session.user.id)
        .maybeSingle(),
      client
        .from('user_settings')
        .select('show_library, show_lists, show_activity, show_diary, email_notifications, updated_at')
        .eq('user_id', session.user.id)
        .maybeSingle(),
    ]);

    if (profileResult.error) throw profileResult.error;
    if (settingsResult.error && settingsResult.error.code !== 'PGRST116') {
      throw settingsResult.error;
    }

    profile = profileResult.data;
    settings = { ...DEFAULT_SETTINGS, ...(settingsResult.data || {}) };
    return profile;
  }

  async function initialize() {
    if (!client) {
      emit();
      return { configured: false };
    }

    const returnKind = authReturnKind();
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    session = data.session;
    recoveryMode = returnKind === 'recovery';
    if (session) await loadProfile();
    emit();

    client.auth.onAuthStateChange((event, nextSession) => {
      window.setTimeout(async () => {
        session = nextSession;
        recoveryMode = event === 'PASSWORD_RECOVERY' || recoveryMode;
        try {
          await loadProfile();
        } catch (profileError) {
          console.error('Caricamento profilo fallito', profileError);
        }
        emit();

        if (event === 'PASSWORD_RECOVERY') {
          clearAuthReturnParameters('#/reset-password');
          window.dispatchEvent(new CustomEvent('tfv:password-recovery'));
        } else if (session && authReturnKind() === 'confirmation') {
          clearAuthReturnParameters('#/profile?confirmed=1');
        }
      }, 0);
    });

    if (returnKind === 'recovery' && session) {
      clearAuthReturnParameters('#/reset-password');
    } else if (returnKind === 'confirmation' && session) {
      clearAuthReturnParameters('#/profile?confirmed=1');
    }

    return { configured: true, session, returnKind };
  }

  async function signUp({ email, password, username }) {
    if (!client) throw new Error('Supabase non configurato.');
    const { data, error } = await client.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: confirmationRedirectUrl(),
        data: { username, display_name: username },
      },
    });
    if (error) throw error;
    return data;
  }

  async function resendConfirmation(email) {
    if (!client) throw new Error('Supabase non configurato.');
    const { data, error } = await client.auth.resend({
      type: 'signup',
      email,
      options: { emailRedirectTo: confirmationRedirectUrl() },
    });
    if (error) throw error;
    return data;
  }

  async function signIn({ email, password }) {
    if (!client) throw new Error('Supabase non configurato.');
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }

  async function signOut() {
    if (!client) return;
    const { error } = await client.auth.signOut();
    if (error) throw error;
  }

  async function requestPasswordReset(email) {
    if (!client) throw new Error('Supabase non configurato.');
    const { data, error } = await client.auth.resetPasswordForEmail(email, {
      redirectTo: passwordRecoveryRedirectUrl(),
    });
    if (error) throw error;
    return data;
  }

  async function updatePassword(password) {
    if (!client || !session?.user) throw new Error('Sessione di recupero non valida o scaduta.');
    if (password.length < 8) throw new Error('La password deve contenere almeno 8 caratteri.');
    const { data, error } = await client.auth.updateUser({ password });
    if (error) throw error;
    recoveryMode = false;
    emit();
    return data;
  }

  async function updateEmail(email) {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    const normalized = email.trim().toLowerCase();
    if (!normalized) throw new Error('Inserisci un indirizzo email valido.');
    const { data, error } = await client.auth.updateUser({ email: normalized });
    if (error) throw error;
    return data;
  }

  async function updateProfile(patch) {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    const username = patch.username?.trim();
    const displayName = patch.display_name?.trim();
    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username || '')) {
      throw new Error('Username: 3–30 caratteri, solo lettere, numeri e underscore.');
    }
    if (!displayName) throw new Error('Inserisci un nome visualizzato.');

    const payload = {
      id: session.user.id,
      username,
      display_name: displayName,
      bio: patch.bio?.trim() || null,
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await client
      .from('profiles')
      .upsert(payload)
      .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
      .single();
    if (error) {
      if (error.code === '23505') throw new Error('Questo username è già utilizzato.');
      throw error;
    }
    profile = data;
    emit();
    return data;
  }

  async function updatePrivacy(patch) {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    const nextSettings = { ...settings, ...patch };

    const [profileResult, settingsResult] = await Promise.all([
      client
        .from('profiles')
        .update({ is_public: Boolean(patch.is_public), updated_at: new Date().toISOString() })
        .eq('id', session.user.id)
        .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
        .single(),
      client
        .from('user_settings')
        .upsert({
          user_id: session.user.id,
          show_library: Boolean(nextSettings.show_library),
          show_lists: Boolean(nextSettings.show_lists),
          show_activity: Boolean(nextSettings.show_activity),
          show_diary: Boolean(nextSettings.show_diary),
          email_notifications: Boolean(nextSettings.email_notifications),
          updated_at: new Date().toISOString(),
        })
        .select('show_library, show_lists, show_activity, show_diary, email_notifications, updated_at')
        .single(),
    ]);

    if (profileResult.error) throw profileResult.error;
    if (settingsResult.error) throw settingsResult.error;
    profile = profileResult.data;
    settings = { ...DEFAULT_SETTINGS, ...settingsResult.data };
    emit();
    return { profile, settings };
  }

  async function uploadAvatar(file) {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    if (!(file instanceof File) || !file.type.startsWith('image/')) {
      throw new Error('Seleziona un’immagine PNG, JPG o WebP.');
    }
    if (file.size > 2 * 1024 * 1024) throw new Error('L’immagine non può superare 2 MB.');

    const mimeExtensions = {
      'image/png': 'png',
      'image/jpeg': 'jpg',
      'image/webp': 'webp',
    };
    const extension = mimeExtensions[file.type];
    if (!extension) throw new Error('Formato non supportato. Usa PNG, JPG o WebP.');

    const folder = session.user.id;
    const storage = client.storage.from('avatars');
    const { data: existing } = await storage.list(folder, { limit: 20 });
    if (existing?.length) {
      await storage.remove(existing.map((item) => `${folder}/${item.name}`));
    }

    const path = `${folder}/avatar-${Date.now()}.${extension}`;
    const { error: uploadError } = await storage.upload(path, file, {
      cacheControl: '3600',
      contentType: file.type,
      upsert: false,
    });
    if (uploadError) throw uploadError;

    const { data: publicData } = storage.getPublicUrl(path);
    const avatarUrl = `${publicData.publicUrl}?v=${Date.now()}`;
    const { data, error } = await client
      .from('profiles')
      .update({ avatar_url: avatarUrl, updated_at: new Date().toISOString() })
      .eq('id', session.user.id)
      .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
      .single();
    if (error) throw error;
    profile = data;
    emit();
    return data;
  }

  async function removeAvatar() {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    const folder = session.user.id;
    const storage = client.storage.from('avatars');
    const { data: existing, error: listError } = await storage.list(folder, { limit: 20 });
    if (listError) throw listError;
    if (existing?.length) {
      const { error: removeError } = await storage.remove(existing.map((item) => `${folder}/${item.name}`));
      if (removeError) throw removeError;
    }
    const { data, error } = await client
      .from('profiles')
      .update({ avatar_url: null, updated_at: new Date().toISOString() })
      .eq('id', session.user.id)
      .select('id, username, display_name, bio, avatar_url, is_public, created_at, updated_at')
      .single();
    if (error) throw error;
    profile = data;
    emit();
    return data;
  }

  async function deleteAccount() {
    if (!client || !session?.user) throw new Error('Utente non autenticato.');
    const { data, error } = await client.functions.invoke('delete-account', {
      body: { confirmation: 'DELETE' },
    });
    if (error) throw error;
    session = null;
    profile = null;
    settings = { ...DEFAULT_SETTINGS };
    emit();
    return data;
  }

  function subscribe(listener) {
    listeners.add(listener);
    listener(snapshot());
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
    requestPasswordReset,
    updatePassword,
    updateEmail,
    updateProfile,
    updatePrivacy,
    uploadAvatar,
    removeAvatar,
    deleteAccount,
    confirmationRedirectUrl,
    passwordRecoveryRedirectUrl,
    subscribe,
    get session() { return session; },
    get user() { return session?.user || null; },
    get profile() { return profile; },
    get settings() { return settings; },
    get recoveryMode() { return recoveryMode; },
  };
})();
