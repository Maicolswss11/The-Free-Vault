const DATA_URL = "./games.json";
const HISTORY_URL = "./history.json";
const PLACEHOLDER = "./placeholders/game-placeholder.svg";

const GUEST_LIBRARY_KEY = "tfv:guest:library:v1";
const GUEST_LISTS_KEY = "tfv:guest:lists:v1";
const USER_STORAGE_PREFIX = "tfv:user:";
const LEGACY_LIBRARY_KEYS = [
  "the-free-vault-library-v3",
  "the-free-vault-library-v2",
];
const LEGACY_LIST_KEYS = ["the-free-vault-lists-v1"];

let activeStorageUserId = null;
let personalStorageGeneration = 0;
let synchronizedAccountId = null;

const state = {
  current: [],
  upcoming: [],
  history: [],
  catalog: [],
  catalogMeta: null,
  gameIndex: new Map(),
  catalogTotal: 0,
  catalogOffset: 0,
  catalogLimit: 36,
  catalogLoading: false,
  catalogHasMore: false,
  catalogRequestId: 0,
  globalSearchRequestId: 0,
  discoveryData: null,
  discoveryLoading: false,
  discoveryRecommendations: null,
  entityData: null,
  entityLoading: false,
  entityRequestId: 0,
  editorialDirectory: null,
  franchiseData: null,
  franchiseOrder: "release",
  collectionData: null,
  editorialRequestId: 0,
  library: loadLibrary(null),
  lists: loadLists(null),
  route: { name: "home", params: {}, query: new URLSearchParams() },
  search: "",
  globalSearch: "",
  statusFilter: "all",
  storeFilter: "all",
  categoryFilter: "all",
  segmentFilter: "all",
  priceFilter: "all",
  yearFilter: "all",
  sort: "relevance",
  pendingListGame: null,
  auth: { configured: false, user: null, profile: null },
  social: {
    gameReviews: [],
    myReview: null,
    publicProfile: null,
    publicProfileContent: null,
    sharedList: null,
    feed: [],
    feedFollowingOnly: true,
    notifications: [],
    unreadNotifications: 0,
    exploreUsers: [],
  },
  admin: {
    loaded: false,
    context: { role: null, is_admin: false, can_moderate: false },
    selectedCatalog: null,
    matches: [],
    reports: [],
    system: null,
    franchises: [],
    collections: [],
    selectedFranchise: null,
    selectedCollection: null,
    franchiseSearchResults: [],
    franchiseGameSelection: [],
    requestId: 0,
  },
  dataLoaded: false,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const ui = {
  sidebar: $("#app-sidebar"),
  menuButton: $("#menu-button"),
  sidebarClose: $("#sidebar-close"),
  sidebarBackdrop: $("#sidebar-backdrop"),
  filterBackdrop: $("#filter-backdrop"),
  mobileFilterToggle: $("#mobile-filter-toggle"),
  mobileFilterCount: $("#mobile-filter-count"),
  mobileFilterClose: $("#mobile-filter-close"),
  mobileFilterApply: $("#mobile-filter-apply"),
  dashboardPage: $("#dashboard-page"),
  gamePage: $("#game-page"),
  authPage: $("#auth-page"),
  profilePage: $("#profile-page"),
  publicProfilePage: $("#public-profile-page"),
  sharedListPage: $("#shared-list-page"),
  settingsPage: $("#settings-page"),
  feedPage: $("#feed-page"),
  explorePage: $("#explore-page"),
  notificationsPage: $("#notifications-page"),
  diaryPage: $("#diary-page"),
  statsPage: $("#stats-page"),
  discoveryPage: $("#discovery-page"),
  entityPage: $("#entity-page"),
  discoveryStatus: $("#discovery-status"),
  discoverySections: $("#discovery-sections"),
  entityKind: $("#entity-kind"),
  entityTitle: $("#entity-title"),
  entityMeta: $("#entity-meta"),
  entityStatus: $("#entity-status"),
  entityGames: $("#entity-games"),
  entityPagination: $("#entity-pagination"),
  entityPageSummary: $("#entity-page-summary"),
  entityLoadMore: $("#entity-load-more"),
  editorialDirectoryPage: $("#editorial-directory-page"),
  editorialDirectoryStatus: $("#editorial-directory-status"),
  franchiseDirectoryGrid: $("#franchise-directory-grid"),
  collectionDirectoryGrid: $("#collection-directory-grid"),
  franchisePage: $("#franchise-page"),
  franchiseHero: $("#franchise-hero"),
  franchiseHeroImage: $("#franchise-hero-image"),
  franchiseTitle: $("#franchise-title"),
  franchiseDescription: $("#franchise-description"),
  franchiseMeta: $("#franchise-meta"),
  franchiseStatus: $("#franchise-status"),
  franchiseProgress: $("#franchise-progress"),
  franchiseProgressCompleted: $("#franchise-progress-completed"),
  franchiseProgressStarted: $("#franchise-progress-started"),
  franchiseProgressPercent: $("#franchise-progress-percent"),
  franchiseProgressFill: $("#franchise-progress-fill"),
  franchiseSections: $("#franchise-sections"),
  editorialCollectionPage: $("#editorial-collection-page"),
  editorialCollectionHero: $("#editorial-collection-hero"),
  editorialCollectionImage: $("#editorial-collection-image"),
  editorialCollectionTitle: $("#editorial-collection-title"),
  editorialCollectionDescription: $("#editorial-collection-description"),
  editorialCollectionCuratorNote: $("#editorial-collection-curator-note"),
  editorialCollectionMeta: $("#editorial-collection-meta"),
  editorialCollectionStatus: $("#editorial-collection-status"),
  editorialCollectionGames: $("#editorial-collection-games"),
  gameEditorialMemberships: $("#game-editorial-memberships"),
  gameEditorialMembershipLinks: $("#game-editorial-membership-links"),
  adminPage: $("#admin-page"),
  adminNavSection: $("#admin-nav-section"),
  adminRoleBadge: $("#admin-role-badge"),
  adminAccessRequired: $("#admin-access-required"),
  adminContent: $("#admin-content"),
  adminCatalogPanel: $("#admin-panel-catalog"),
  adminEditorialPanel: $("#admin-panel-editorial"),
  adminMatchingPanel: $("#admin-panel-matching"),
  adminModerationPanel: $("#admin-panel-moderation"),
  adminSystemPanel: $("#admin-panel-system"),
  adminCatalogSearchForm: $("#admin-catalog-search-form"),
  adminCatalogSearch: $("#admin-catalog-search"),
  adminCatalogResults: $("#admin-catalog-results"),
  adminCatalogEditor: $("#admin-catalog-editor"),
  adminCatalogTitle: $("#admin-catalog-title"),
  adminCatalogKey: $("#admin-catalog-key"),
  adminCatalogOpen: $("#admin-catalog-open"),
  adminCatalogListings: $("#admin-catalog-listings"),
  adminOverrideForm: $("#admin-override-form"),
  adminOverrideMessage: $("#admin-override-message"),
  adminClearOverride: $("#admin-clear-override"),
  adminMatchStatus: $("#admin-match-status"),
  adminMatchRefresh: $("#admin-match-refresh"),
  adminMatchList: $("#admin-match-list"),
  adminReportStatus: $("#admin-report-status"),
  adminReportRefresh: $("#admin-report-refresh"),
  adminReportList: $("#admin-report-list"),
  adminSystemRefresh: $("#admin-system-refresh"),
  adminSystemStats: $("#admin-system-stats"),
  adminSyncList: $("#admin-sync-list"),
  adminEditorialRefresh: $("#admin-editorial-refresh"),
  adminFranchiseList: $("#admin-franchise-list"),
  adminFranchiseNew: $("#admin-franchise-new"),
  adminFranchiseForm: $("#admin-franchise-form"),
  adminFranchiseId: $("#admin-franchise-id"),
  adminFranchiseName: $("#admin-franchise-name"),
  adminFranchiseSlug: $("#admin-franchise-slug"),
  adminFranchiseStatus: $("#admin-franchise-status"),
  adminFranchiseImage: $("#admin-franchise-image"),
  adminFranchiseDescription: $("#admin-franchise-description"),
  adminFranchiseMessage: $("#admin-franchise-message"),
  adminFranchiseDelete: $("#admin-franchise-delete"),
  adminFranchiseGamesEditor: $("#admin-franchise-games-editor"),
  adminFranchiseOpen: $("#admin-franchise-open"),
  adminFranchiseGameSearchForm: $("#admin-franchise-game-search-form"),
  adminFranchiseGameSearch: $("#admin-franchise-game-search"),
  adminFranchiseSearchActions: $("#admin-franchise-search-actions"),
  adminFranchiseSelectAll: $("#admin-franchise-select-all"),
  adminFranchiseDeselectResults: $("#admin-franchise-deselect-results"),
  adminFranchiseGameSearchResults: $("#admin-franchise-game-search-results"),
  adminFranchiseBatchToolbar: $("#admin-franchise-batch-toolbar"),
  adminFranchiseBatchSummary: $("#admin-franchise-batch-summary"),
  adminFranchiseSortRelease: $("#admin-franchise-sort-release"),
  adminFranchiseBatchClear: $("#admin-franchise-batch-clear"),
  adminFranchiseSelectedList: $("#admin-franchise-selected-list"),
  adminFranchiseGameForm: $("#admin-franchise-game-form"),
  adminFranchiseGameKey: $("#admin-franchise-game-key"),
  adminFranchiseGameSelected: $("#admin-franchise-game-selected"),
  adminFranchiseGameType: $("#admin-franchise-game-type"),
  adminFranchiseReleaseOrder: $("#admin-franchise-release-order"),
  adminFranchiseNarrativeOrder: $("#admin-franchise-narrative-order"),
  adminFranchiseGameNote: $("#admin-franchise-game-note"),
  adminFranchiseGameSubmit: $("#admin-franchise-game-submit"),
  adminFranchiseGames: $("#admin-franchise-games"),
  adminCollectionList: $("#admin-collection-list"),
  adminCollectionNew: $("#admin-collection-new"),
  adminCollectionForm: $("#admin-collection-form"),
  adminCollectionId: $("#admin-collection-id"),
  adminCollectionTitle: $("#admin-collection-title"),
  adminCollectionSlug: $("#admin-collection-slug"),
  adminCollectionStatus: $("#admin-collection-status"),
  adminCollectionImage: $("#admin-collection-image"),
  adminCollectionDescription: $("#admin-collection-description"),
  adminCollectionCuratorNote: $("#admin-collection-curator-note"),
  adminCollectionMessage: $("#admin-collection-message"),
  adminCollectionDelete: $("#admin-collection-delete"),
  adminCollectionGamesEditor: $("#admin-collection-games-editor"),
  adminCollectionOpen: $("#admin-collection-open"),
  adminCollectionGameSearchForm: $("#admin-collection-game-search-form"),
  adminCollectionGameSearch: $("#admin-collection-game-search"),
  adminCollectionGameSearchResults: $("#admin-collection-game-search-results"),
  adminCollectionGameForm: $("#admin-collection-game-form"),
  adminCollectionGameKey: $("#admin-collection-game-key"),
  adminCollectionGameSelected: $("#admin-collection-game-selected"),
  adminCollectionPosition: $("#admin-collection-position"),
  adminCollectionGameNote: $("#admin-collection-game-note"),
  adminCollectionGames: $("#admin-collection-games"),
  sharedListReport: $("#shared-list-report"),
  grid: $("#games-grid"),
  template: $("#game-card-template"),
  search: $("#search-input"),
  globalSearchResults: $("#global-search-results"),
  toolbarControls: $("#toolbar-controls"),
  filter: $("#status-filter"),
  storeFilter: $("#store-filter"),
  categoryFilter: $("#category-filter"),
  segmentFilter: $("#segment-filter"),
  priceFilter: $("#price-filter"),
  yearFilter: $("#year-filter"),
  sort: $("#sort-select"),
  refresh: $("#refresh-button"),
  status: $("#status-message"),
  title: $("#view-title"),
  eyebrow: $("#view-eyebrow"),
  hero: $("#hero"),
  heroImage: $("#hero-image"),
  heroTitle: $("#hero-title"),
  heroDescription: $("#hero-description"),
  heroPrice: $("#hero-price"),
  heroCountdown: $("#hero-countdown"),
  heroLink: $("#hero-link"),
  heroLibrary: $("#hero-library"),
  heroDetails: $("#hero-details"),
  sidebarUpdate: $("#sidebar-update"),
  sidebarDataNote: $("#sidebar-data-note"),
  install: $("#install-button"),
  exportLibrary: $("#export-library"),
  importLibrary: $("#import-library"),
  importLibraryFile: $("#import-library-file"),
  toast: $("#toast"),
  statCatalog: $("#stat-catalog"),
  statLists: $("#stat-lists"),
  listsDashboard: $("#lists-dashboard"),
  listsGrid: $("#lists-grid"),
  createListButton: $("#create-list-button"),
  catalogMeta: $("#catalog-meta"),
  catalogPagination: $("#catalog-pagination"),
  catalogPageSummary: $("#catalog-page-summary"),
  catalogLoadMore: $("#catalog-load-more"),
  toolbar: $("#content-toolbar"),
  listDialog: $("#list-dialog"),
  listDialogTitle: $("#list-dialog-title"),
  listName: $("#list-name-input"),
  listDescription: $("#list-description-input"),
  listVisibility: $("#list-visibility-input"),
  saveList: $("#save-list-button"),
  listPicker: $("#list-picker-dialog"),
  listPickerItems: $("#list-picker-items"),
  accountButton: $("#account-button"),
  accountAvatar: $("#account-avatar"),
  accountLabel: $("#account-label"),
  authEyebrow: $("#auth-page-eyebrow"),
  authTitle: $("#auth-page-title"),
  authSubtitle: $("#auth-page-subtitle"),
  authConfigWarning: $("#auth-config-warning"),
  loginForm: $("#login-form"),
  loginEmail: $("#login-email"),
  loginPassword: $("#login-password"),
  loginError: $("#login-error"),
  loginSubmit: $("#login-submit"),
  registerForm: $("#register-form"),
  registerUsername: $("#register-username"),
  registerEmail: $("#register-email"),
  registerPassword: $("#register-password"),
  registerPasswordConfirm: $("#register-password-confirm"),
  registerError: $("#register-error"),
  registerSubmit: $("#register-submit"),
  authConfirmation: $("#auth-confirmation-message"),
  forgotPasswordForm: $("#forgot-password-form"),
  forgotPasswordEmail: $("#forgot-password-email"),
  forgotPasswordError: $("#forgot-password-error"),
  forgotPasswordSuccess: $("#forgot-password-success"),
  forgotPasswordSubmit: $("#forgot-password-submit"),
  resetPasswordForm: $("#reset-password-form"),
  resetPasswordValue: $("#reset-password-value"),
  resetPasswordConfirm: $("#reset-password-confirm"),
  resetPasswordError: $("#reset-password-error"),
  resetPasswordSubmit: $("#reset-password-submit"),
  profileSignedOut: $("#profile-signed-out"),
  profileSignedIn: $("#profile-signed-in"),
  profilePageAvatar: $("#profile-page-avatar"),
  profilePageName: $("#profile-page-name"),
  profilePageHandle: $("#profile-page-handle"),
  profilePageBio: $("#profile-page-bio"),
  profilePageEmail: $("#profile-page-email"),
  profileForm: $("#profile-form"),
  profileUsername: $("#profile-username"),
  profileDisplayName: $("#profile-display-name"),
  profileBio: $("#profile-bio"),
  profileError: $("#profile-error"),
  profileRecentGames: $("#profile-recent-games"),
  profileVisibilityBadge: $("#profile-visibility-badge"),
  settingsSignedOut: $("#settings-signed-out"),
  settingsSignedIn: $("#settings-signed-in"),
  settingsAvatarPreview: $("#settings-avatar-preview"),
  avatarFile: $("#avatar-file"),
  avatarUploadButton: $("#avatar-upload-button"),
  avatarRemoveButton: $("#avatar-remove-button"),
  changeEmailForm: $("#change-email-form"),
  changeEmailValue: $("#change-email-value"),
  changeEmailMessage: $("#change-email-message"),
  changePasswordForm: $("#change-password-form"),
  changePasswordValue: $("#change-password-value"),
  changePasswordConfirm: $("#change-password-confirm"),
  changePasswordMessage: $("#change-password-message"),
  privacyForm: $("#privacy-form"),
  privacyPublic: $("#privacy-public"),
  privacyLibrary: $("#privacy-library"),
  privacyLists: $("#privacy-lists"),
  privacyActivity: $("#privacy-activity"),
  privacyDiary: $("#privacy-diary"),
  privacyEmails: $("#privacy-emails"),
  privacyMessage: $("#privacy-message"),
  settingsExportData: $("#settings-export-data"),
  settingsImportData: $("#settings-import-data"),
  deleteAccountConfirmation: $("#delete-account-confirmation"),
  deleteAccountMessage: $("#delete-account-message"),
  deleteAccountButton: $("#delete-account-button"),
  cloudStatus: $("#cloud-status"),
  steamConnectionCard: $("#steam-connection-card"),
  steamConnectionStatus: $("#steam-connection-status"),
  steamConnectionAvatar: $("#steam-connection-avatar"),
  steamConnectionName: $("#steam-connection-name"),
  steamConnectionId: $("#steam-connection-id"),
  steamConnectButton: $("#steam-connect-button"),
  steamSyncButton: $("#steam-sync-button"),
  steamDisconnectButton: $("#steam-disconnect-button"),
  steamSyncMessage: $("#steam-sync-message"),
  gamePageImage: $("#game-page-image"),
  gamePageBadge: $("#game-page-badge"),
  gamePageTitle: $("#game-page-title"),
  gamePageByline: $("#game-page-byline"),
  gamePageDescription: $("#game-page-description"),
  gamePageMeta: $("#game-page-meta"),
  gamePageStoreLink: $("#game-page-store-link"),
  gamePageLibrary: $("#game-page-library"),
  gamePageFavorite: $("#game-page-favorite"),
  gamePageList: $("#game-page-list"),
  gamePageStatus: $("#game-page-status"),
  gamePageProgress: $("#game-page-progress"),
  gamePageProgressOutput: $("#game-page-progress-output"),
  gamePageStartedAt: $("#game-page-started-at"),
  gamePageCompletedAt: $("#game-page-completed-at"),
  gamePageCompletionCount: $("#game-page-completion-count"),
  gamePagePrimaryPlatform: $("#game-page-primary-platform"),
  gamePageDifficulty: $("#game-page-difficulty"),
  gamePageManualPlaytime: $("#game-page-manual-playtime"),
  gamePageSaveProgress: $("#game-page-save-progress"),
  gamePageRating: $("#game-page-rating"),
  gamePageNotes: $("#game-page-notes"),
  gamePageSaveNotes: $("#game-page-save-notes"),
  gameSessionForm: $("#game-session-form"),
  gameSessionDate: $("#game-session-date"),
  gameSessionMinutes: $("#game-session-minutes"),
  gameSessionProgress: $("#game-session-progress"),
  gameSessionPlatform: $("#game-session-platform"),
  gameSessionVisibility: $("#game-session-visibility"),
  gameSessionSpoilers: $("#game-session-spoilers"),
  gameSessionNote: $("#game-session-note"),
  gameSessionError: $("#game-session-error"),
  gameSessionSubmit: $("#game-session-submit"),
  gamePageSessions: $("#game-page-sessions"),
  gamePagePromotions: $("#game-page-promotions"),
  gamePageStoreOptions: $("#game-page-store-options"),
  gameRelatedSection: $("#game-related-section"),
  gameRelatedStatus: $("#game-related-status"),
  gameRelatedGrid: $("#game-related-grid"),
  publicRatingAverage: $("#public-rating-average"),
  publicRatingCount: $("#public-rating-count"),
  publicReviewSignedOut: $("#public-review-signed-out"),
  publicReviewForm: $("#public-review-form"),
  publicReviewRating: $("#public-review-rating"),
  publicReviewTitle: $("#public-review-title"),
  publicReviewBody: $("#public-review-body"),
  publicReviewSpoilers: $("#public-review-spoilers"),
  publicReviewError: $("#public-review-error"),
  publicReviewSubmit: $("#public-review-submit"),
  publicReviewDelete: $("#public-review-delete"),
  publicReviewsList: $("#public-reviews-list"),
  publicProfileLoading: $("#public-profile-loading"),
  publicProfileNotFound: $("#public-profile-not-found"),
  publicProfileContent: $("#public-profile-content"),
  publicProfileAvatar: $("#public-profile-avatar"),
  publicProfileName: $("#public-profile-name"),
  publicProfileHandle: $("#public-profile-handle"),
  publicProfileBio: $("#public-profile-bio"),
  publicProfileMemberSince: $("#public-profile-member-since"),
  publicProfileShare: $("#public-profile-share"),
  publicProfileStatReviews: $("#public-profile-stat-reviews"),
  publicProfileStatAverage: $("#public-profile-stat-average"),
  publicProfileStatLists: $("#public-profile-stat-lists"),
  publicProfileReviews: $("#public-profile-reviews"),
  publicProfileLists: $("#public-profile-lists"),
  sharedListLoading: $("#shared-list-loading"),
  sharedListNotFound: $("#shared-list-not-found"),
  sharedListContent: $("#shared-list-content"),
  sharedListVisibility: $("#shared-list-visibility"),
  sharedListTitle: $("#shared-list-title"),
  sharedListDescription: $("#shared-list-description"),
  sharedListAuthor: $("#shared-list-author"),
  sharedListMeta: $("#shared-list-meta"),
  sharedListShare: $("#shared-list-share"),
  sharedListGames: $("#shared-list-games"),
  sharedListLike: $("#shared-list-like"),
  sharedListLikeCount: $("#shared-list-like-count"),
  sharedListCommentCount: $("#shared-list-comment-count"),
  sharedListComments: $("#shared-list-comments"),
  publicProfileFollow: $("#public-profile-follow"),
  publicProfileLoginToFollow: $("#public-profile-login-to-follow"),
  publicProfileStatFollowers: $("#public-profile-stat-followers"),
  publicProfileStatFollowing: $("#public-profile-stat-following"),
  publicProfileDiary: $("#public-profile-diary"),
  diarySearch: $("#diary-search"),
  diaryPlatformFilter: $("#diary-platform-filter"),
  diaryMonthFilter: $("#diary-month-filter"),
  diaryClearFilters: $("#diary-clear-filters"),
  diaryEntryList: $("#diary-entry-list"),
  diaryEmpty: $("#diary-empty"),
  diaryStatSessions: $("#diary-stat-sessions"),
  diaryStatHours: $("#diary-stat-hours"),
  diaryStatGames: $("#diary-stat-games"),
  diaryStatMonth: $("#diary-stat-month"),
  statsTotalHours: $("#stats-total-hours"),
  statsSteamHours: $("#stats-steam-hours"),
  statsCompleted: $("#stats-completed"),
  statsCompletionRate: $("#stats-completion-rate"),
  statsBacklog: $("#stats-backlog"),
  statsSessions: $("#stats-sessions"),
  statsMonthlyChart: $("#stats-monthly-chart"),
  statsPlatforms: $("#stats-platforms"),
  statsStatuses: $("#stats-statuses"),
  statsTopGames: $("#stats-top-games"),
  notificationButton: $("#notification-button"),
  notificationBadge: $("#notification-badge"),
  sidebarNotificationBadge: $("#sidebar-notification-badge"),
  feedFollowingTab: $("#feed-following-tab"),
  feedPublicTab: $("#feed-public-tab"),
  feedShowPublic: $("#feed-show-public"),
  feedAuthRequired: $("#feed-auth-required"),
  feedList: $("#feed-list"),
  exploreUsersSearch: $("#explore-users-search"),
  exploreUsersGrid: $("#explore-users-grid"),
  notificationsAuthRequired: $("#notifications-auth-required"),
  notificationsList: $("#notifications-list"),
  notificationsMarkAll: $("#notifications-mark-all"),
  viewPublicProfile: $("#view-public-profile"),
};

let installPrompt = null;
let countdownTimer = null;
let editingListId = null;

function loadJson(key, fallback) {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || "null");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed
      : fallback;
  } catch {
    return fallback;
  }
}

function personalStorageKeys(userId = activeStorageUserId) {
  if (!userId) {
    return { library: GUEST_LIBRARY_KEY, lists: GUEST_LISTS_KEY };
  }
  const prefix = `${USER_STORAGE_PREFIX}${userId}:`;
  return {
    library: `${prefix}library:v1`,
    lists: `${prefix}lists:v1`,
  };
}

function migrateLegacyPersonalDataToGuest() {
  const guestKeys = personalStorageKeys(null);

  if (localStorage.getItem(guestKeys.library) === null) {
    for (const legacyKey of LEGACY_LIBRARY_KEYS) {
      const legacy = loadJson(legacyKey, null);
      if (legacy) {
        localStorage.setItem(guestKeys.library, JSON.stringify(legacy));
        break;
      }
    }
  }

  if (localStorage.getItem(guestKeys.lists) === null) {
    for (const legacyKey of LEGACY_LIST_KEYS) {
      const legacy = loadJson(legacyKey, null);
      if (legacy) {
        localStorage.setItem(guestKeys.lists, JSON.stringify(legacy));
        break;
      }
    }
  }

  [...LEGACY_LIBRARY_KEYS, ...LEGACY_LIST_KEYS]
    .forEach((key) => localStorage.removeItem(key));
}

function loadLibrary(userId = activeStorageUserId) {
  if (!userId) migrateLegacyPersonalDataToGuest();
  return loadJson(personalStorageKeys(userId).library, {});
}

function loadLists(userId = activeStorageUserId) {
  if (!userId) migrateLegacyPersonalDataToGuest();
  return loadJson(personalStorageKeys(userId).lists, {});
}

function persistPersonalDataLocally() {
  const keys = personalStorageKeys();
  localStorage.setItem(keys.library, JSON.stringify(state.library));
  localStorage.setItem(keys.lists, JSON.stringify(state.lists));
}

function switchPersonalStorage(userId) {
  activeStorageUserId = userId || null;
  state.library = loadLibrary(activeStorageUserId);
  state.lists = loadLists(activeStorageUserId);
  rebuildGameIndex();
  updateStats();
}

function clearPersonalStorage(userId) {
  const keys = personalStorageKeys(userId || null);
  localStorage.removeItem(keys.library);
  localStorage.removeItem(keys.lists);
}

function canSyncActiveAccount() {
  const authUserId = window.VaultAuth?.user?.id || null;
  return Boolean(activeStorageUserId && authUserId === activeStorageUserId);
}

function saveLibrary() {
  window.VaultCatalog?.clearRecommendationCache?.();
  state.discoveryRecommendations = null;
  persistPersonalDataLocally();
  updateStats();
  if (canSyncActiveAccount()) {
    window.VaultCloud?.schedulePush(state.library, state.lists);
  }
}

function saveLists() {
  window.VaultCatalog?.clearRecommendationCache?.();
  state.discoveryRecommendations = null;
  persistPersonalDataLocally();
  updateStats();
  if (canSyncActiveAccount()) {
    window.VaultCloud?.schedulePush(state.library, state.lists);
  }
}

function showToast(message) {
  ui.toast.textContent = message;
  ui.toast.hidden = false;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { ui.toast.hidden = true; }, 3200);
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value || "";
  return div.innerHTML;
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll('"', "&quot;");
}

function gameKey(game) {
  return game.match_key || game.canonical_id || game.internal_id || game.listing_id || game.epic_id || game.promotion_key ||
    `${game.store || "epic"}:${game.namespace || "unknown"}:${game.external_id || game.title}`;
}

function gameAliases(game) {
  return [
    game.match_key,
    game.canonical_id,
    game.internal_id,
    game.listing_id,
    game.epic_id,
    game.promotion_key,
    game.external_id,
    game.namespace && (game.external_id || game.epic_id)
      ? `epic:${game.namespace}:${game.external_id || game.epic_id}`
      : null,
  ].filter(Boolean);
}

function reviewKeysForGame(game) {
  return [...new Set([gameKey(game), ...gameAliases(game)].filter(Boolean))];
}

function snapshotGame(game) {
  return {
    canonical_id: game.canonical_id,
    canonical_title: game.canonical_title,
    match_key: game.match_key,
    listing_id: game.listing_id || game.internal_id,
    internal_id: game.internal_id || game.listing_id,
    store: game.store || "epic",
    stores: game.stores || [game.store || "epic"],
    store_listings: game.store_listings || [],
    platforms: game.platforms || ["pc"],
    external_id: game.external_id || game.epic_id,
    epic_id: game.epic_id,
    namespace: game.namespace,
    title: game.title,
    description: game.description,
    developer: game.developer,
    publisher: game.publisher,
    image_url: game.image_url,
    store_url: game.store_url,
    release_date: game.release_date,
    release_year: game.release_year,
    fmt_original_price: game.fmt_original_price,
    fmt_discount_price: game.fmt_discount_price,
    original_price: game.original_price,
    discount_price: game.discount_price,
    currency_code: game.currency_code,
    currency_decimals: game.currency_decimals,
    start_date: game.start_date,
    end_date: game.end_date,
    is_mystery_game: game.is_mystery_game,
    offer_type: game.offer_type,
    category_group: game.category_group,
    edition_name: game.edition_name,
    market_segment: game.market_segment,
    market_segment_source: game.market_segment_source,
    genres: game.genres || [],
    categories: game.categories || [],
    source_kind: game.source_kind,
  };
}

function getLibraryEntry(game) {
  return state.library[gameKey(game)] || null;
}

function setLibraryEntry(game, patch = {}) {
  const key = gameKey(game);
  const current = state.library[key] || {
    addedAt: new Date().toISOString(),
    status: "saved",
    favorite: false,
    rating: 0,
    notes: "",
  };
  state.library[key] = {
    ...current,
    ...patch,
    updatedAt: new Date().toISOString(),
    game: snapshotGame(game),
  };
  saveLibrary();
  rebuildGameIndex();
  return state.library[key];
}

function removeLibraryEntry(game) {
  const key = gameKey(game);
  delete state.library[key];
  saveLibrary();
  rebuildGameIndex();
  window.VaultCloud?.deleteLibraryItem(key).catch(console.error);
}

function formatDate(value, withTime = false) {
  if (!value) return "Data non disponibile";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Data non disponibile";
  return new Intl.DateTimeFormat("it-IT", withTime
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium" }).format(date);
}

function priceText(game) {
  if (game.source_kind === "promotion") return game.fmt_original_price || "";
  return game.fmt_discount_price || game.fmt_original_price || "";
}

function getMode(game) {
  if (game.source_kind === "catalog") return "catalog";
  const now = Date.now();
  const start = new Date(game.start_date).getTime();
  const end = new Date(game.end_date).getTime();
  if (start && start > now) return "upcoming";
  if (end && end <= now) return "expired";
  return "current";
}

function countdownText(game) {
  const mode = getMode(game);
  if (mode === "catalog") return game.release_date ? formatDate(game.release_date) : "";
  const target = mode === "upcoming" ? game.start_date : game.end_date;
  const diff = new Date(target).getTime() - Date.now();
  if (diff <= 0) return mode === "upcoming" ? "Disponibile ora" : "Terminato";
  const mins = Math.floor(diff / 60000);
  const days = Math.floor(mins / 1440);
  const hours = Math.floor((mins % 1440) / 60);
  return `${mode === "upcoming" ? "Tra" : "Scade tra"} ${days ? `${days}g ` : ""}${hours}h`;
}


function releaseYearOf(game) {
  const explicit = Number(game.release_year);
  if (Number.isInteger(explicit) && explicit > 1900) return explicit;
  const value = game.release_date || game.start_date;
  if (!value) return null;
  const year = new Date(value).getFullYear();
  return Number.isInteger(year) ? year : null;
}

function inferCategoryGroup(game) {
  const offer = String(game.offer_type || "").toUpperCase();
  const categories = (game.categories || []).join(" ").toLowerCase();
  if (["ADD_ON", "DLC"].includes(offer) || categories.includes("addon")) return "dlc";
  if (offer === "BUNDLE" || categories.includes("bundle")) return "bundle";
  if (offer === "BASE_GAME" || categories.includes("games/edition/base")) return "base_game";
  if (offer === "EDITION" || categories.includes("games/edition")) return "edition";
  return "other";
}

function inferMarketSegment(game) {
  const known = String(game.market_segment || "");
  if (["aaa", "indie", "unclassified"].includes(known)) return known;
  return "unclassified";
}

function priceBucket(game) {
  const original = Number(game.original_price);
  const discounted = Number(game.discount_price);
  if (Number.isFinite(discounted) && discounted === 0) return "free";
  if (Number.isFinite(original) && Number.isFinite(discounted) && discounted < original) return "discounted";
  return "paid";
}

function storeLabel(store) {
  return {
    epic: "Epic Games",
    steam: "Steam",
    playstation: "PlayStation",
    xbox: "Xbox",
  }[store || "epic"] || String(store || "Store");
}

function normalizePromotion(game) {
  const listingAlias = game.namespace && (game.epic_id || game.external_id)
    ? `epic:${game.namespace}:${game.epic_id || game.external_id}`
    : null;
  const catalogMatch = listingAlias ? state.gameIndex.get(listingAlias) : null;
  return {
    ...game,
    canonical_id: game.canonical_id || catalogMatch?.canonical_id,
    match_key: game.match_key || catalogMatch?.match_key,
    listing_id: game.listing_id || listingAlias,
    internal_id: game.internal_id || listingAlias,
    category_group: game.category_group || "base_game",
    market_segment: game.market_segment || catalogMatch?.market_segment || "unclassified",
    release_year: game.release_year || catalogMatch?.release_year,
    source_kind: "promotion",
    store: "epic",
    platforms: game.platforms || ["pc"],
  };
}

function normalizeCatalog(game) {
  const store = game.store || "epic";
  return {
    ...game,
    listing_id: game.listing_id || game.internal_id,
    source_kind: "catalog",
    store,
    stores: game.stores || [store],
    store_listings: game.store_listings || [],
    category_group: game.category_group || inferCategoryGroup(game),
    market_segment: game.market_segment || inferMarketSegment(game),
    release_year: game.release_year || releaseYearOf(game),
    platforms: game.platforms || ["pc"],
  };
}


function listingRichness(game) {
  return [
    game.description,
    game.developer,
    game.publisher,
    game.image_url,
    game.release_date,
    game.fmt_discount_price,
    game.fmt_original_price,
  ].filter(Boolean).length + (game.store === "epic" ? 2 : 0);
}

function groupedCatalogGames() {
  return state.catalog.map(normalizeCatalog);
}

function registerCatalogGame(game) {
  if (!game?.title) return;
  const normalized = normalizeCatalog(game);
  for (const alias of gameAliases(normalized)) state.gameIndex.set(alias, normalized);
  state.gameIndex.set(gameKey(normalized), normalized);
  if (normalized.canonical_id) state.gameIndex.set(normalized.canonical_id, normalized);
  if (normalized.match_key) state.gameIndex.set(normalized.match_key, normalized);
  for (const listing of normalized.store_listings || []) {
    if (listing.listing_id) state.gameIndex.set(listing.listing_id, normalized);
  }
}

function personalCatalogKeys({ favorite = false } = {}) {
  return [...new Set(Object.entries(state.library)
    .filter(([, entry]) => !favorite || entry?.favorite)
    .map(([key, entry]) => entry?.game?.match_key || entry?.game?.canonical_id || (/^(?:title|game):/.test(key) ? key : null))
    .filter(Boolean))];
}

function catalogSearchOptions(offset = 0) {
  return {
    query: state.search,
    stores: state.storeFilter === "all" ? null : [state.storeFilter],
    category: state.categoryFilter,
    segment: state.segmentFilter,
    price: state.priceFilter,
    year: state.yearFilter === "all" ? null : Number(state.yearFilter),
    libraryKeys: personalCatalogKeys(),
    favoriteKeys: personalCatalogKeys({ favorite: true }),
    personalFilter: state.statusFilter,
    sort: state.sort,
    limit: state.catalogLimit,
    offset,
  };
}

async function loadCatalogPage({ reset = true, force = false } = {}) {
  if (state.route.name !== "catalog") return;
  if (!window.VaultCatalog?.configured()) {
    state.catalog = [];
    state.catalogTotal = 0;
    state.catalogLoading = false;
    ui.status.hidden = false;
    ui.status.textContent = "Configura Supabase ed esegui la migrazione v4.1 per usare il catalogo.";
    renderDashboard();
    return;
  }

  const requestId = ++state.catalogRequestId;
  const offset = reset ? 0 : state.catalog.length;
  state.catalogLoading = true;
  if (reset) {
    state.catalog = [];
    state.catalogOffset = 0;
  }
  renderGames();

  try {
    const response = await window.VaultCatalog.search({
      ...catalogSearchOptions(offset),
      force,
    });
    if (requestId !== state.catalogRequestId || state.route.name !== "catalog") return;

    const incoming = response.items.map(normalizeCatalog);
    if (reset) {
      state.catalog = incoming;
    } else {
      const merged = new Map(state.catalog.map((game) => [gameKey(game), game]));
      for (const game of incoming) merged.set(gameKey(game), game);
      state.catalog = [...merged.values()];
    }
    state.catalogTotal = response.total;
    state.catalogOffset = state.catalog.length;
    state.catalogHasMore = state.catalog.length < response.total;
    for (const game of incoming) registerCatalogGame(game);
    ui.status.hidden = true;
  } catch (error) {
    console.error("Caricamento catalogo fallito", error);
    if (requestId !== state.catalogRequestId) return;
    ui.status.hidden = false;
    ui.status.textContent = "Catalogo temporaneamente non disponibile. Controlla la migrazione e i workflow v4.1.";
  } finally {
    if (requestId === state.catalogRequestId) {
      state.catalogLoading = false;
      renderDashboard();
    }
  }
}

function renderCatalogPagination() {
  const visible = state.route.name === "catalog";
  ui.catalogPagination.hidden = !visible;
  if (!visible) return;
  const shown = state.catalog.length;
  const total = state.catalogTotal;
  ui.catalogPageSummary.textContent = total
    ? `${shown.toLocaleString("it-IT")} di ${total.toLocaleString("it-IT")} giochi`
    : state.catalogLoading ? "Caricamento…" : "Nessun risultato";
  ui.catalogLoadMore.hidden = !state.catalogHasMore;
  ui.catalogLoadMore.disabled = state.catalogLoading;
  ui.catalogLoadMore.textContent = state.catalogLoading ? "Caricamento…" : "Carica altri giochi";
}

async function hydrateCatalogKeys(keys) {
  const missing = [...new Set((keys || []).filter((key) => key && !resolveGameByKey(key)))];
  if (!missing.length || !window.VaultCatalog?.configured()) return [];
  try {
    const games = await window.VaultCatalog.getGames(missing);
    for (const game of games) registerCatalogGame(game);
    return games;
  } catch (error) {
    console.warn("Impossibile caricare i giochi della lista", error);
    return [];
  }
}

function listingsForGame(game) {
  const key = game.match_key || gameKey(game);
  const direct = (game.store_listings || []).map((listing) => ({
    ...listing,
    source_kind: "catalog",
    match_key: key,
  }));
  if (direct.length) return direct;

  return state.catalog
    .map(normalizeCatalog)
    .filter((candidate) =>
      (candidate.match_key && candidate.match_key === key)
      || (!candidate.match_key && candidate.canonical_id === game.canonical_id)
    );
}

function historyGames() {
  return state.history.map(normalizePromotion);
}

function libraryGames() {
  return Object.values(state.library)
    .filter((entry) => entry?.game)
    .map((entry) => ({
      ...entry.game,
      libraryStatus: entry.status,
      favorite: entry.favorite,
      rating: entry.rating,
      notes: entry.notes,
    }));
}

function rebuildGameIndex() {
  const next = new Map();
  const insert = (game) => {
    if (!game?.title) return;
    for (const alias of gameAliases(game)) {
      const previous = next.get(alias);
      if (!previous || game.source_kind === "promotion") next.set(alias, game);
    }
    next.set(gameKey(game), game);
  };

  state.catalog.map(normalizeCatalog).forEach(insert);
  groupedCatalogGames().forEach(insert);
  // Rende subito disponibili gli alias delle listing ai parser delle promozioni.
  state.gameIndex = next;
  historyGames().forEach(insert);
  state.upcoming.map(normalizePromotion).forEach(insert);
  state.current.map(normalizePromotion).forEach(insert);
  libraryGames().forEach(insert);
  state.gameIndex = next;
}

function resolveGameByKey(key) {
  return state.gameIndex.get(key) || state.library[key]?.game || null;
}

function gameRoute(game) {
  return `#/game/${encodeURIComponent(gameKey(game))}`;
}

function listRoute(id) {
  return `#/list/${encodeURIComponent(id)}`;
}

function franchiseRoute(slug) {
  return `#/franchise/${encodeURIComponent(slug)}`;
}

function editorialCollectionRoute(slug) {
  return `#/collection/${encodeURIComponent(slug)}`;
}

function entityRoute(kind, name) {
  const safeKind = kind === "publisher" ? "publisher" : "developer";
  return `#/${safeKind}/${encodeURIComponent(name)}`;
}

const MOBILE_NAV_QUERY = window.matchMedia("(max-width: 820px)");
let lastMobileMenuTrigger = null;
let lastFilterTrigger = null;

function visibleFocusable(container) {
  if (!container) return [];
  return [...container.querySelectorAll(
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
  )].filter((node) => !node.hidden && node.getClientRects().length > 0);
}

function setOverlayHistory(kind) {
  const current = window.history.state || {};
  if (current.tfvOverlay === kind) return;
  window.history.pushState({ ...current, tfvOverlay: kind }, "", window.location.href);
}

function clearOverlayHistoryMarker() {
  const current = window.history.state || {};
  if (!current.tfvOverlay) return;
  const next = { ...current };
  delete next.tfvOverlay;
  window.history.replaceState(next, "", window.location.href);
}

function openMobileMenu() {
  if (!MOBILE_NAV_QUERY.matches || !ui.sidebar) return;
  closeMobileFilters({ restoreFocus: false, clearHistory: true });
  lastMobileMenuTrigger = document.activeElement;
  document.body.classList.add("menu-open");
  ui.menuButton?.setAttribute("aria-expanded", "true");
  ui.sidebar.setAttribute("aria-hidden", "false");
  setOverlayHistory("menu");
  requestAnimationFrame(() => ui.sidebarClose?.focus());
}

function closeMobileMenu({ restoreFocus = true, clearHistory = false } = {}) {
  if (!document.body.classList.contains("menu-open")) return;
  document.body.classList.remove("menu-open");
  ui.menuButton?.setAttribute("aria-expanded", "false");
  if (MOBILE_NAV_QUERY.matches) ui.sidebar?.setAttribute("aria-hidden", "true");
  if (clearHistory) clearOverlayHistoryMarker();
  if (restoreFocus && lastMobileMenuTrigger instanceof HTMLElement) lastMobileMenuTrigger.focus();
}

function requestCloseMobileMenu() {
  if (window.history.state?.tfvOverlay === "menu") window.history.back();
  else closeMobileMenu();
}

function openMobileFilters() {
  if (!MOBILE_NAV_QUERY.matches || ui.toolbarControls?.hidden) return;
  closeMobileMenu({ restoreFocus: false, clearHistory: true });
  lastFilterTrigger = document.activeElement;
  document.body.classList.add("filters-open");
  ui.mobileFilterToggle?.setAttribute("aria-expanded", "true");
  setOverlayHistory("filters");
  requestAnimationFrame(() => ui.mobileFilterClose?.focus());
}

function closeMobileFilters({ restoreFocus = true, clearHistory = false } = {}) {
  if (!document.body.classList.contains("filters-open")) return;
  document.body.classList.remove("filters-open");
  ui.mobileFilterToggle?.setAttribute("aria-expanded", "false");
  if (clearHistory) clearOverlayHistoryMarker();
  if (restoreFocus && lastFilterTrigger instanceof HTMLElement) lastFilterTrigger.focus();
}

function requestCloseMobileFilters() {
  if (window.history.state?.tfvOverlay === "filters") window.history.back();
  else closeMobileFilters();
}

function closeMobileOverlaysForNavigation() {
  closeMobileMenu({ restoreFocus: false, clearHistory: true });
  closeMobileFilters({ restoreFocus: false, clearHistory: true });
}

function trapMobileOverlayFocus(event) {
  if (event.key !== "Tab") return;
  const container = document.body.classList.contains("menu-open")
    ? ui.sidebar
    : document.body.classList.contains("filters-open")
      ? ui.toolbarControls
      : null;
  const focusable = visibleFocusable(container);
  if (!focusable.length) return;
  const first = focusable[0];
  const last = focusable.at(-1);
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

function parseRoute() {
  const rawHash = window.location.hash || "#/home";
  if (/^#(?:access_token|refresh_token|error|error_description)=/.test(rawHash)) {
    return { name: "auth-callback", params: {}, query: new URLSearchParams() };
  }
  const raw = rawHash.startsWith("#/") ? rawHash.slice(2) : rawHash.replace(/^#/, "");
  const [pathPart = "home", queryPart = ""] = raw.split("?");
  const segments = pathPart.split("/").filter(Boolean);
  const query = new URLSearchParams(queryPart);
  const first = segments[0] || "home";
  const simple = {
    home: "home",
    free: "current",
    current: "current",
    upcoming: "upcoming",
    history: "history",
    catalog: "catalog",
    discover: "discover",
    franchises: "editorial-directory",
    library: "library",
    lists: "lists",
    profile: "profile",
    feed: "feed",
    explore: "explore",
    notifications: "notifications",
    diary: "diary",
    stats: "stats",
    login: "login",
    register: "register",
    "forgot-password": "forgot-password",
    "reset-password": "reset-password",
  };
  if (first === "game" && segments[1]) {
    return { name: "game", params: { key: decodeURIComponent(segments.slice(1).join("/")) }, query };
  }
  if ((first === "developer" || first === "publisher") && segments[1]) {
    return {
      name: "entity",
      params: {
        kind: first,
        name: decodeURIComponent(segments.slice(1).join("/")),
      },
      query,
    };
  }
  if (first === "franchise" && segments[1]) {
    return { name: "franchise", params: { slug: decodeURIComponent(segments.slice(1).join("/")) }, query };
  }
  if (first === "collection" && segments[1]) {
    return { name: "editorial-collection", params: { slug: decodeURIComponent(segments.slice(1).join("/")) }, query };
  }
  if (first === "list" && segments[1]) {
    return { name: "list", params: { id: decodeURIComponent(segments[1]) }, query };
  }
  if (first === "user" && segments[1]) {
    return { name: "public-profile", params: { username: decodeURIComponent(segments.slice(1).join("/")) }, query };
  }
  if (first === "auth" && segments[1] === "callback") {
    return { name: "auth-callback", params: {}, query };
  }
  if (first === "settings") {
    return { name: "settings", params: { section: segments[1] || "profile" }, query };
  }
  if (first === "admin") {
    const section = ["catalog", "editorial", "matching", "moderation", "system"].includes(segments[1])
      ? segments[1]
      : "catalog";
    return { name: "admin", params: { section }, query };
  }
  return { name: simple[first] || "home", params: {}, query };
}

function routeToDashboardView(routeName) {
  return ["home", "current", "upcoming", "history", "catalog", "library", "lists"].includes(routeName);
}

function setPageVisibility(page) {
  ui.dashboardPage.hidden = page !== "dashboard";
  ui.gamePage.hidden = page !== "game";
  ui.authPage.hidden = page !== "auth";
  ui.profilePage.hidden = page !== "profile";
  ui.publicProfilePage.hidden = page !== "public-profile";
  ui.sharedListPage.hidden = page !== "shared-list";
  ui.settingsPage.hidden = page !== "settings";
  ui.feedPage.hidden = page !== "feed";
  ui.explorePage.hidden = page !== "explore";
  ui.notificationsPage.hidden = page !== "notifications";
  ui.diaryPage.hidden = page !== "diary";
  ui.statsPage.hidden = page !== "stats";
  ui.discoveryPage.hidden = page !== "discovery";
  ui.entityPage.hidden = page !== "entity";
  ui.editorialDirectoryPage.hidden = page !== "editorial-directory";
  ui.franchisePage.hidden = page !== "franchise";
  ui.editorialCollectionPage.hidden = page !== "editorial-collection";
  ui.adminPage.hidden = page !== "admin";
}

function updateDocumentTitle(label) {
  document.title = label ? `${label} · The Free Vault` : "The Free Vault";
}

function setActiveNavigation(routeName) {
  const normalized = routeName === "list"
    ? "lists"
    : routeName === "public-profile"
      ? "profile"
      : routeName === "settings"
        ? "settings"
        : routeName === "entity"
          ? "discover"
          : ["editorial-directory", "franchise", "editorial-collection"].includes(routeName)
            ? "editorial"
            : routeName === "admin"
            ? `admin-${state.route.params.section || "catalog"}`
            : routeName;
  $$("[data-route]").forEach((node) => {
    node.classList.toggle("is-active", node.dataset.route === normalized);
  });
}

function navigate(hash) {
  if (window.location.hash === hash) {
    handleRoute();
  } else {
    window.location.hash = hash;
  }
}

function handleRoute() {
  closeMobileOverlaysForNavigation();
  state.route = parseRoute();
  setActiveNavigation(state.route.name);

  if (state.route.name === "catalog") {
    const query = (state.route.query.get("q") || "").trim();
    state.search = query;
    state.globalSearch = query;
    ui.search.value = query;
  } else {
    state.search = "";
    state.globalSearch = "";
    ui.search.value = "";
  }
  hideGlobalSearchResults();

  if (routeToDashboardView(state.route.name)) {
    setPageVisibility("dashboard");
    renderDashboard();
    if (state.route.name === "catalog") void loadCatalogPage({ reset: true });
  } else if (state.route.name === "list") {
    setPageVisibility("shared-list");
    void renderSharedListPage();
  } else if (state.route.name === "game") {
    setPageVisibility("game");
    void renderGamePage();
  } else if (state.route.name === "discover") {
    setPageVisibility("discovery");
    void renderDiscoveryPage();
  } else if (state.route.name === "editorial-directory") {
    setPageVisibility("editorial-directory");
    void renderEditorialDirectory();
  } else if (state.route.name === "franchise") {
    setPageVisibility("franchise");
    void renderFranchisePage();
  } else if (state.route.name === "editorial-collection") {
    setPageVisibility("editorial-collection");
    void renderEditorialCollectionPage();
  } else if (state.route.name === "entity") {
    setPageVisibility("entity");
    void loadEntityPage({ reset: true });
  } else if (state.route.name === "public-profile") {
    setPageVisibility("public-profile");
    void renderPublicProfilePage();
  } else if (state.route.name === "feed") {
    setPageVisibility("feed");
    void renderFeedPage();
  } else if (state.route.name === "explore") {
    setPageVisibility("explore");
    void renderExplorePage();
  } else if (state.route.name === "notifications") {
    setPageVisibility("notifications");
    void renderNotificationsPage();
  } else if (state.route.name === "diary") {
    setPageVisibility("diary");
    renderDiaryPage();
  } else if (state.route.name === "stats") {
    setPageVisibility("stats");
    void renderStatsPage();
  } else if (["login", "register", "forgot-password", "reset-password", "auth-callback"].includes(state.route.name)) {
    setPageVisibility("auth");
    renderAuthPage();
  } else if (state.route.name === "profile") {
    setPageVisibility("profile");
    renderProfilePage();
  } else if (state.route.name === "settings") {
    setPageVisibility("settings");
    renderSettingsPage();
  } else if (state.route.name === "admin") {
    setPageVisibility("admin");
    void renderAdminPage();
  } else {
    navigate("#/home");
  }
  window.scrollTo({ top: 0, behavior: "auto" });
}


function allSearchText(game) {
  const entry = getLibraryEntry(game);
  return [
    game.title,
    game.canonical_title,
    game.description,
    game.publisher,
    game.developer,
    game.offer_type,
    game.category_group,
    game.market_segment,
    (game.genres || []).join(" "),
    ...(game.stores || [game.store || "epic"]).map(storeLabel),
    entry?.status,
    entry?.notes,
  ].filter(Boolean).join(" ").toLocaleLowerCase("it");
}

function gameMatchesSearch(game) {
  return !state.search || allSearchText(game).includes(state.search.toLocaleLowerCase("it"));
}

function matchesStatusFilter(game) {
  const entry = getLibraryEntry(game);
  const route = state.route.name;
  if (!["catalog", "library", "history"].includes(route)) return true;
  if (state.statusFilter === "all") return true;

  if (route === "history") {
    if (state.statusFilter === "redeemed") return Boolean(entry);
    if (state.statusFilter === "missed") return !entry;
  }

  if (route === "library") {
    if (state.statusFilter === "favorite") return Boolean(entry?.favorite);
    return entry?.status === state.statusFilter;
  }

  if (state.statusFilter === "saved") return Boolean(entry);
  if (state.statusFilter === "favorite") return Boolean(entry?.favorite);
  return true;
}

function matchesAdvancedFilters(game) {
  const route = state.route.name;
  if (!["catalog", "library", "history"].includes(route)) return true;

  if (route === "catalog") {
    const stores = game.stores || [game.store || "epic"];
    if (state.storeFilter !== "all" && !stores.includes(state.storeFilter)) return false;
    if (state.categoryFilter !== "all" && inferCategoryGroup(game) !== state.categoryFilter) return false;
    if (state.segmentFilter !== "all" && inferMarketSegment(game) !== state.segmentFilter) return false;
    if (state.priceFilter !== "all" && priceBucket(game) !== state.priceFilter) return false;
    if (state.yearFilter !== "all" && String(releaseYearOf(game) || "") !== state.yearFilter) return false;
  }

  if (route === "library") {
    const stores = game.stores || [game.store || "epic"];
    if (state.storeFilter !== "all" && !stores.includes(state.storeFilter)) return false;
    if (state.categoryFilter !== "all" && inferCategoryGroup(game) !== state.categoryFilter) return false;
    if (state.segmentFilter !== "all" && inferMarketSegment(game) !== state.segmentFilter) return false;
  }

  if (route === "history") {
    if (state.yearFilter !== "all" && String(releaseYearOf(game) || "") !== state.yearFilter) return false;
  }

  return true;
}

function sortGames(games) {
  const sorted = [...games];
  if (state.sort === "title") sorted.sort((a, b) => a.title.localeCompare(b.title, "it"));
  if (state.sort === "date") sorted.sort((a, b) =>
    new Date(b.release_date || b.start_date || 0) - new Date(a.release_date || a.start_date || 0));
  if (state.sort === "value") sorted.sort((a, b) =>
    (b.original_price || 0) - (a.original_price || 0));
  return sorted;
}

function gamesForDashboard() {
  let games = [];
  const route = state.route.name;
  if (route === "home") games = [...state.current, ...state.upcoming].map(normalizePromotion);
  if (route === "current") games = state.current.map(normalizePromotion);
  if (route === "upcoming") games = state.upcoming.map(normalizePromotion);
  if (route === "history") games = historyGames();
  if (route === "catalog") return state.catalog;
  if (route === "library") games = libraryGames();
  if (route === "list") {
    const list = state.lists[state.route.params.id];
    games = (list?.games || []).map(resolveGameByKey).filter(Boolean);
  }

  return sortGames(
    games
      .filter(gameMatchesSearch)
      .filter(matchesStatusFilter)
      .filter(matchesAdvancedFilters)
  );
}

function uniqueSearchGames() {
  const unique = new Map();
  for (const game of [
    ...state.current.map(normalizePromotion),
    ...state.upcoming.map(normalizePromotion),
    ...historyGames(),
    ...libraryGames(),
    ...state.catalog,
  ]) {
    if (!game?.title) continue;
    const key = gameKey(game);
    if (!unique.has(key)) unique.set(key, game);
  }
  return [...unique.values()];
}

function hideGlobalSearchResults() {
  ui.globalSearchResults.hidden = true;
  ui.globalSearchResults.replaceChildren();
  ui.search.setAttribute("aria-expanded", "false");
}

async function renderGlobalSearchResults() {
  const rawQuery = state.globalSearch.trim();
  const query = rawQuery.toLocaleLowerCase("it");
  if (query.length < 2) {
    hideGlobalSearchResults();
    return;
  }

  const requestId = ++state.globalSearchRequestId;
  ui.globalSearchResults.hidden = false;
  ui.globalSearchResults.innerHTML = '<div class="global-search-empty">Ricerca…</div>';
  ui.search.setAttribute("aria-expanded", "true");

  try {
    let results = [];
    if (window.VaultCatalog?.configured()) {
      const response = await window.VaultCatalog.search({
        query: rawQuery,
        limit: 8,
        offset: 0,
        sort: "relevance",
      });
      if (requestId !== state.globalSearchRequestId || state.globalSearch.trim() !== rawQuery) return;
      results = response.items;
    } else {
      results = uniqueSearchGames()
        .filter((game) => allSearchText(game).includes(query))
        .slice(0, 8);
    }

    ui.globalSearchResults.replaceChildren();
    if (!results.length) {
      const empty = document.createElement("div");
      empty.className = "global-search-empty";
      empty.textContent = "Nessun risultato.";
      ui.globalSearchResults.append(empty);
    } else {
      for (const game of results) {
        registerCatalogGame(game);
        const button = document.createElement("button");
        button.type = "button";
        button.className = "global-search-result";
        button.setAttribute("role", "option");
        button.innerHTML = `
          <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
          <span>
            <strong>${escapeHtml(game.title)}</strong>
            <small>${escapeHtml(game.developer || game.publisher || (game.stores || []).map(storeLabel).join(" · "))}</small>
          </span>
          <em>${escapeHtml((game.stores || [game.store]).map(storeLabel).join(" + "))}</em>`;
        button.onclick = () => {
          state.globalSearch = "";
          ui.search.value = "";
          hideGlobalSearchResults();
          navigate(gameRoute(game));
        };
        ui.globalSearchResults.append(button);
      }
    }

    const openCatalog = document.createElement("button");
    openCatalog.type = "button";
    openCatalog.className = "global-search-all";
    openCatalog.textContent = `Vedi tutti i risultati per “${rawQuery}”`;
    openCatalog.onclick = () => {
      hideGlobalSearchResults();
      navigate(`#/catalog?q=${encodeURIComponent(rawQuery)}`);
    };
    ui.globalSearchResults.append(openCatalog);
  } catch (error) {
    console.error("Ricerca globale fallita", error);
    if (requestId !== state.globalSearchRequestId) return;
    ui.globalSearchResults.innerHTML = '<div class="global-search-empty">Ricerca temporaneamente non disponibile.</div>';
  }
}

function updateStats() {
  $("#stat-current").textContent = state.current.length;
  ui.statCatalog.textContent = Number(state.catalogMeta?.total_games || 0).toLocaleString("it-IT");
  $("#stat-library").textContent = Object.keys(state.library).length;
  ui.statLists.textContent = Object.keys(state.lists).length;
}

function renderHero() {
  const game = state.current[0] ? normalizePromotion(state.current[0]) : null;
  ui.hero.hidden = state.route.name !== "home" || !game;
  if (!game) return;
  ui.heroImage.src = game.image_url || PLACEHOLDER;
  ui.heroImage.onerror = () => { ui.heroImage.src = PLACEHOLDER; };
  ui.heroTitle.textContent = game.title;
  ui.heroDescription.textContent = game.description || "";
  ui.heroPrice.textContent = game.fmt_original_price ? `${game.fmt_original_price} → GRATIS` : "GRATIS";
  ui.heroCountdown.textContent = countdownText(game);
  ui.heroLink.href = game.store_url;
  const inLibrary = Boolean(getLibraryEntry(game));
  ui.heroLibrary.textContent = inLibrary ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.heroLibrary.onclick = () => toggleLibraryWithoutRerender(game);
  ui.heroDetails.onclick = () => navigate(gameRoute(game));
}

function badgeText(game) {
  const mode = getMode(game);
  if (game.is_mystery_game) return "MYSTERY GAME";
  if (mode === "current") return "GRATIS ORA";
  if (mode === "upcoming") return "IN ARRIVO";
  if (mode === "expired") return "REGALO PASSATO";
  const stores = game.stores || [game.store || "epic"];
  return stores.length > 1
    ? stores.map((store) => storeLabel(store).replace(" Games", "")).join(" + ").toUpperCase()
    : `${storeLabel(stores[0]).toUpperCase()} STORE`;
}

function applyPriceToCard(game, originalPrice, priceLabel) {
  if (game.source_kind === "promotion") {
    originalPrice.hidden = !game.fmt_original_price;
    originalPrice.textContent = game.fmt_original_price || "";
    priceLabel.textContent = "GRATIS";
    return;
  }

  const originalValue = Number(game.original_price);
  const discountedValue = Number(game.discount_price);
  const hasOriginal = Number.isFinite(originalValue) && originalValue > 0;
  const hasDiscount = hasOriginal && Number.isFinite(discountedValue) && discountedValue >= 0 && discountedValue < originalValue;
  const isFreeToPlay = Number.isFinite(discountedValue) && discountedValue === 0 && originalValue === 0;

  if (hasDiscount) {
    originalPrice.hidden = false;
    originalPrice.textContent = game.fmt_original_price || "";
    priceLabel.textContent = game.fmt_discount_price || "In offerta";
  } else {
    originalPrice.hidden = true;
    originalPrice.textContent = "";
    if (isFreeToPlay) priceLabel.textContent = "FREE TO PLAY";
    else priceLabel.textContent = game.fmt_discount_price || game.fmt_original_price || `Vedi su ${storeLabel(game.store)}`;
  }
}


function updateCardPersonalState(card, game) {
  const entry = getLibraryEntry(game);
  const libraryButton = card.querySelector(".library-button");
  const favoriteButton = card.querySelector(".favorite-button");
  const favoriteIndicator = card.querySelector(".favorite-indicator");
  libraryButton.textContent = entry ? "In libreria" : "Aggiungi";
  favoriteButton.textContent = entry?.favorite ? "♥" : "♡";
  favoriteIndicator.hidden = !entry?.favorite;
  card.classList.toggle("is-saved", Boolean(entry));
  card.classList.toggle("is-favorite", Boolean(entry?.favorite));
}

function refreshGamePresentation(game) {
  const key = gameKey(game);
  const entry = getLibraryEntry(game);

  for (const card of $$(".game-card")) {
    const cardKey = card.dataset.gameKey;
    const cardGame = resolveGameByKey(cardKey);
    if (cardKey !== key && (!cardGame || gameKey(cardGame) !== key)) continue;

    const mustDisappear =
      (state.route.name === "library" && !entry) ||
      (state.statusFilter === "saved" && !entry) ||
      (state.statusFilter === "favorite" && !entry?.favorite);

    if (mustDisappear) card.remove();
    else updateCardPersonalState(card, game);
  }

  if (!ui.hero.hidden && state.current[0]) {
    const heroGame = normalizePromotion(state.current[0]);
    if (gameKey(heroGame) === key) {
      ui.heroLibrary.textContent = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
    }
  }

  updateStats();

  if (!ui.grid.hidden && !ui.grid.querySelector(".game-card") && state.route.name !== "lists") {
    ui.grid.innerHTML = `<div class="empty-state"><strong>Nessun gioco trovato</strong><span>Modifica ricerca o filtri.</span></div>`;
  }
}

function toggleLibraryWithoutRerender(game) {
  if (getLibraryEntry(game)) removeLibraryEntry(game);
  else setLibraryEntry(game);
  refreshGamePresentation(game);
}

function renderCard(game) {
  const fragment = ui.template.content.cloneNode(true);
  const card = fragment.querySelector(".game-card");
  const cover = fragment.querySelector(".card-cover");
  const image = fragment.querySelector(".game-image");
  const badge = fragment.querySelector(".game-badge");
  const publisher = fragment.querySelector(".publisher");
  const title = fragment.querySelector(".game-title");
  const description = fragment.querySelector(".game-description");
  const originalPrice = fragment.querySelector(".original-price");
  const priceLabel = fragment.querySelector(".free-label");
  const countdown = fragment.querySelector(".countdown");
  const progress = fragment.querySelector(".progress-track");
  const storeLink = fragment.querySelector(".store-link");
  const libraryButton = fragment.querySelector(".library-button");
  const favoriteButton = fragment.querySelector(".favorite-button");

  card.dataset.gameKey = gameKey(game);
  image.src = game.image_url || PLACEHOLDER;
  image.alt = `Copertina di ${game.title}`;
  image.onerror = () => { image.src = PLACEHOLDER; };
  badge.textContent = badgeText(game);
  publisher.textContent = game.developer || game.publisher || storeLabel(game.store);
  title.textContent = game.title;
  description.textContent = game.description || "Descrizione non disponibile.";
  applyPriceToCard(game, originalPrice, priceLabel);
  countdown.textContent = countdownText(game);
  progress.hidden = game.source_kind === "catalog";
  storeLink.href = game.store_url;
  storeLink.textContent = `Apri su ${storeLabel(game.store)}`;
  updateCardPersonalState(card, game);

  cover.onclick = () => navigate(gameRoute(game));
  libraryButton.onclick = () => toggleLibraryWithoutRerender(game);
  favoriteButton.onclick = () => {
    setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
    refreshGamePresentation(game);
  };
  return fragment;
}

function renderGames() {
  const games = gamesForDashboard();
  ui.grid.replaceChildren();
  if (!games.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    if (state.route.name === "catalog" && state.catalogLoading) {
      empty.innerHTML = `<strong>Caricamento catalogo…</strong><span>La ricerca viene eseguita sul database, senza scaricare 160.000 titoli.</span>`;
    } else {
      empty.innerHTML = `<strong>Nessun gioco trovato</strong><span>Modifica ricerca o filtri.</span>`;
    }
    ui.grid.append(empty);
  } else {
    for (const game of games) ui.grid.append(renderCard(game));
  }
  renderCatalogPagination();
}

function setSelectOptions(select, options, currentValue) {
  select.replaceChildren();
  for (const [value, label] of options) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    select.append(option);
  }
  select.value = options.some(([value]) => value === currentValue) ? currentValue : "all";
}

function populateYearFilter() {
  const catalogYears = Array.isArray(state.catalogMeta?.years) ? state.catalogMeta.years : [];
  const localYears = [...historyGames(), ...libraryGames()].map(releaseYearOf).filter(Boolean);
  const years = [...new Set([...catalogYears, ...localYears].map(Number).filter(Boolean))]
    .sort((a, b) => b - a);

  const current = state.yearFilter;
  setSelectOptions(
    ui.yearFilter,
    [["all", "Tutti gli anni"], ...years.map((year) => [String(year), String(year)])],
    current
  );
  state.yearFilter = ui.yearFilter.value;
}

function activeDashboardFilterCount() {
  const values = [
    state.statusFilter,
    state.storeFilter,
    state.categoryFilter,
    state.segmentFilter,
    state.priceFilter,
    state.yearFilter,
  ];
  return values.filter((value) => value && value !== "all").length
    + (state.sort !== "relevance" ? 1 : 0);
}

function updateMobileFilterSummary() {
  if (!ui.mobileFilterCount) return;
  const count = activeDashboardFilterCount();
  ui.mobileFilterCount.textContent = String(count);
  ui.mobileFilterCount.hidden = count === 0;
}

function configureContextualFilters() {
  const route = state.route.name;
  const controlsVisible = ["catalog", "library", "history"].includes(route);
  ui.toolbarControls.hidden = !controlsVisible;
  ui.mobileFilterToggle.hidden = !controlsVisible;
  if (!controlsVisible) closeMobileFilters({ restoreFocus: false, clearHistory: true });

  const visibility = {
    store: ["catalog", "library"].includes(route),
    category: ["catalog", "library"].includes(route),
    segment: ["catalog", "library"].includes(route),
    price: route === "catalog",
    year: ["catalog", "history"].includes(route),
    status: ["catalog", "library", "history"].includes(route),
    sort: controlsVisible,
  };

  $("#store-filter-wrap").hidden = !visibility.store;
  $("#category-filter-wrap").hidden = !visibility.category;
  $("#segment-filter-wrap").hidden = !visibility.segment;
  $("#price-filter-wrap").hidden = !visibility.price;
  $("#year-filter-wrap").hidden = !visibility.year;
  $("#status-filter-wrap").hidden = !visibility.status;
  $("#sort-filter-wrap").hidden = !visibility.sort;

  if (route === "catalog") {
    setSelectOptions(ui.filter, [
      ["all", "Tutti"],
      ["saved", "In libreria"],
      ["favorite", "Preferiti"],
    ], state.statusFilter);
  } else if (route === "library") {
    setSelectOptions(ui.filter, [
      ["all", "Tutti gli stati"],
      ["saved", "In libreria"],
      ["backlog", "Da giocare"],
      ["playing", "In corso"],
      ["paused", "In pausa"],
      ["completed", "Completati"],
      ["abandoned", "Abbandonati"],
      ["replay", "Da rigiocare"],
      ["favorite", "Preferiti"],
    ], state.statusFilter);
  } else if (route === "history") {
    setSelectOptions(ui.filter, [
      ["all", "Tutti"],
      ["redeemed", "Riscattati"],
      ["missed", "Persi"],
    ], state.statusFilter);
  }

  state.statusFilter = ui.filter.value;
  populateYearFilter();
  updateMobileFilterSummary();
}

function renderDashboardHeader() {
  const labels = {
    home: ["THE FREE VAULT", "Scopri i giochi gratuiti"],
    current: ["FREE TRACKER", "Gratis adesso"],
    upcoming: ["FREE TRACKER", "In arrivo"],
    history: ["FREE TRACKER", "Cronologia dei regali"],
    catalog: ["DISCOVER", "Catalogo multi-store"],
    library: ["PERSONALE", "La mia libreria"],
    lists: ["PERSONALE", "Le mie liste"],
    list: ["LISTA PERSONALE", state.lists[state.route.params.id]?.name || "Lista"],
  };
  const [eyebrow, title] = labels[state.route.name] || labels.home;
  ui.eyebrow.textContent = eyebrow;
  ui.title.textContent = title;
  updateDocumentTitle(title);
  ui.listsDashboard.hidden = state.route.name !== "lists";
  ui.toolbar.hidden = state.route.name === "lists";
  ui.catalogMeta.hidden = state.route.name !== "catalog";
  configureContextualFilters();

  if (state.route.name === "catalog") {
    const stores = state.catalogMeta?.stores || {};
    const epicTotal = Number(stores.epic || 0);
    const steamTotal = Number(stores.steam || 0);
    const totalGames = Number(state.catalogMeta?.total_games || 0);
    const completed = (state.catalogMeta?.sync || [])
      .filter((entry) => entry.status === "completed" && entry.completed_at)
      .map((entry) => entry.completed_at)
      .sort()
      .at(-1);
    ui.catalogMeta.textContent = totalGames
      ? `${totalGames.toLocaleString("it-IT")} giochi canonici · ${epicTotal.toLocaleString("it-IT")} Epic · ${steamTotal.toLocaleString("it-IT")} Steam${completed ? ` · aggiornato ${formatDate(completed, true)}` : ""}`
      : "Catalogo Supabase vuoto. Esegui la migrazione v4.1 e poi i workflow Epic e Steam.";
  }
}

function renderListsOverview() {
  ui.listsGrid.replaceChildren();
  const lists = Object.values(state.lists).sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || ""));
  if (!lists.length) {
    ui.listsGrid.innerHTML = `<div class="empty-state"><strong>Nessuna lista</strong><span>Crea raccolte ordinate come su Letterboxd.</span></div>`;
    return;
  }
  const coverKeys = lists.flatMap((list) => (list.games || []).slice(0, 4));
  const missingCoverKeys = coverKeys.filter((key) => !resolveGameByKey(key));
  if (missingCoverKeys.length) {
    void hydrateCatalogKeys(missingCoverKeys).then(() => {
      if (state.route.name === "lists") renderListsOverview();
    });
  }

  for (const list of lists) {
    const card = document.createElement("article");
    card.className = "list-card";
    const coverGames = (list.games || []).slice(0, 4).map(resolveGameByKey).filter(Boolean);
    card.innerHTML = `
      <button class="list-cover-stack" type="button" aria-label="Apri ${escapeAttr(list.name)}">
        ${[0, 1, 2, 3].map((i) => `<img src="${escapeAttr(coverGames[i]?.image_url || PLACEHOLDER)}" alt="">`).join("")}
      </button>
      <div class="list-card-body">
        <span class="pill">${list.visibility === "public" ? "PUBBLICA" : "PRIVATA"}</span>
        <h3>${escapeHtml(list.name)}</h3>
        <p>${escapeHtml(list.description || "Nessuna descrizione.")}</p>
        <small>${(list.games || []).length} giochi</small>
        <div class="list-card-actions">
          <a class="button button-primary" href="${listRoute(list.id)}">Apri</a>
          <button class="button button-secondary edit-list" type="button">Modifica</button>
          <button class="button button-secondary delete-list" type="button">Elimina</button>
        </div>
      </div>`;
    card.querySelector(".list-cover-stack").onclick = () => navigate(listRoute(list.id));
    card.querySelector(".edit-list").onclick = () => openListEditor(list.id);
    card.querySelector(".delete-list").onclick = async () => {
      if (!confirm(`Eliminare la lista “${list.name}”?`)) return;
      delete state.lists[list.id];
      saveLists();
      await window.VaultCloud?.deleteList(list.id).catch(console.error);
      renderDashboard();
    };
    ui.listsGrid.append(card);
  }
}

function renderDashboard() {
  renderHero();
  renderDashboardHeader();
  ui.grid.hidden = state.route.name === "lists";
  if (state.route.name === "lists") renderListsOverview();
  else renderGames();
  updateStats();
  updateCountdowns();
}

function openListEditor(id = null) {
  editingListId = id;
  const list = id ? state.lists[id] : null;
  ui.listDialogTitle.textContent = list ? "Modifica lista" : "Nuova lista";
  ui.listName.value = list?.name || "";
  ui.listDescription.value = list?.description || "";
  ui.listVisibility.value = list?.visibility || "private";
  ui.listDialog.showModal();
}

function saveListEditor() {
  const name = ui.listName.value.trim();
  if (!name) return showToast("Inserisci un titolo per la lista.");
  const id = editingListId || crypto.randomUUID();
  const previous = state.lists[id];
  const games = new Set(previous?.games || []);
  if (!editingListId && state.pendingListGame) games.add(gameKey(state.pendingListGame));
  state.lists[id] = {
    id,
    name,
    description: ui.listDescription.value.trim(),
    visibility: ui.listVisibility.value,
    games: [...games],
    createdAt: previous?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  saveLists();
  ui.listDialog.close();
  editingListId = null;
  state.pendingListGame = null;
  if (state.route.name === "lists") renderDashboard();
  else showToast("Lista salvata.");
}

function openListPicker(game) {
  state.pendingListGame = game;
  ui.listPickerItems.replaceChildren();
  const lists = Object.values(state.lists);
  if (!lists.length) {
    ui.listPickerItems.innerHTML = `<div class="empty-state"><strong>Nessuna lista</strong><span>Creane una per iniziare.</span></div>`;
  }
  for (const list of lists) {
    const key = gameKey(game);
    const included = (list.games || []).includes(key);
    const button = document.createElement("button");
    button.className = "list-picker-button";
    button.innerHTML = `<span><strong>${escapeHtml(list.name)}</strong><small>${(list.games || []).length} giochi</small></span><span>${included ? "✓" : "+"}</span>`;
    button.onclick = () => {
      const games = new Set(list.games || []);
      if (games.has(key)) games.delete(key); else games.add(key);
      list.games = [...games];
      list.updatedAt = new Date().toISOString();
      saveLists();
      openListPicker(game);
    };
    ui.listPickerItems.append(button);
  }
  ui.listPicker.showModal();
}

function matchingPromotions(game) {
  const targetIds = new Set([game.epic_id, game.external_id].filter(Boolean));
  const normalizedTitle = (game.title || "").trim().toLocaleLowerCase("it");
  return [...state.current, ...state.upcoming, ...state.history]
    .map(normalizePromotion)
    .filter((promo) => {
      const idsMatch = [promo.epic_id, promo.external_id].some((id) => id && targetIds.has(id));
      const namespaceMatch = game.namespace && promo.namespace === game.namespace;
      const titleMatch = normalizedTitle && (promo.title || "").trim().toLocaleLowerCase("it") === normalizedTitle;
      return idsMatch || (namespaceMatch && titleMatch) || titleMatch;
    })
    .sort((a, b) => new Date(b.start_date || 0) - new Date(a.start_date || 0));
}

function renderRating(game, entry) {
  ui.gamePageRating.replaceChildren();
  const selected = Number(entry?.rating || 0);
  for (let rating = 1; rating <= 5; rating += 1) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "rating-button";
    button.textContent = rating <= selected ? "★" : "☆";
    button.setAttribute("aria-label", `${rating} stelle`);
    button.onclick = () => {
      const nextRating = selected === rating ? 0 : rating;
      const updatedEntry = setLibraryEntry(game, { rating: nextRating });
      renderRating(game, updatedEntry);
    };
    ui.gamePageRating.append(button);
  }
}

function renderPromotionTimeline(game) {
  const promotions = matchingPromotions(game);
  ui.gamePagePromotions.replaceChildren();
  if (!promotions.length) {
    ui.gamePagePromotions.innerHTML = `<div class="timeline-empty">Nessuna promozione gratuita registrata per questo titolo.</div>`;
    return;
  }
  for (const promo of promotions) {
    const item = document.createElement("article");
    const mode = getMode(promo);
    item.className = `promotion-event promotion-event-${mode}`;
    item.innerHTML = `
      <span class="timeline-dot"></span>
      <div>
        <strong>${escapeHtml(badgeText(promo))}</strong>
        <span>${formatDate(promo.start_date)} → ${formatDate(promo.end_date)}</span>
        <small>${escapeHtml(promo.fmt_original_price || "Prezzo non disponibile")}</small>
      </div>`;
    ui.gamePagePromotions.append(item);
  }
}


function renderStoreOptions(game) {
  ui.gamePageStoreOptions.replaceChildren();
  const listings = listingsForGame(game)
    .filter((listing) => listing?.store_url)
    .sort((a, b) => {
      const priority = { epic: 0, steam: 1, playstation: 2, xbox: 3 };
      return (priority[a.store] ?? 99) - (priority[b.store] ?? 99);
    });

  if (!listings.length) {
    ui.gamePageStoreOptions.innerHTML = '<div class="timeline-empty">Nessuna listing disponibile.</div>';
    return;
  }

  for (const listing of listings) {
    const card = document.createElement("article");
    card.className = `store-option store-option-${listing.store}`;
    const price = listing.fmt_discount_price
      || listing.fmt_original_price
      || (listing.store === "steam" ? "Prezzo su Steam" : "Vedi prezzo");
    const edition = listing.edition_name || listing.title || game.title;
    card.innerHTML = `
      <div class="store-option-logo">${escapeHtml(storeLabel(listing.store).slice(0, 1))}</div>
      <div class="store-option-copy">
        <strong>${escapeHtml(storeLabel(listing.store))}</strong>
        <span>${escapeHtml(edition)}</span>
        <small>${escapeHtml(price)}</small>
      </div>
      <a class="button button-secondary" href="${escapeAttr(listing.store_url)}" target="_blank" rel="noopener noreferrer">
        Apri
      </a>`;
    ui.gamePageStoreOptions.append(card);
  }
}



function formatMinutes(minutes) {
  const value = Math.max(0, Number(minutes) || 0);
  const hours = Math.floor(value / 60);
  const mins = Math.round(value % 60);
  if (!hours) return `${mins} min`;
  return mins ? `${hours} h ${mins} min` : `${hours} h`;
}

function statusLabel(status) {
  return ({
    saved: "In libreria",
    backlog: "Da giocare",
    playing: "In corso",
    paused: "In pausa",
    completed: "Completato",
    abandoned: "Abbandonato",
    replay: "Da rigiocare",
  })[status] || "In libreria";
}

function journalGame(entry) {
  return resolveGameByKey(entry.gameKey) || {
    match_key: entry.gameKey,
    canonical_id: entry.gameKey,
    title: entry.gameTitle,
    image_url: entry.gameImageUrl,
    source_kind: "catalog",
    store: "other",
  };
}

function createDiaryEntryCard(entry, { publicView = false, compact = false } = {}) {
  const game = journalGame(entry);
  const article = document.createElement("article");
  article.className = `diary-entry-card${compact ? " diary-entry-card-compact" : ""}`;
  const note = entry.note
    ? entry.containsSpoilers
      ? `<details class="spoiler-note"><summary>Nota con spoiler</summary><p>${escapeHtml(entry.note)}</p></details>`
      : `<p class="diary-entry-note">${escapeHtml(entry.note)}</p>`
    : "";
  article.innerHTML = `
    <a class="diary-entry-cover" href="${gameRoute(game)}">
      <img src="${escapeAttr(entry.gameImageUrl || game.image_url || PLACEHOLDER)}" alt="">
    </a>
    <div class="diary-entry-body">
      <div class="diary-entry-heading">
        <div>
          <span class="eyebrow">${escapeHtml(formatDate(entry.playedAt))}</span>
          <h3><a href="${gameRoute(game)}">${escapeHtml(entry.gameTitle || game.title)}</a></h3>
        </div>
        <strong>${escapeHtml(formatMinutes(entry.minutesPlayed))}</strong>
      </div>
      <div class="diary-entry-meta">
        ${entry.platform ? `<span>${escapeHtml(entry.platform)}</span>` : ""}
        ${entry.progressPercent !== null && entry.progressPercent !== undefined ? `<span>${Number(entry.progressPercent)}%</span>` : ""}
        <span>${entry.visibility === "public" ? "Pubblica" : "Privata"}</span>
      </div>
      ${note}
    </div>
    ${publicView ? "" : `<button class="diary-entry-delete" type="button" aria-label="Elimina sessione">×</button>`}`;

  if (!publicView) {
    article.querySelector(".diary-entry-delete").onclick = async () => {
      if (!confirm("Eliminare questa sessione dal diario?")) return;
      try {
        await window.VaultJournal.deleteEntry(entry.id);
        showToast("Sessione eliminata.");
        if (state.route.name === "game") void renderGamePage();
        if (state.route.name === "diary") renderDiaryPage();
        if (state.route.name === "stats") void renderStatsPage();
      } catch (error) {
        showToast(error.message || "Eliminazione fallita.");
      }
    };
  }
  return article;
}

function renderGameSessions(game) {
  if (!window.VaultJournal || !ui.gamePageSessions) return;
  const entries = window.VaultJournal.listEntries({ gameKey: gameKey(game), limit: 5 });
  ui.gamePageSessions.replaceChildren();
  if (!entries.length) {
    ui.gamePageSessions.innerHTML = `<div class="timeline-empty">Nessuna sessione registrata per questo gioco.</div>`;
    return;
  }
  entries.forEach((entry) => ui.gamePageSessions.append(createDiaryEntryCard(entry, { compact: true })));
}

function populateDiaryPlatformFilter(entries) {
  const current = ui.diaryPlatformFilter.value || "all";
  const platforms = [...new Set(entries.map((entry) => entry.platform).filter(Boolean))].sort((a, b) => a.localeCompare(b, "it"));
  ui.diaryPlatformFilter.replaceChildren();
  const all = document.createElement("option");
  all.value = "all";
  all.textContent = "Tutte";
  ui.diaryPlatformFilter.append(all);
  platforms.forEach((platform) => {
    const option = document.createElement("option");
    option.value = platform;
    option.textContent = platform;
    ui.diaryPlatformFilter.append(option);
  });
  ui.diaryPlatformFilter.value = platforms.includes(current) ? current : "all";
}

function renderDiaryPage() {
  updateDocumentTitle("Diario di gioco");
  if (!window.VaultJournal) return;
  const allEntries = window.VaultJournal.listEntries();
  populateDiaryPlatformFilter(allEntries);

  const query = (ui.diarySearch.value || "").trim().toLocaleLowerCase("it");
  const platform = ui.diaryPlatformFilter.value || "all";
  const month = ui.diaryMonthFilter.value || "";
  const entries = allEntries.filter((entry) => {
    const searchText = `${entry.gameTitle || ""} ${entry.note || ""}`.toLocaleLowerCase("it");
    return (!query || searchText.includes(query))
      && (platform === "all" || entry.platform === platform)
      && (!month || String(entry.playedAt || "").startsWith(month));
  });

  const summary = window.VaultJournal.summarize();
  const currentMonth = new Date().toISOString().slice(0, 7);
  const currentMonthMinutes = allEntries
    .filter((entry) => String(entry.playedAt || "").startsWith(currentMonth))
    .reduce((sum, entry) => sum + Number(entry.minutesPlayed || 0), 0);
  ui.diaryStatSessions.textContent = allEntries.length;
  ui.diaryStatHours.textContent = formatMinutes(summary.sessionMinutes);
  ui.diaryStatGames.textContent = new Set(allEntries.map((entry) => entry.gameKey)).size;
  ui.diaryStatMonth.textContent = formatMinutes(currentMonthMinutes);

  ui.diaryEntryList.replaceChildren();
  ui.diaryEmpty.hidden = Boolean(entries.length);
  entries.forEach((entry) => ui.diaryEntryList.append(createDiaryEntryCard(entry)));
}

function renderBreakdown(container, rows, total, labeler = (value) => value) {
  container.replaceChildren();
  if (!rows.length) {
    container.innerHTML = `<div class="timeline-empty">Dati non ancora disponibili.</div>`;
    return;
  }
  for (const [label, value] of rows) {
    const percent = total ? Math.max(2, Math.round((value / total) * 100)) : 0;
    const row = document.createElement("div");
    row.className = "breakdown-row";
    row.innerHTML = `<div><strong>${escapeHtml(labeler(label))}</strong><span>${escapeHtml(formatMinutes(value))}</span></div><div class="breakdown-track"><span style="width:${percent}%"></span></div>`;
    container.append(row);
  }
}

async function renderStatsPage() {
  updateDocumentTitle("Statistiche personali");
  if (!window.VaultJournal) return;
  let ownedListings = [];
  try {
    if (state.auth.user && window.VaultSteam) ownedListings = await window.VaultSteam.getOwnedListings();
  } catch (error) {
    console.warn("Statistiche Steam non disponibili", error);
  }
  if (state.route.name !== "stats") return;

  const summary = window.VaultJournal.summarize({ ownedListings });
  ui.statsTotalHours.textContent = formatMinutes(summary.sessionMinutes);
  ui.statsSteamHours.textContent = `Steam: ${formatMinutes(summary.steamMinutes)}`;
  ui.statsCompleted.textContent = summary.completed;
  ui.statsCompletionRate.textContent = `${summary.completionRate}% dei giochi iniziati`;
  ui.statsBacklog.textContent = summary.backlog;
  ui.statsSessions.textContent = summary.sessions;

  ui.statsMonthlyChart.replaceChildren();
  const lastMonths = [];
  const cursor = new Date();
  cursor.setDate(1);
  for (let offset = 11; offset >= 0; offset -= 1) {
    const date = new Date(cursor.getFullYear(), cursor.getMonth() - offset, 1);
    lastMonths.push(date.toISOString().slice(0, 7));
  }
  const monthlyMap = new Map(summary.monthly);
  const maxMinutes = Math.max(1, ...lastMonths.map((month) => monthlyMap.get(month) || 0));
  lastMonths.forEach((month) => {
    const minutes = monthlyMap.get(month) || 0;
    const date = new Date(`${month}-01T12:00:00`);
    const item = document.createElement("div");
    item.className = "month-bar-item";
    item.innerHTML = `<span class="month-bar-value">${minutes ? formatMinutes(minutes) : ""}</span><div class="month-bar"><span style="height:${Math.max(minutes ? 5 : 0, Math.round((minutes / maxMinutes) * 100))}%"></span></div><small>${new Intl.DateTimeFormat("it-IT", { month: "short" }).format(date)}</small>`;
    ui.statsMonthlyChart.append(item);
  });

  renderBreakdown(ui.statsPlatforms, summary.platforms, summary.sessionMinutes);

  const statusRows = Object.entries(summary.statusCounts).sort((a, b) => b[1] - a[1]);
  ui.statsStatuses.replaceChildren();
  if (!statusRows.length) {
    ui.statsStatuses.innerHTML = `<div class="timeline-empty">Aggiungi progressi ai giochi della libreria.</div>`;
  } else {
    const total = statusRows.reduce((sum, [, count]) => sum + count, 0);
    statusRows.forEach(([status, count]) => {
      const row = document.createElement("div");
      row.className = "status-stat-row";
      row.innerHTML = `<span>${escapeHtml(statusLabel(status))}</span><strong>${count}</strong><div class="breakdown-track"><span style="width:${Math.round((count / total) * 100)}%"></span></div>`;
      ui.statsStatuses.append(row);
    });
  }

  ui.statsTopGames.replaceChildren();
  if (!summary.topGames.length) {
    ui.statsTopGames.innerHTML = `<div class="timeline-empty">Registra sessioni per costruire la classifica.</div>`;
  } else {
    summary.topGames.forEach((game) => {
      const link = document.createElement("a");
      link.className = "top-game-row";
      link.href = `#/game/${encodeURIComponent(game.gameKey)}`;
      link.innerHTML = `<img src="${escapeAttr(game.gameImageUrl || PLACEHOLDER)}" alt=""><span><strong>${escapeHtml(game.gameTitle)}</strong><small>${game.sessions} sessioni</small></span><b>${escapeHtml(formatMinutes(game.minutes))}</b>`;
      ui.statsTopGames.append(link);
    });
  }
}

function renderDiscoveryCards(container, games, { showReasons = false } = {}) {
  container.replaceChildren();
  for (const game of games || []) {
    registerCatalogGame(game);
    const fragment = renderCard(game);
    if (showReasons) {
      const card = fragment.querySelector(".game-card");
      const actions = card?.querySelector(".card-actions");
      const reasons = Array.isArray(game.reasons) ? game.reasons.filter(Boolean).slice(0, 2) : [];
      if (card && actions && (reasons.length || game.recommendation_confidence)) {
        const explanation = document.createElement("div");
        explanation.className = "recommendation-explanation";
        const confidence = Number(game.recommendation_confidence || 0);
        explanation.innerHTML = `
          <div class="recommendation-explanation-head">
            <strong>Perché te lo consigliamo</strong>
            ${confidence ? `<span>${confidence}% affinità</span>` : ""}
          </div>
          ${reasons.map((reason) => `<p>${escapeHtml(reason)}</p>`).join("")}`;
        actions.before(explanation);
      }
    }
    container.append(fragment);
  }
}

function createDiscoverySection({
  title,
  subtitle,
  description = "",
  games,
  actionHref = "#/catalog",
  actionLabel = "Vedi tutto",
  showReasons = false,
}) {
  const section = document.createElement("section");
  section.className = "discovery-section";
  section.innerHTML = `
    <header class="discovery-section-header">
      <div>
        <p class="eyebrow">${escapeHtml(subtitle || "DISCOVER")}</p>
        <h2>${escapeHtml(title)}</h2>
        ${description ? `<p class="discovery-section-description">${escapeHtml(description)}</p>` : ""}
      </div>
      <a class="discovery-section-link" href="${escapeAttr(actionHref)}">${escapeHtml(actionLabel)} →</a>
    </header>
    <div class="discovery-game-strip"></div>`;
  const grid = section.querySelector(".discovery-game-strip");
  if (!games?.length) {
    grid.innerHTML = `<div class="timeline-empty">Nessun gioco disponibile in questa sezione.</div>`;
  } else {
    renderDiscoveryCards(grid, games, { showReasons });
  }
  return section;
}

function discoveryEntryWeight(entry) {
  if (!entry?.game) return 0;
  const statusWeight = {
    completed: 7,
    replay: 5,
    playing: 3,
    paused: 1,
    backlog: 1,
    abandoned: -8,
    saved: 0.5,
  }[entry.status || "saved"] || 0;
  const rating = Number(entry.rating || 0);
  const ratingWeight = rating >= 4 ? (rating - 2) * 2 : rating > 0 && rating <= 2 ? -4 : 0;
  const playtime = Math.max(0, Number(entry.steamPlaytimeMinutes || 0));
  return statusWeight + ratingWeight + (entry.favorite ? 6 : 0) + Math.min(4, Math.log1p(playtime / 60));
}

function preferredDiscoverySeeds(limit = 3) {
  return Object.values(state.library)
    .filter((entry) => entry?.game && discoveryEntryWeight(entry) > 1)
    .sort((a, b) => {
      const scoreDelta = discoveryEntryWeight(b) - discoveryEntryWeight(a);
      if (scoreDelta) return scoreDelta;
      return String(b.updatedAt || b.addedAt || "").localeCompare(String(a.updatedAt || a.addedAt || ""));
    })
    .slice(0, limit);
}

async function getHeuristicDiscoveryRecommendations({ force = false, limit = 12 } = {}) {
  const seeds = preferredDiscoverySeeds(3);
  if (!seeds.length) {
    return {
      mode: state.auth.user ? "cold_start" : "signed_out",
      profile: { positive_signals: 0, negative_signals: 0, similar_users: 0, top_genres: [], top_developers: [] },
      items: [],
    };
  }

  const groups = await Promise.all(seeds.map(async (entry) => ({
    entry,
    games: await window.VaultCatalog.getRelated(gameKey(entry.game), { force, limit: 12 }),
  })));
  const ranked = new Map();

  for (const { entry, games } of groups) {
    const seed = entry.game;
    const seedKey = gameKey(seed);
    const seedWeight = Math.max(1, discoveryEntryWeight(entry));
    for (const game of games || []) {
      const key = gameKey(game);
      if (!key || key === seedKey || getLibraryEntry(game)) continue;
      const current = ranked.get(key) || { game: { ...game }, score: 0, seeds: [] };
      current.score += seedWeight + Number(game.relation_score || 0);
      if (!current.seeds.includes(seed.title)) current.seeds.push(seed.title);
      ranked.set(key, current);
    }
  }

  const items = [...ranked.values()]
    .sort((a, b) => b.score - a.score || String(a.game.title).localeCompare(String(b.game.title), "it"))
    .slice(0, limit)
    .map(({ game, score, seeds: matchedSeeds }) => ({
      ...game,
      recommendation_score: score,
      recommendation_confidence: Math.min(95, Math.max(35, Math.round(45 + score))),
      reasons: [
        matchedSeeds.length >= 2
          ? `Perché hai apprezzato ${matchedSeeds[0]} e ${matchedSeeds[1]}`
          : `Perché hai apprezzato ${matchedSeeds[0]}`,
      ],
    }));

  return {
    mode: "local_heuristic",
    profile: {
      positive_signals: seeds.length,
      negative_signals: Object.values(state.library).filter((entry) => discoveryEntryWeight(entry) < 0).length,
      similar_users: 0,
      top_genres: [],
      top_developers: [],
    },
    items,
  };
}

function recommendationDescription(data) {
  const profile = data?.profile || {};
  if (data?.mode === "personalized") {
    const parts = [`${Number(profile.positive_signals || 0)} segnali positivi`];
    if (Number(profile.negative_signals || 0)) parts.push(`${Number(profile.negative_signals)} segnali negativi`);
    if (Number(profile.similar_users || 0)) parts.push(`${Number(profile.similar_users)} utenti affini`);
    return `Ranking aggiornato usando ${parts.join(", ")}.`;
  }
  if (data?.mode === "local_heuristic") {
    return "Suggerimenti combinati dai giochi più apprezzati nella tua libreria locale.";
  }
  return "Aggiungi giochi, preferiti, voti e progressi per costruire un profilo dei tuoi gusti.";
}

function createRecommendationEmptyState() {
  const panel = document.createElement("section");
  panel.className = "recommendation-empty-panel";
  const signedIn = Boolean(state.auth.user);
  panel.innerHTML = `
    <div>
      <p class="eyebrow">PER TE</p>
      <h2>${signedIn ? "Il tuo profilo dei gusti è ancora vuoto" : "Attiva le raccomandazioni personali"}</h2>
      <p>${signedIn
        ? "Salva e valuta alcuni giochi, aggiorna i progressi o registra sessioni nel diario. Il ranking inizierà a distinguere ciò che apprezzi da ciò che abbandoni."
        : "Accedi e usa libreria, preferiti, voti e diario per ottenere un ordinamento diverso per il tuo account."}</p>
    </div>
    <a class="button button-secondary" href="${signedIn ? "#/catalog" : "#/login"}">${signedIn ? "Esplora il catalogo" : "Accedi"}</a>`;
  return panel;
}

async function renderDiscoveryPage({ force = false } = {}) {
  updateDocumentTitle("Scopri giochi");
  ui.discoverySections.replaceChildren();
  ui.discoveryStatus.hidden = true;

  if (!window.VaultCatalog?.configured()) {
    ui.discoveryStatus.textContent = "Configura Supabase per usare le sezioni di scoperta.";
    ui.discoveryStatus.hidden = false;
    return;
  }

  if (state.discoveryLoading) return;
  state.discoveryLoading = true;
  ui.discoverySections.innerHTML = `<div class="route-loading">Preparazione dei suggerimenti…</div>`;

  try {
    const data = await window.VaultCatalog.getDiscovery({ force, limit: 12 });
    if (state.route.name !== "discover") return;
    state.discoveryData = data;

    let recommendations = null;
    if (state.auth.user && window.VaultCatalog.getRecommendations) {
      try {
        recommendations = await window.VaultCatalog.getRecommendations({ force, limit: 12 });
      } catch (error) {
        console.warn("Ranking personale server non disponibile; uso fallback locale.", error);
      }
    }
    if (!recommendations?.items?.length) {
      recommendations = await getHeuristicDiscoveryRecommendations({ force, limit: 12 });
    }
    state.discoveryRecommendations = recommendations;

    if (state.route.name !== "discover") return;
    ui.discoverySections.replaceChildren();

    if (recommendations?.items?.length) {
      ui.discoverySections.append(createDiscoverySection({
        title: "Per te",
        subtitle: recommendations.mode === "personalized" ? "RANKING PERSONALE" : "DALLA TUA LIBRERIA",
        description: recommendationDescription(recommendations),
        games: recommendations.items,
        actionHref: state.auth.user ? "#/profile" : "#/login",
        actionLabel: state.auth.user ? "Apri profilo" : "Accedi",
        showReasons: true,
      }));
    } else {
      ui.discoverySections.append(createRecommendationEmptyState());
    }

    ui.discoverySections.append(
      createDiscoverySection({
        title: "Nuove uscite",
        subtitle: "APPENA ARRIVATI",
        games: data.recent,
        actionHref: "#/catalog",
        actionLabel: "Catalogo",
      }),
      createDiscoverySection({
        title: "Più apprezzati dalla community",
        subtitle: "VOTI PUBBLICI",
        games: data.communityTop,
        actionHref: "#/feed",
        actionLabel: "Feed",
      }),
      createDiscoverySection({
        title: "I più recensiti",
        subtitle: "COMMUNITY",
        games: data.mostReviewed,
        actionHref: "#/feed",
        actionLabel: "Recensioni",
      }),
      createDiscoverySection({
        title: "Disponibili su Epic e Steam",
        subtitle: "MULTI-STORE",
        games: data.multiStore,
        actionHref: "#/catalog",
        actionLabel: "Confronta store",
      }),
      createDiscoverySection({
        title: "Indie da scoprire",
        subtitle: "SPOTLIGHT",
        games: data.indie,
        actionHref: "#/catalog",
        actionLabel: "Esplora indie",
      }),
    );
  } catch (error) {
    console.error("Caricamento discovery fallito", error);
    ui.discoverySections.replaceChildren();
    ui.discoveryStatus.textContent = "Le sezioni di scoperta non sono disponibili. Verifica le migrazioni v4.4 e v4.7.";
    ui.discoveryStatus.hidden = false;
  } finally {
    state.discoveryLoading = false;
  }
}

function renderEntityPage() {
  const data = state.entityData;
  const kind = state.route.params.kind === "publisher" ? "publisher" : "developer";
  const label = kind === "publisher" ? "PUBLISHER" : "SVILUPPATORE";
  const name = state.route.params.name || data?.name || "Catalogo";

  ui.entityKind.textContent = label;
  ui.entityTitle.textContent = name;
  updateDocumentTitle(name);
  ui.entityGames.replaceChildren();

  if (!data?.items?.length) {
    if (state.entityLoading) {
      ui.entityGames.innerHTML = `<div class="route-loading">Caricamento giochi…</div>`;
    } else {
      ui.entityGames.innerHTML = `<div class="empty-state"><strong>Nessun gioco trovato</strong><span>Il catalogo non contiene ancora titoli associati a questo ${kind === "publisher" ? "publisher" : "sviluppatore"}.</span></div>`;
    }
  } else {
    for (const game of data.items) {
      registerCatalogGame(game);
      ui.entityGames.append(renderCard(game));
    }
  }

  const shown = data?.items?.length || 0;
  const total = Number(data?.total || 0);
  ui.entityMeta.textContent = total
    ? `${total.toLocaleString("it-IT")} giochi nel catalogo multi-store`
    : state.entityLoading ? "Caricamento…" : "Nessun gioco disponibile";
  ui.entityPageSummary.textContent = total
    ? `${shown.toLocaleString("it-IT")} di ${total.toLocaleString("it-IT")} giochi`
    : "";
  ui.entityPagination.hidden = total === 0;
  ui.entityLoadMore.hidden = shown >= total;
  ui.entityLoadMore.disabled = state.entityLoading;
  ui.entityLoadMore.textContent = state.entityLoading ? "Caricamento…" : "Carica altri giochi";
}

async function loadEntityPage({ reset = true, force = false } = {}) {
  if (state.route.name !== "entity") return;
  if (!window.VaultCatalog?.configured()) {
    ui.entityStatus.textContent = "Configura Supabase per aprire le pagine sviluppatore e publisher.";
    ui.entityStatus.hidden = false;
    return;
  }

  const requestId = ++state.entityRequestId;
  const kind = state.route.params.kind === "publisher" ? "publisher" : "developer";
  const name = state.route.params.name || "";
  const offset = reset ? 0 : (state.entityData?.items?.length || 0);

  state.entityLoading = true;
  if (reset) state.entityData = { kind, name, total: 0, items: [], limit: 36, offset: 0 };
  ui.entityStatus.hidden = true;
  renderEntityPage();

  try {
    const response = await window.VaultCatalog.getEntity(kind, name, {
      limit: 36,
      offset,
      force,
    });
    if (requestId !== state.entityRequestId || state.route.name !== "entity") return;

    if (reset) {
      state.entityData = response;
    } else {
      const merged = new Map((state.entityData?.items || []).map((game) => [gameKey(game), game]));
      for (const game of response.items) merged.set(gameKey(game), game);
      state.entityData = { ...response, items: [...merged.values()] };
    }
  } catch (error) {
    console.error("Caricamento pagina catalogo entity fallito", error);
    if (requestId !== state.entityRequestId) return;
    ui.entityStatus.textContent = "Pagina temporaneamente non disponibile. Verifica la migrazione v4.4.";
    ui.entityStatus.hidden = false;
  } finally {
    if (requestId === state.entityRequestId) {
      state.entityLoading = false;
      renderEntityPage();
    }
  }
}

async function renderRelatedGames(game) {
  ui.gameRelatedGrid.replaceChildren();
  ui.gameRelatedStatus.textContent = "Caricamento suggerimenti…";
  ui.gameRelatedStatus.hidden = false;
  ui.gameRelatedSection.hidden = false;

  if (!window.VaultCatalog?.configured() || game.source_kind !== "catalog") {
    ui.gameRelatedSection.hidden = true;
    ui.gameEditorialMemberships.hidden = true;
    return;
  }

  const expectedKey = gameKey(game);
  try {
    const related = await window.VaultCatalog.getRelated(expectedKey, { limit: 12 });
    const routed = state.route.name === "game" ? resolveGameByKey(state.route.params.key) : null;
    if (!routed || gameKey(routed) !== expectedKey) return;

    const filtered = related.filter((candidate) => gameKey(candidate) !== expectedKey);
    ui.gameRelatedGrid.replaceChildren();
    if (!filtered.length) {
      ui.gameRelatedStatus.textContent = "Non ci sono ancora suggerimenti sufficienti per questo titolo.";
      return;
    }
    ui.gameRelatedStatus.hidden = true;
    renderDiscoveryCards(ui.gameRelatedGrid, filtered);
  } catch (error) {
    console.error("Caricamento giochi correlati fallito", error);
    ui.gameRelatedStatus.textContent = "Suggerimenti temporaneamente non disponibili.";
  }
}


const FRANCHISE_RELATION_LABELS = {
  main: "Giochi principali",
  spin_off: "Spin-off",
  remake: "Remake",
  remaster: "Remaster",
  dlc: "DLC",
  expansion: "Espansioni",
  other: "Altri titoli",
};

function editorialCard({ title, description, imageUrl, count, href, badge }) {
  const article = document.createElement("article");
  article.className = "editorial-directory-card";
  article.innerHTML = `
    <a class="editorial-card-cover" href="${escapeAttr(href)}">
      <img src="${escapeAttr(imageUrl || PLACEHOLDER)}" alt="" loading="lazy">
      <span class="editorial-card-scrim"></span>
      <span class="official-badge">${escapeHtml(badge)}</span>
    </a>
    <div class="editorial-card-copy">
      <h3><a href="${escapeAttr(href)}">${escapeHtml(title)}</a></h3>
      <p>${escapeHtml(description || "Descrizione editoriale in preparazione.")}</p>
      <div><span>${Number(count || 0).toLocaleString("it-IT")} giochi</span><a href="${escapeAttr(href)}">Apri →</a></div>
    </div>`;
  const image = article.querySelector("img");
  image.onerror = () => { image.src = PLACEHOLDER; };
  return article;
}

async function renderEditorialDirectory() {
  const requestId = ++state.editorialRequestId;
  updateDocumentTitle("Franchise e collezioni");
  ui.editorialDirectoryStatus.hidden = true;
  ui.franchiseDirectoryGrid.innerHTML = `<div class="route-loading">Caricamento franchise…</div>`;
  ui.collectionDirectoryGrid.innerHTML = `<div class="route-loading">Caricamento collezioni…</div>`;
  try {
    if (!window.VaultFranchises) throw new Error("Modulo franchise non disponibile.");
    const directory = await window.VaultFranchises.getDirectory();
    if (requestId !== state.editorialRequestId || state.route.name !== "editorial-directory") return;
    state.editorialDirectory = directory || { franchises: [], collections: [] };
    ui.franchiseDirectoryGrid.replaceChildren();
    ui.collectionDirectoryGrid.replaceChildren();

    for (const franchise of state.editorialDirectory.franchises || []) {
      ui.franchiseDirectoryGrid.append(editorialCard({
        title: franchise.name,
        description: franchise.description,
        imageUrl: franchise.hero_image_url,
        count: franchise.game_count,
        href: franchiseRoute(franchise.slug),
        badge: "FRANCHISE",
      }));
    }
    for (const collection of state.editorialDirectory.collections || []) {
      ui.collectionDirectoryGrid.append(editorialCard({
        title: collection.title,
        description: collection.description,
        imageUrl: collection.cover_image_url,
        count: collection.game_count,
        href: editorialCollectionRoute(collection.slug),
        badge: "COLLEZIONE UFFICIALE",
      }));
    }

    if (!(state.editorialDirectory.franchises || []).length) {
      ui.franchiseDirectoryGrid.innerHTML = `<div class="empty-state"><strong>Nessun franchise pubblicato</strong><span>Le saghe vengono preparate dagli amministratori.</span></div>`;
    }
    if (!(state.editorialDirectory.collections || []).length) {
      ui.collectionDirectoryGrid.innerHTML = `<div class="empty-state"><strong>Nessuna collezione pubblicata</strong><span>Le selezioni editoriali appariranno qui.</span></div>`;
    }
  } catch (error) {
    console.error("Directory editoriale non disponibile", error);
    if (requestId !== state.editorialRequestId) return;
    ui.editorialDirectoryStatus.textContent = "Archivio editoriale non disponibile. Applica la migrazione v4.6 su Supabase.";
    ui.editorialDirectoryStatus.hidden = false;
    ui.franchiseDirectoryGrid.replaceChildren();
    ui.collectionDirectoryGrid.replaceChildren();
  }
}

function franchiseGameProgress(game) {
  const progress = window.VaultJournal?.getProgress(gameKey(game));
  const library = getLibraryEntry(game);
  return {
    status: progress?.status || library?.status || null,
    percent: Number(progress?.progressPercent ?? library?.progressPercent ?? 0),
  };
}

function renderFranchiseProgress(games) {
  const items = games || [];
  if (!items.length) {
    ui.franchiseProgress.hidden = true;
    return;
  }
  let completed = 0;
  let started = 0;
  let totalPercent = 0;
  for (const game of items) {
    const progress = franchiseGameProgress(game);
    const isCompleted = progress.status === "completed";
    if (isCompleted) completed += 1;
    if (["playing", "paused", "completed", "abandoned", "replay"].includes(progress.status)) started += 1;
    totalPercent += isCompleted ? 100 : Math.max(0, Math.min(100, progress.percent || 0));
  }
  const average = Math.round(totalPercent / items.length);
  ui.franchiseProgressCompleted.textContent = `${completed}/${items.length}`;
  ui.franchiseProgressStarted.textContent = String(started);
  ui.franchiseProgressPercent.textContent = `${average}%`;
  ui.franchiseProgressFill.style.width = `${average}%`;
  ui.franchiseProgress.hidden = false;
}

function franchiseOrderValue(game) {
  if (state.franchiseOrder === "narrative") {
    return Number(game.narrative_order || 100000 + Number(game.release_order || 0));
  }
  return Number(game.release_order || 100000);
}

function renderFranchiseGameRow(game) {
  const progress = franchiseGameProgress(game);
  const row = document.createElement("article");
  row.className = "franchise-game-row";
  row.innerHTML = `
    <button class="franchise-game-cover" type="button"><img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt=""></button>
    <div class="franchise-game-copy">
      <div class="franchise-game-heading">
        <div><small>${escapeHtml(game.developer || game.publisher || "")}</small><h3>${escapeHtml(game.title)}</h3></div>
        <span class="pill">${escapeHtml(game.release_year || "Anno n/d")}</span>
      </div>
      <div class="franchise-game-orders">
        <span>Uscita #${Number(game.release_order || 0)}</span>
        ${game.narrative_order ? `<span>Narrativa #${Number(game.narrative_order)}</span>` : `<span>Narrativa non definita</span>`}
        ${progress.status ? `<span>${escapeHtml(statusLabel(progress.status))} · ${Math.max(0, Math.min(100, progress.percent || 0))}%</span>` : `<span>Non iniziato</span>`}
      </div>
      ${game.franchise_note ? `<p>${escapeHtml(game.franchise_note)}</p>` : ""}
      <div class="franchise-game-actions"><a class="button button-secondary" href="${escapeAttr(gameRoute(game))}">Scheda</a><button class="button button-secondary" data-saga-library type="button">${getLibraryEntry(game) ? "Rimuovi dalla libreria" : "Aggiungi alla libreria"}</button></div>
    </div>`;
  row.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
  row.querySelector(".franchise-game-cover").onclick = () => navigate(gameRoute(game));
  row.querySelector("[data-saga-library]").onclick = () => {
    toggleLibraryWithoutRerender(game);
    renderFranchiseSections();
    renderFranchiseProgress(state.franchiseData?.games || []);
  };
  return row;
}

function renderFranchiseSections() {
  const games = [...(state.franchiseData?.games || [])].sort((a, b) => {
    const order = franchiseOrderValue(a) - franchiseOrderValue(b);
    return order || String(a.title || "").localeCompare(String(b.title || ""), "it");
  });
  ui.franchiseSections.replaceChildren();
  if (!games.length) {
    ui.franchiseSections.innerHTML = `<div class="empty-state"><strong>Saga in preparazione</strong><span>I giochi verranno collegati dal pannello amministrativo.</span></div>`;
    return;
  }
  const relationOrder = ["main", "spin_off", "remake", "remaster", "expansion", "dlc", "other"];
  for (const relation of relationOrder) {
    const relationGames = games.filter((game) => (game.relation_type || "other") === relation);
    if (!relationGames.length) continue;
    const section = document.createElement("section");
    section.className = "franchise-group";
    section.innerHTML = `<header><div><p class="eyebrow">${escapeHtml(relation.replaceAll("_", " ").toUpperCase())}</p><h2>${escapeHtml(FRANCHISE_RELATION_LABELS[relation])}</h2></div><span>${relationGames.length}</span></header>`;
    const list = document.createElement("div");
    list.className = "franchise-game-list";
    for (const game of relationGames) list.append(renderFranchiseGameRow(game));
    section.append(list);
    ui.franchiseSections.append(section);
  }
}

async function renderFranchisePage() {
  const requestId = ++state.editorialRequestId;
  const slug = state.route.params.slug;
  state.franchiseOrder = "release";
  $$('[data-franchise-order]').forEach((button) => button.classList.toggle("is-active", button.dataset.franchiseOrder === "release"));
  updateDocumentTitle("Caricamento franchise");
  ui.franchiseTitle.textContent = "Caricamento…";
  ui.franchiseDescription.textContent = "Recupero la cronologia della saga.";
  ui.franchiseStatus.hidden = true;
  ui.franchiseSections.innerHTML = `<div class="route-loading">Caricamento saga…</div>`;
  ui.franchiseProgress.hidden = true;
  try {
    const data = await window.VaultFranchises.getFranchise(slug);
    if (requestId !== state.editorialRequestId || state.route.name !== "franchise" || state.route.params.slug !== slug) return;
    if (!data?.franchise) throw new Error("Franchise non trovato.");
    state.franchiseData = data;
    for (const game of data.games || []) registerCatalogGame(game);
    const franchise = data.franchise;
    updateDocumentTitle(franchise.name);
    ui.franchiseTitle.textContent = franchise.name;
    ui.franchiseDescription.textContent = franchise.description || "Descrizione editoriale in preparazione.";
    ui.franchiseMeta.innerHTML = `<span>${Number((data.games || []).length).toLocaleString("it-IT")} titoli</span><span>Ordine di uscita e narrativo</span>`;
    ui.franchiseHeroImage.hidden = !franchise.hero_image_url;
    if (franchise.hero_image_url) {
      ui.franchiseHeroImage.src = franchise.hero_image_url;
      ui.franchiseHeroImage.alt = franchise.name;
      ui.franchiseHeroImage.onerror = () => { ui.franchiseHeroImage.hidden = true; };
    }
    renderFranchiseProgress(data.games || []);
    renderFranchiseSections();
  } catch (error) {
    console.error("Franchise non disponibile", error);
    if (requestId !== state.editorialRequestId) return;
    updateDocumentTitle("Franchise non trovato");
    ui.franchiseTitle.textContent = "Franchise non disponibile";
    ui.franchiseDescription.textContent = "La saga richiesta non è pubblicata oppure la migrazione v4.6 non è stata applicata.";
    ui.franchiseStatus.textContent = error.message || "Franchise non disponibile.";
    ui.franchiseStatus.hidden = false;
    ui.franchiseSections.replaceChildren();
  }
}

function renderCollectionGameRow(game) {
  const row = document.createElement("article");
  row.className = "collection-game-row";
  row.innerHTML = `
    <span class="collection-position">${Number(game.collection_position || 0)}</span>
    <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
    <div><small>${escapeHtml(game.developer || game.publisher || "")}</small><h2><a href="${escapeAttr(gameRoute(game))}">${escapeHtml(game.title)}</a></h2>${game.editorial_note ? `<p>${escapeHtml(game.editorial_note)}</p>` : ""}</div>
    <a class="button button-secondary" href="${escapeAttr(gameRoute(game))}">Apri scheda</a>`;
  row.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
  return row;
}

async function renderEditorialCollectionPage() {
  const requestId = ++state.editorialRequestId;
  const slug = state.route.params.slug;
  updateDocumentTitle("Caricamento collezione");
  ui.editorialCollectionTitle.textContent = "Caricamento…";
  ui.editorialCollectionDescription.textContent = "Recupero la selezione editoriale.";
  ui.editorialCollectionStatus.hidden = true;
  ui.editorialCollectionGames.innerHTML = `<div class="route-loading">Caricamento collezione…</div>`;
  try {
    const data = await window.VaultFranchises.getCollection(slug);
    if (requestId !== state.editorialRequestId || state.route.name !== "editorial-collection" || state.route.params.slug !== slug) return;
    if (!data?.collection) throw new Error("Collezione non trovata.");
    state.collectionData = data;
    for (const game of data.games || []) registerCatalogGame(game);
    const collection = data.collection;
    updateDocumentTitle(collection.title);
    ui.editorialCollectionTitle.textContent = collection.title;
    ui.editorialCollectionDescription.textContent = collection.description || "Descrizione editoriale in preparazione.";
    ui.editorialCollectionMeta.innerHTML = `<span>${Number((data.games || []).length).toLocaleString("it-IT")} giochi</span><span>Selezione ufficiale The Free Vault</span>`;
    ui.editorialCollectionCuratorNote.hidden = !collection.curator_note;
    ui.editorialCollectionCuratorNote.textContent = collection.curator_note || "";
    ui.editorialCollectionImage.hidden = !collection.cover_image_url;
    if (collection.cover_image_url) {
      ui.editorialCollectionImage.src = collection.cover_image_url;
      ui.editorialCollectionImage.alt = collection.title;
      ui.editorialCollectionImage.onerror = () => { ui.editorialCollectionImage.hidden = true; };
    }
    ui.editorialCollectionGames.replaceChildren();
    for (const game of data.games || []) ui.editorialCollectionGames.append(renderCollectionGameRow(game));
    if (!(data.games || []).length) {
      ui.editorialCollectionGames.innerHTML = `<div class="empty-state"><strong>Collezione in preparazione</strong><span>I giochi verranno aggiunti dagli amministratori.</span></div>`;
    }
  } catch (error) {
    console.error("Collezione editoriale non disponibile", error);
    if (requestId !== state.editorialRequestId) return;
    updateDocumentTitle("Collezione non trovata");
    ui.editorialCollectionTitle.textContent = "Collezione non disponibile";
    ui.editorialCollectionDescription.textContent = "La selezione richiesta non è pubblicata oppure la migrazione v4.6 non è stata applicata.";
    ui.editorialCollectionStatus.textContent = error.message || "Collezione non disponibile.";
    ui.editorialCollectionStatus.hidden = false;
    ui.editorialCollectionGames.replaceChildren();
  }
}

async function renderGameEditorialMemberships(game) {
  ui.gameEditorialMemberships.hidden = true;
  ui.gameEditorialMembershipLinks.replaceChildren();
  if (!window.VaultFranchises || game.source_kind !== "catalog") return;
  const expectedKey = gameKey(game);
  try {
    const memberships = await window.VaultFranchises.getMemberships(expectedKey);
    const routed = state.route.name === "game" ? resolveGameByKey(state.route.params.key) : null;
    if (!routed || gameKey(routed) !== expectedKey) return;
    const links = [];
    for (const franchise of memberships?.franchises || []) {
      links.push(`<a href="${escapeAttr(franchiseRoute(franchise.slug))}"><span>Franchise</span><strong>${escapeHtml(franchise.name)}</strong><small>${escapeHtml(FRANCHISE_RELATION_LABELS[franchise.relation_type] || franchise.relation_type)}</small></a>`);
    }
    for (const collection of memberships?.collections || []) {
      links.push(`<a href="${escapeAttr(editorialCollectionRoute(collection.slug))}"><span>Collezione ufficiale</span><strong>${escapeHtml(collection.title)}</strong><small>Posizione #${Number(collection.position || 0)}</small></a>`);
    }
    if (!links.length) return;
    ui.gameEditorialMembershipLinks.innerHTML = links.join("");
    ui.gameEditorialMemberships.hidden = false;
  } catch (error) {
    console.warn("Appartenenze editoriali non disponibili", error);
  }
}

async function renderGamePage() {
  let game = resolveGameByKey(state.route.params.key);
  if (!game && window.VaultCatalog?.configured()) {
    updateDocumentTitle("Caricamento gioco");
    ui.gamePageTitle.textContent = "Caricamento…";
    ui.gamePageDescription.textContent = "Recupero la scheda dal catalogo.";
    ui.gamePageImage.src = PLACEHOLDER;
    ui.gamePageMeta.replaceChildren();
    ui.gamePagePromotions.replaceChildren();
    try {
      game = await window.VaultCatalog.getGame(state.route.params.key);
      if (game) registerCatalogGame(game);
    } catch (error) {
      console.error("Caricamento scheda gioco fallito", error);
    }
  }
  if (!game || state.route.name !== "game") {
    updateDocumentTitle("Gioco non trovato");
    ui.gamePageTitle.textContent = "Gioco non trovato";
    ui.gamePageDescription.textContent = "Il titolo richiesto non è disponibile nel catalogo.";
    ui.gamePageImage.src = PLACEHOLDER;
    ui.gamePageMeta.replaceChildren();
    ui.gamePagePromotions.replaceChildren();
    ui.gameRelatedSection.hidden = true;
    return;
  }

  const entry = getLibraryEntry(game);
  const journalProgress = window.VaultJournal?.getProgress(gameKey(game)) || null;
  const journalEntries = window.VaultJournal?.listEntries({ gameKey: gameKey(game) }) || [];
  const sessionMinutes = journalEntries.reduce((sum, item) => sum + Number(item.minutesPlayed || 0), 0);
  updateDocumentTitle(game.title);
  ui.gamePageImage.src = game.image_url || PLACEHOLDER;
  ui.gamePageImage.alt = `Immagine di ${game.title}`;
  ui.gamePageImage.onerror = () => { ui.gamePageImage.src = PLACEHOLDER; };
  ui.gamePageBadge.textContent = badgeText(game);
  ui.gamePageTitle.textContent = game.title;
  const availableStores = game.stores || listingsForGame(game).map((listing) => listing.store);
  const bylineParts = [];
  if (game.developer) {
    bylineParts.push(`<a href="${escapeAttr(entityRoute("developer", game.developer))}">${escapeHtml(game.developer)}</a>`);
  }
  if (game.publisher) {
    bylineParts.push(`<a href="${escapeAttr(entityRoute("publisher", game.publisher))}">${escapeHtml(game.publisher)}</a>`);
  }
  ui.gamePageByline.innerHTML = bylineParts.join(" · ")
    || escapeHtml([...new Set(availableStores)].map(storeLabel).join(" · "))
    || "Store non disponibile";
  ui.gamePageDescription.textContent = game.description || "Descrizione non disponibile.";
  ui.gamePageMeta.innerHTML = [
    game.release_date ? `<span><small>USCITA</small>${escapeHtml(formatDate(game.release_date))}</span>` : "",
    priceText(game) ? `<span><small>PREZZO</small>${escapeHtml(priceText(game))}</span>` : "",
    game.offer_type ? `<span><small>TIPO</small>${escapeHtml(game.offer_type)}</span>` : "",
    `<span><small>STORE</small>${escapeHtml([...new Set(availableStores)].map(storeLabel).join(" · "))}</span>`,
  ].filter(Boolean).join("");
  ui.gamePageStoreLink.href = game.store_url;
  ui.gamePageStoreLink.textContent = `Apri su ${storeLabel(game.store)}`;
  ui.gamePageLibrary.textContent = entry ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
  ui.gamePageFavorite.textContent = entry?.favorite ? "♥ Preferito" : "♡ Preferito";
  ui.gamePageStatus.value = journalProgress?.status || entry?.status || "saved";
  ui.gamePageStatus.disabled = false;
  ui.gamePageProgress.value = String(journalProgress?.progressPercent ?? entry?.progressPercent ?? 0);
  ui.gamePageProgressOutput.textContent = `${ui.gamePageProgress.value}%`;
  ui.gamePageStartedAt.value = journalProgress?.startedAt || "";
  ui.gamePageCompletedAt.value = journalProgress?.completedAt || "";
  ui.gamePageCompletionCount.value = String(journalProgress?.completionCount || 0);
  ui.gamePagePrimaryPlatform.value = journalProgress?.primaryPlatform || "";
  ui.gamePageDifficulty.value = journalProgress?.difficulty || "";
  ui.gamePageManualPlaytime.textContent = formatMinutes(sessionMinutes || journalProgress?.manualPlaytimeMinutes || 0);
  ui.gamePageNotes.value = entry?.notes || "";
  ui.gameSessionDate.value = new Date().toISOString().slice(0, 10);
  ui.gameSessionProgress.value = journalProgress?.progressPercent ?? "";
  ui.gameSessionPlatform.value = journalProgress?.primaryPlatform || "";
  ui.gameSessionVisibility.value = state.auth.user ? "private" : "private";
  ui.gameSessionVisibility.disabled = !state.auth.user;
  renderRating(game, entry);
  renderStoreOptions(game);
  renderPromotionTimeline(game);
  renderGameSessions(game);
  void renderRelatedGames(game);
  void renderGameEditorialMemberships(game);
  void renderGameSocial(game);

  ui.gamePageLibrary.onclick = () => {
    if (getLibraryEntry(game)) removeLibraryEntry(game);
    else setLibraryEntry(game);
    void renderGamePage();
  };
  ui.gamePageFavorite.onclick = () => {
    setLibraryEntry(game, { favorite: !getLibraryEntry(game)?.favorite });
    void renderGamePage();
  };
  ui.gamePageList.onclick = () => openListPicker(game);
  ui.gamePageProgress.oninput = () => {
    ui.gamePageProgressOutput.textContent = `${ui.gamePageProgress.value}%`;
  };
  ui.gamePageStatus.onchange = () => {

    if (ui.gamePageStatus.value === "completed" && !ui.gamePageCompletedAt.value) {
      ui.gamePageCompletedAt.value = new Date().toISOString().slice(0, 10);
      ui.gamePageProgress.value = "100";
      ui.gamePageProgressOutput.textContent = "100%";
    }
  };
  ui.gamePageSaveProgress.onclick = async () => {
    ui.gamePageSaveProgress.disabled = true;
    try {
      const status = ui.gamePageStatus.value;
      const progressPercent = Number(ui.gamePageProgress.value || 0);
      setLibraryEntry(game, {
        status,
        progressPercent,
        startedAt: ui.gamePageStartedAt.value || null,
        completedAt: ui.gamePageCompletedAt.value || null,
        completionCount: Number(ui.gamePageCompletionCount.value || 0),
        primaryPlatform: ui.gamePagePrimaryPlatform.value || null,
      });
      await window.VaultJournal.saveProgress({
        gameKey: gameKey(game),
        gameTitle: game.title,
        gameImageUrl: game.image_url,
        status,
        progressPercent,
        startedAt: ui.gamePageStartedAt.value,
        completedAt: ui.gamePageCompletedAt.value,
        completionCount: ui.gamePageCompletionCount.value,
        manualPlaytimeMinutes: sessionMinutes,
        primaryPlatform: ui.gamePagePrimaryPlatform.value,
        difficulty: ui.gamePageDifficulty.value,
      });
      showToast("Progressi salvati.");
      void renderGamePage();
    } catch (error) {
      showToast(error.message || "Salvataggio progressi fallito.");
    } finally {
      ui.gamePageSaveProgress.disabled = false;
    }
  };
  ui.gamePageSaveNotes.onclick = () => {
    setLibraryEntry(game, { notes: ui.gamePageNotes.value.trim() });
    showToast("Note private aggiornate.");
  };
  ui.gameSessionForm.onsubmit = async (event) => {
    event.preventDefault();
    ui.gameSessionError.hidden = true;
    ui.gameSessionSubmit.disabled = true;
    try {
      const minutes = Number(ui.gameSessionMinutes.value);
      if (!Number.isFinite(minutes) || minutes < 1) throw new Error("Inserisci una durata valida.");
      const progressValue = ui.gameSessionProgress.value === "" ? null : Number(ui.gameSessionProgress.value);
      await window.VaultJournal.addEntry({
        gameKey: gameKey(game),
        gameTitle: game.title,
        gameImageUrl: game.image_url,
        playedAt: ui.gameSessionDate.value,
        minutesPlayed: minutes,
        progressPercent: progressValue,
        platform: ui.gameSessionPlatform.value,
        note: ui.gameSessionNote.value,
        containsSpoilers: ui.gameSessionSpoilers.checked,
        visibility: state.auth.user ? ui.gameSessionVisibility.value : "private",
      });
      const nextMinutes = sessionMinutes + minutes;
      const currentProgress = window.VaultJournal.getProgress(gameKey(game)) || journalProgress || {};
      await window.VaultJournal.saveProgress({
        ...currentProgress,
        gameKey: gameKey(game),
        gameTitle: game.title,
        gameImageUrl: game.image_url,
        status: currentProgress.status || entry?.status || "playing",
        progressPercent: progressValue ?? currentProgress.progressPercent ?? 0,
        manualPlaytimeMinutes: nextMinutes,
        primaryPlatform: ui.gameSessionPlatform.value || currentProgress.primaryPlatform,
      });
      setLibraryEntry(game, {
        status: currentProgress.status || entry?.status || "playing",
        progressPercent: progressValue ?? currentProgress.progressPercent ?? 0,
      });
      ui.gameSessionForm.reset();
      ui.gameSessionDate.value = new Date().toISOString().slice(0, 10);
      ui.gameSessionMinutes.value = "60";
      ui.gameSessionVisibility.value = "private";
      showToast("Sessione registrata nel diario.");
      void renderGamePage();
    } catch (error) {
      ui.gameSessionError.textContent = error.message || "Registrazione sessione fallita.";
      ui.gameSessionError.hidden = false;
    } finally {
      ui.gameSessionSubmit.disabled = false;
    }
  };
}


function starsText(rating) {
  const value = Math.max(0, Math.min(5, Number(rating) || 0));
  return `${"★".repeat(value)}${"☆".repeat(5 - value)}`;
}

function profileRoute(username) {
  return `#/user/${encodeURIComponent(username)}`;
}

async function copyCurrentUrl(successMessage) {
  try {
    await navigator.clipboard.writeText(window.location.href);
    showToast(successMessage);
  } catch {
    window.prompt("Copia questo link:", window.location.href);
  }
}

function relativeTime(value) {
  const date = new Date(value);
  const seconds = Math.round((date.getTime() - Date.now()) / 1000);
  const formatter = new Intl.RelativeTimeFormat("it", { numeric: "auto" });
  const units = [
    ["year", 31536000],
    ["month", 2592000],
    ["week", 604800],
    ["day", 86400],
    ["hour", 3600],
    ["minute", 60],
  ];
  for (const [unit, size] of units) {
    if (Math.abs(seconds) >= size) return formatter.format(Math.round(seconds / size), unit);
  }
  return formatter.format(seconds, "second");
}

function socialTargetRoute(targetType, targetId, metadata = {}) {
  if (targetType === "profile" && metadata.following_username) {
    return profileRoute(metadata.following_username);
  }
  if (targetType === "review" && metadata.game_key) {
    return gameRoute({ internal_id: metadata.game_key });
  }
  if (targetType === "list") return listRoute(targetId);
  return "#/feed";
}

function commentElement(comment, onDeleted = null) {
  const article = document.createElement("article");
  article.className = "comment-item";
  const author = comment.author || {};
  const authorName = author.display_name || author.username || "Utente";
  const own = Boolean(state.auth.user && state.auth.user.id === comment.user_id);
  article.innerHTML = `
    <a class="comment-author" href="${author.username ? profileRoute(author.username) : "#/home"}">
      <span class="account-avatar comment-avatar">${author.avatar_url ? "" : escapeHtml(authorName.slice(0, 2).toUpperCase())}</span>
      <span><strong>${escapeHtml(authorName)}</strong><small>${author.username ? `@${escapeHtml(author.username)}` : ""}</small></span>
    </a>
    <p>${escapeHtml(comment.body)}</p>
    <footer>
      <span>${relativeTime(comment.created_at)}</span>
      <span class="comment-actions">
        ${!own && state.auth.user ? `<button class="comment-report" type="button">Segnala</button>` : ""}
        ${own ? `<button class="comment-delete" type="button">Elimina</button>` : ""}
      </span>
    </footer>`;
  const avatar = article.querySelector(".comment-avatar");
  if (author.avatar_url) avatar.style.backgroundImage = `url("${author.avatar_url}")`;
  const reportButton = article.querySelector(".comment-report");
  if (reportButton) {
    reportButton.onclick = () => requestContentReport("comment", comment.id, "questo commento");
  }
  const deleteButton = article.querySelector(".comment-delete");
  if (deleteButton) {
    deleteButton.onclick = async () => {
      if (!confirm("Eliminare il commento?")) return;
      try {
        await window.VaultSocial.deleteComment(comment.id);
        if (onDeleted) await onDeleted();
        else article.remove();
      } catch (error) {
        showToast(error.message || "Eliminazione commento fallita.");
      }
    };
  }
  return article;
}

async function renderCommentThread(container, targetType, targetId, onCountChange = null) {
  container.hidden = false;
  container.innerHTML = `<div class="route-loading">Caricamento commenti…</div>`;
  try {
    const comments = await window.VaultSocial.getComments(targetType, targetId);
    container.replaceChildren();

    const list = document.createElement("div");
    list.className = "comment-list";
    if (!comments.length) {
      list.innerHTML = `<div class="timeline-empty">Nessun commento. Inizia la conversazione.</div>`;
    } else {
      for (const comment of comments) {
        list.append(commentElement(comment, async () => {
          await renderCommentThread(container, targetType, targetId, onCountChange);
        }));
      }
    }
    container.append(list);

    if (state.auth.user) {
      const form = document.createElement("form");
      form.className = "comment-form";
      form.innerHTML = `
        <textarea rows="3" maxlength="2000" placeholder="Scrivi un commento…" required></textarea>
        <button class="button button-primary" type="submit">Pubblica</button>`;
      form.onsubmit = async (event) => {
        event.preventDefault();
        const textarea = form.querySelector("textarea");
        const button = form.querySelector("button");
        button.disabled = true;
        try {
          await window.VaultSocial.addComment(targetType, targetId, textarea.value);
          await renderCommentThread(container, targetType, targetId, onCountChange);
          if (onCountChange) onCountChange(comments.length + 1);
        } catch (error) {
          showToast(error.message || "Commento non pubblicato.");
        } finally {
          button.disabled = false;
        }
      };
      container.append(form);
    } else {
      const callout = document.createElement("p");
      callout.className = "comment-login-callout";
      callout.innerHTML = `Accedi per commentare. <a href="#/login">Vai all’accesso</a>`;
      container.append(callout);
    }

    if (onCountChange) onCountChange(comments.length);
  } catch (error) {
    console.error("Caricamento commenti fallito", error);
    container.innerHTML = `<div class="timeline-empty">Commenti non disponibili. Verifica la migrazione v3.4.</div>`;
  }
}

function wireReviewEngagement(article, review) {
  const likeButton = article.querySelector(".review-like-button");
  const commentsButton = article.querySelector(".review-comments-button");
  const thread = article.querySelector(".review-comment-thread");

  const updateLike = () => {
    likeButton.classList.toggle("is-active", Boolean(review.liked_by_me));
    likeButton.innerHTML = `${review.liked_by_me ? "♥" : "♡"} <span>${review.like_count || 0}</span>`;
  };
  updateLike();

  likeButton.onclick = async () => {
    if (!state.auth.user) {
      navigate("#/login");
      return;
    }
    likeButton.disabled = true;
    try {
      const liked = await window.VaultSocial.toggleReviewLike(review.id, Boolean(review.liked_by_me));
      review.liked_by_me = liked;
      review.like_count = Math.max(0, Number(review.like_count || 0) + (liked ? 1 : -1));
      updateLike();
    } catch (error) {
      showToast(error.message || "Operazione non riuscita.");
    } finally {
      likeButton.disabled = false;
    }
  };

  commentsButton.onclick = async () => {
    if (!thread.hidden) {
      thread.hidden = true;
      return;
    }
    await renderCommentThread(thread, "review", review.id, (count) => {
      review.comment_count = count;
      commentsButton.innerHTML = `💬 <span>${count}</span>`;
    });
  };
}

function activityCard(activity) {
  const article = document.createElement("article");
  article.className = "activity-card";
  const author = activity.author || {};
  const authorName = author.display_name || author.username || "Utente";
  const metadata = activity.metadata || {};
  const messages = {
    followed_user: `ha iniziato a seguire ${metadata.following_display_name || metadata.following_username || "un utente"}`,
    review_published: `ha recensito ${metadata.game_title || "un gioco"}`,
    list_published: `ha pubblicato la lista ${metadata.name || "senza titolo"}`,
    comment_published: `ha commentato ${metadata.label || "un contenuto"}`,
  };
  const route = socialTargetRoute(activity.target_type, activity.target_id, metadata);
  article.innerHTML = `
    <a class="activity-avatar-link" href="${author.username ? profileRoute(author.username) : "#/home"}">
      <span class="account-avatar activity-avatar">${author.avatar_url ? "" : escapeHtml(authorName.slice(0, 2).toUpperCase())}</span>
    </a>
    <div class="activity-body">
      <p><a href="${author.username ? profileRoute(author.username) : "#/home"}"><strong>${escapeHtml(authorName)}</strong></a> ${escapeHtml(messages[activity.activity_type] || "ha aggiornato il profilo")}</p>
      <span>${relativeTime(activity.created_at)}</span>
      <a class="activity-target-link" href="${route}">Apri contenuto →</a>
    </div>`;
  const avatar = article.querySelector(".activity-avatar");
  if (author.avatar_url) avatar.style.backgroundImage = `url("${author.avatar_url}")`;
  return article;
}

function userExploreCard(profile) {
  const article = document.createElement("article");
  article.className = "user-explore-card";
  const name = profile.display_name || profile.username;
  article.innerHTML = `
    <a href="${profileRoute(profile.username)}" class="user-explore-main">
      <span class="account-avatar account-avatar-large explore-avatar">${profile.avatar_url ? "" : escapeHtml(name.slice(0, 2).toUpperCase())}</span>
      <span>
        <strong>${escapeHtml(name)}</strong>
        <small>@${escapeHtml(profile.username)}</small>
      </span>
    </a>
    <p>${escapeHtml(profile.bio || "Nessuna bio pubblica.")}</p>
    <a class="button button-secondary" href="${profileRoute(profile.username)}">Apri profilo</a>`;
  const avatar = article.querySelector(".explore-avatar");
  if (profile.avatar_url) avatar.style.backgroundImage = `url("${profile.avatar_url}")`;
  return article;
}

function notificationRoute(notification) {
  const metadata = notification.metadata || {};
  if (notification.notification_type === "new_follower") {
    const username = notification.actor?.username || metadata.actor_username;
    if (username) return profileRoute(username);
  }
  return socialTargetRoute(notification.target_type, notification.target_id, metadata);
}

function notificationMessage(notification) {
  const metadata = notification.metadata || {};
  const actor = notification.actor?.display_name
    || notification.actor?.username
    || metadata.actor_display_name
    || metadata.actor_username
    || "Un utente";
  const messages = {
    new_follower: `${actor} ha iniziato a seguirti`,
    review_like: `${actor} ha apprezzato la tua recensione di ${metadata.game_title || "un gioco"}`,
    list_like: `${actor} ha apprezzato la lista ${metadata.list_name || ""}`,
    review_comment: `${actor} ha commentato la tua recensione di ${metadata.label || "un gioco"}`,
    list_comment: `${actor} ha commentato la lista ${metadata.label || ""}`,
  };
  return messages[notification.notification_type] || `${actor} ha interagito con un tuo contenuto`;
}

function notificationCard(notification) {
  const link = document.createElement("a");
  link.className = `notification-card${notification.read_at ? "" : " is-unread"}`;
  link.href = notificationRoute(notification);
  const metadata = notification.metadata || {};
  const actor = notification.actor || {};
  const actorName = actor.display_name
    || actor.username
    || metadata.actor_display_name
    || metadata.actor_username
    || "Utente";
  const actorAvatar = actor.avatar_url || metadata.actor_avatar_url || null;
  link.innerHTML = `
    <span class="account-avatar notification-avatar">${actorAvatar ? "" : escapeHtml(actorName.slice(0, 2).toUpperCase())}</span>
    <span class="notification-copy">
      <strong>${escapeHtml(notificationMessage(notification))}</strong>
      <small>${relativeTime(notification.created_at)}</small>
    </span>
    ${notification.read_at ? "" : `<span class="unread-dot" aria-label="Non letta"></span>`}`;
  const avatar = link.querySelector(".notification-avatar");
  if (actorAvatar) avatar.style.backgroundImage = `url("${actorAvatar}")`;
  link.onclick = () => {
    if (!notification.read_at) {
      void window.VaultSocial.markNotificationRead(notification.id)
        .then(() => refreshNotificationCount())
        .catch(console.error);
    }
  };
  return link;
}

async function refreshNotificationCount() {
  if (!window.VaultSocial || !state.auth.user) {
    state.social.unreadNotifications = 0;
  } else {
    try {
      state.social.unreadNotifications = await window.VaultSocial.getUnreadNotificationCount();
    } catch (error) {
      console.warn("Conteggio notifiche non disponibile", error);
      state.social.unreadNotifications = 0;
    }
  }
  const count = state.social.unreadNotifications;
  for (const badge of [ui.notificationBadge, ui.sidebarNotificationBadge]) {
    if (!badge) continue;
    badge.hidden = count === 0;
    badge.textContent = count > 99 ? "99+" : String(count);
  }
}

async function renderFeedPage() {
  updateDocumentTitle("Feed");
  const signedIn = Boolean(state.auth.user);
  ui.feedFollowingTab.classList.toggle("is-active", state.social.feedFollowingOnly);
  ui.feedPublicTab.classList.toggle("is-active", !state.social.feedFollowingOnly);
  ui.feedAuthRequired.hidden = signedIn || !state.social.feedFollowingOnly;
  ui.feedList.hidden = !signedIn && state.social.feedFollowingOnly;

  if (!window.VaultSocial || !state.auth.configured) {
    ui.feedList.hidden = false;
    ui.feedList.innerHTML = `<div class="timeline-empty">Configura Supabase per usare il feed.</div>`;
    return;
  }
  if (!signedIn && state.social.feedFollowingOnly) return;

  ui.feedList.hidden = false;
  ui.feedList.innerHTML = `<div class="route-loading">Caricamento attività…</div>`;
  try {
    const activities = await window.VaultSocial.getActivityFeed({
      followingOnly: state.social.feedFollowingOnly,
    });
    state.social.feed = activities;
    ui.feedList.replaceChildren();
    if (!activities.length) {
      ui.feedList.innerHTML = `<div class="timeline-empty">${state.social.feedFollowingOnly ? "Il feed è vuoto. Segui qualche profilo da Esplora." : "Nessuna attività pubblica recente."}</div>`;
    } else {
      for (const activity of activities) ui.feedList.append(activityCard(activity));
    }
  } catch (error) {
    console.error("Feed non disponibile", error);
    ui.feedList.innerHTML = `<div class="timeline-empty">Feed non disponibile. Verifica la migrazione v3.4.</div>`;
  }
}

async function renderExplorePage() {
  updateDocumentTitle("Esplora utenti");
  if (!window.VaultSocial || !state.auth.configured) {
    ui.exploreUsersGrid.innerHTML = `<div class="timeline-empty">Configura Supabase per esplorare i profili.</div>`;
    return;
  }
  ui.exploreUsersGrid.innerHTML = `<div class="route-loading">Ricerca profili…</div>`;
  try {
    const profiles = await window.VaultSocial.exploreUsers(ui.exploreUsersSearch.value);
    state.social.exploreUsers = profiles;
    ui.exploreUsersGrid.replaceChildren();
    if (!profiles.length) {
      ui.exploreUsersGrid.innerHTML = `<div class="timeline-empty">Nessun profilo trovato.</div>`;
    } else {
      for (const profile of profiles) ui.exploreUsersGrid.append(userExploreCard(profile));
    }
  } catch (error) {
    console.error("Esplora utenti non disponibile", error);
    ui.exploreUsersGrid.innerHTML = `<div class="timeline-empty">Impossibile caricare i profili pubblici.</div>`;
  }
}

async function renderNotificationsPage() {
  updateDocumentTitle("Notifiche");
  const signedIn = Boolean(state.auth.user);
  ui.notificationsAuthRequired.hidden = signedIn;
  ui.notificationsList.hidden = !signedIn;
  ui.notificationsMarkAll.hidden = !signedIn;

  if (!signedIn) return;
  ui.notificationsList.innerHTML = `<div class="route-loading">Caricamento notifiche…</div>`;
  try {
    const notifications = await window.VaultSocial.getNotifications();
    state.social.notifications = notifications;
    ui.notificationsList.replaceChildren();
    if (!notifications.length) {
      ui.notificationsList.innerHTML = `<div class="timeline-empty">Nessuna notifica.</div>`;
    } else {
      for (const notification of notifications) {
        ui.notificationsList.append(notificationCard(notification));
      }
    }
    await refreshNotificationCount();
  } catch (error) {
    console.error("Notifiche non disponibili", error);
    ui.notificationsList.innerHTML = `<div class="timeline-empty">Notifiche non disponibili. Verifica la migrazione v3.4.</div>`;
  }
}

async function renderSharedListSocial(list) {
  if (!window.VaultSocial || !state.auth.configured || list.visibility !== "public") {
    ui.sharedListLike.hidden = true;
    ui.sharedListComments.innerHTML = `<div class="timeline-empty">Le interazioni sono disponibili per le liste pubbliche.</div>`;
    return;
  }

  ui.sharedListLike.hidden = false;
  try {
    const engagement = await window.VaultSocial.getEngagement("list", [list.id]);
    const current = engagement[list.id] || { like_count: 0, comment_count: 0, liked_by_me: false };
    list.like_count = current.like_count;
    list.comment_count = current.comment_count;
    list.liked_by_me = current.liked_by_me;
    const updateButton = () => {
      ui.sharedListLike.classList.toggle("is-active", Boolean(list.liked_by_me));
      ui.sharedListLike.innerHTML = `${list.liked_by_me ? "♥" : "♡"} <span>${list.like_count || 0}</span>`;
    };
    updateButton();
    ui.sharedListCommentCount.textContent = `${list.comment_count || 0} commenti`;

    ui.sharedListLike.onclick = async () => {
      if (!state.auth.user) {
        navigate("#/login");
        return;
      }
      ui.sharedListLike.disabled = true;
      try {
        const liked = await window.VaultSocial.toggleListLike(list.id, Boolean(list.liked_by_me));
        list.liked_by_me = liked;
        list.like_count = Math.max(0, Number(list.like_count || 0) + (liked ? 1 : -1));
        updateButton();
      } catch (error) {
        showToast(error.message || "Operazione non riuscita.");
      } finally {
        ui.sharedListLike.disabled = false;
      }
    };

    await renderCommentThread(ui.sharedListComments, "list", list.id, (count) => {
      list.comment_count = count;
      ui.sharedListCommentCount.textContent = `${count} commenti`;
    });
  } catch (error) {
    console.error("Interazioni lista non disponibili", error);
    ui.sharedListComments.innerHTML = `<div class="timeline-empty">Interazioni non disponibili. Verifica la migrazione v3.4.</div>`;
  }
}

function reviewCard(review, { showGame = false } = {}) {
  const article = document.createElement("article");
  article.className = "public-review-card";
  const author = review.author || {};
  const authorName = author.display_name || author.username || "Utente The Free Vault";
  const authorLink = author.username ? profileRoute(author.username) : "#/home";
  const own = Boolean(state.auth.user && state.auth.user.id === review.user_id);
  const avatarStyle = author.avatar_url
    ? `style="background-image:url('${escapeAttr(author.avatar_url)}')"`
    : "";
  const avatarText = author.avatar_url ? "" : escapeHtml(authorName.slice(0, 2).toUpperCase());
  const body = review.body
    ? `<p class="review-body${review.contains_spoilers ? " is-spoiler" : ""}">${escapeHtml(review.body)}</p>`
    : `<p class="muted">Voto senza recensione testuale.</p>`;
  const gameBlock = showGame
    ? `<a class="review-game-link" href="${gameRoute({ internal_id: review.game_key })}">
         <img src="${escapeAttr(review.game_image_url || PLACEHOLDER)}" alt="">
         <span>${escapeHtml(review.game_title || "Gioco")}</span>
       </a>`
    : "";

  article.innerHTML = `
    ${gameBlock}
    <header class="review-card-header">
      <a class="review-author" href="${authorLink}">
        <span class="account-avatar review-avatar" ${avatarStyle}>${avatarText}</span>
        <span><strong>${escapeHtml(authorName)}</strong><small>${author.username ? `@${escapeHtml(author.username)}` : ""}</small></span>
      </a>
      <div class="review-score"><strong>${starsText(review.rating)}</strong><span>${Number(review.rating).toFixed(0)}/5</span></div>
    </header>
    ${review.title ? `<h3>${escapeHtml(review.title)}</h3>` : ""}
    ${body}
    ${review.contains_spoilers && review.body ? `<button class="spoiler-reveal" type="button">Mostra spoiler</button>` : ""}
    <footer class="review-card-footer">
      <span>${formatDate(review.updated_at || review.created_at, true)}</span>
      <div class="review-social-actions">
        <button class="review-like-button" type="button" aria-label="Mi piace">
          ${review.liked_by_me ? "♥" : "♡"} <span>${review.like_count || 0}</span>
        </button>
        <button class="review-comments-button" type="button" aria-label="Commenti">
          💬 <span>${review.comment_count || 0}</span>
        </button>
        ${!own && state.auth.user ? `<button class="review-report-button" type="button">Segnala</button>` : ""}
      </div>
    </footer>
    <div class="review-comment-thread comment-thread" hidden></div>`;

  const spoiler = article.querySelector(".is-spoiler");
  const reveal = article.querySelector(".spoiler-reveal");
  if (spoiler && reveal) {
    reveal.onclick = () => {
      spoiler.classList.toggle("is-revealed");
      reveal.textContent = spoiler.classList.contains("is-revealed")
        ? "Nascondi spoiler"
        : "Mostra spoiler";
    };
  }
  wireReviewEngagement(article, review);
  const reportButton = article.querySelector(".review-report-button");
  if (reportButton) reportButton.onclick = () => requestContentReport("review", review.id, "questa recensione");
  return article;
}

async function renderGameSocial(game) {
  const key = gameKey(game);
  const reviewKeys = reviewKeysForGame(game);
  ui.publicReviewsList.innerHTML = `<div class="route-loading">Caricamento recensioni…</div>`;
  ui.publicReviewError.hidden = true;

  if (!window.VaultSocial || !state.auth.configured) {
    ui.publicRatingAverage.textContent = "—";
    ui.publicRatingCount.textContent = "Community non configurata";
    ui.publicReviewForm.hidden = true;
    ui.publicReviewSignedOut.hidden = false;
    ui.publicReviewsList.innerHTML = `<div class="timeline-empty">Configura Supabase per abilitare recensioni e voti pubblici.</div>`;
    return;
  }

  try {
    const [reviews, myReview] = await Promise.all([
      window.VaultSocial.getGameReviews(reviewKeys),
      window.VaultSocial.getMyReview(reviewKeys),
    ]);
    const routedGame = state.route.name === "game"
      ? resolveGameByKey(state.route.params.key)
      : null;
    if (!routedGame || gameKey(routedGame) !== key) return;
    state.social.gameReviews = reviews;
    state.social.myReview = myReview;
    const summary = window.VaultSocial.summarizeRatings(reviews);
    ui.publicRatingAverage.textContent = summary.count ? summary.average.toFixed(1) : "—";
    ui.publicRatingCount.textContent = summary.count === 1 ? "1 voto pubblico" : `${summary.count} voti pubblici`;

    const signedIn = Boolean(state.auth.user);
    ui.publicReviewSignedOut.hidden = signedIn;
    ui.publicReviewForm.hidden = !signedIn;
    if (signedIn) {
      ui.publicReviewRating.value = myReview?.rating ? String(myReview.rating) : "";
      ui.publicReviewTitle.value = myReview?.title || "";
      ui.publicReviewBody.value = myReview?.body || "";
      ui.publicReviewSpoilers.checked = Boolean(myReview?.contains_spoilers);
      ui.publicReviewSubmit.textContent = myReview ? "Aggiorna recensione" : "Pubblica recensione";
      ui.publicReviewDelete.hidden = !myReview;
    }

    ui.publicReviewsList.replaceChildren();
    if (!reviews.length) {
      ui.publicReviewsList.innerHTML = `<div class="timeline-empty">Nessuna recensione pubblica. Puoi essere il primo.</div>`;
    } else {
      for (const review of reviews) ui.publicReviewsList.append(reviewCard(review));
    }
  } catch (error) {
    console.error("Caricamento recensioni fallito", error);
    ui.publicReviewsList.innerHTML = `<div class="timeline-empty">Recensioni temporaneamente non disponibili. Verifica di aver eseguito le migrazioni sociali v3.3 e v3.4.</div>`;
  }
}

async function renderPublicProfilePage() {
  const username = state.route.params.username;
  updateDocumentTitle(`@${username}`);
  ui.publicProfileLoading.hidden = false;
  ui.publicProfileNotFound.hidden = true;
  ui.publicProfileContent.hidden = true;

  if (!window.VaultSocial || !state.auth.configured) {
    ui.publicProfileLoading.hidden = true;
    ui.publicProfileNotFound.hidden = false;
    return;
  }

  try {
    const profile = await window.VaultSocial.getPublicProfile(username);
    if (!profile || state.route.name !== "public-profile") {
      ui.publicProfileLoading.hidden = true;
      ui.publicProfileNotFound.hidden = false;
      return;
    }
    const content = await window.VaultSocial.getPublicProfileContent(profile.id);
    if (
      state.route.name !== "public-profile"
      || state.route.params.username.toLocaleLowerCase() !== username.toLocaleLowerCase()
    ) return;

    state.social.publicProfile = profile;
    state.social.publicProfileContent = content;
    ui.publicProfileLoading.hidden = true;
    ui.publicProfileContent.hidden = false;
    applyAvatar(ui.publicProfileAvatar, null, profile);
    ui.publicProfileName.textContent = profile.display_name || profile.username;
    ui.publicProfileHandle.textContent = `@${profile.username}`;
    ui.publicProfileBio.textContent = profile.bio || "Nessuna bio pubblica.";
    ui.publicProfileMemberSince.textContent = `Nel Vault dal ${formatDate(profile.created_at)}`;

    const summary = window.VaultSocial.summarizeRatings(content.reviews);
    ui.publicProfileStatReviews.textContent = content.reviews.length;
    ui.publicProfileStatAverage.textContent = summary.count ? summary.average.toFixed(1) : "—";
    ui.publicProfileStatLists.textContent = content.lists.length;
    ui.publicProfileStatFollowers.textContent = content.follow.followers;
    ui.publicProfileStatFollowing.textContent = content.follow.following;

    const signedIn = Boolean(state.auth.user);
    ui.publicProfileLoginToFollow.hidden = signedIn || content.follow.is_self;
    ui.publicProfileFollow.hidden = !signedIn || content.follow.is_self;
    ui.publicProfileFollow.textContent = content.follow.is_following ? "Seguito ✓" : "Segui";
    ui.publicProfileFollow.classList.toggle("button-primary", !content.follow.is_following);
    ui.publicProfileFollow.classList.toggle("button-secondary", content.follow.is_following);
    ui.publicProfileFollow.onclick = async () => {
      ui.publicProfileFollow.disabled = true;
      try {
        if (content.follow.is_following) {
          await window.VaultSocial.unfollowUser(profile.id);
        } else {
          await window.VaultSocial.followUser(profile.id);
        }
        content.follow = await window.VaultSocial.getFollowState(profile.id);
        ui.publicProfileStatFollowers.textContent = content.follow.followers;
        ui.publicProfileStatFollowing.textContent = content.follow.following;
        ui.publicProfileFollow.textContent = content.follow.is_following ? "Seguito ✓" : "Segui";
        ui.publicProfileFollow.classList.toggle("button-primary", !content.follow.is_following);
        ui.publicProfileFollow.classList.toggle("button-secondary", content.follow.is_following);
      } catch (error) {
        showToast(error.message || "Impossibile aggiornare il follow.");
      } finally {
        ui.publicProfileFollow.disabled = false;
      }
    };

    ui.publicProfileReviews.replaceChildren();
    if (!content.reviews.length) {
      ui.publicProfileReviews.innerHTML = `<div class="timeline-empty">Nessuna recensione pubblica.</div>`;
    } else {
      const engagement = await window.VaultSocial.getEngagement(
        "review",
        content.reviews.map((review) => review.id),
      );
      for (const review of content.reviews) {
        ui.publicProfileReviews.append(
          reviewCard(
            { ...review, ...(engagement[review.id] || {}), author: profile },
            { showGame: true },
          ),
        );
      }
    }

    ui.publicProfileLists.replaceChildren();
    if (!content.lists.length) {
      ui.publicProfileLists.innerHTML = `<div class="timeline-empty">Nessuna lista pubblica.</div>`;
    } else {
      for (const list of content.lists) {
        const link = document.createElement("a");
        link.className = "public-list-link";
        link.href = listRoute(list.id);
        link.innerHTML = `<span><strong>${escapeHtml(list.name)}</strong><small>${escapeHtml(list.description || "Nessuna descrizione")}</small></span><b>${(list.game_keys || []).length} giochi →</b>`;
        ui.publicProfileLists.append(link);
      }
    }

    ui.publicProfileDiary.replaceChildren();
    try {
      const diaryEntries = await window.VaultJournal?.getPublicEntries(profile.id, 8) || [];
      if (!diaryEntries.length) {
        ui.publicProfileDiary.innerHTML = `<div class="timeline-empty">Nessuna sessione pubblica.</div>`;
      } else {
        diaryEntries.forEach((entry) => ui.publicProfileDiary.append(createDiaryEntryCard(entry, { publicView: true, compact: true })));
      }
    } catch (diaryError) {
      console.warn("Diario pubblico non disponibile", diaryError);
      ui.publicProfileDiary.innerHTML = `<div class="timeline-empty">Diario pubblico temporaneamente non disponibile.</div>`;
    }
  } catch (error) {
    console.error("Profilo pubblico non disponibile", error);
    ui.publicProfileLoading.hidden = true;
    ui.publicProfileNotFound.hidden = false;
  }
}

async function renderSharedListPage() {
  const id = state.route.params.id;
  updateDocumentTitle("Lista");
  ui.sharedListLoading.hidden = false;
  ui.sharedListNotFound.hidden = true;
  ui.sharedListContent.hidden = true;
  ui.sharedListGames.replaceChildren();
  ui.sharedListComments.replaceChildren();

  try {
    let list = state.lists[id]
      ? {
          id,
          user_id: state.auth.user?.id || null,
          name: state.lists[id].name,
          description: state.lists[id].description,
          visibility: state.lists[id].visibility,
          game_keys: state.lists[id].games || [],
          created_at: state.lists[id].createdAt,
          updated_at: state.lists[id].updatedAt,
          author: state.auth.profile || null,
        }
      : null;

    if (!list && window.VaultSocial && state.auth.configured) {
      list = await window.VaultSocial.getSharedList(id);
    }
    if (!list || state.route.name !== "list" || state.route.params.id !== id) {
      ui.sharedListLoading.hidden = true;
      ui.sharedListNotFound.hidden = false;
      return;
    }

    state.social.sharedList = list;
    ui.sharedListLoading.hidden = true;
    ui.sharedListContent.hidden = false;
    const canReportList = Boolean(state.auth.user && list.user_id && state.auth.user.id !== list.user_id);
    ui.sharedListReport.hidden = !canReportList;
    ui.sharedListReport.onclick = canReportList
      ? () => requestContentReport("list", list.id, "questa lista")
      : null;
    ui.sharedListVisibility.textContent = list.visibility === "public" ? "LISTA PUBBLICA" : "LISTA PRIVATA";
    ui.sharedListTitle.textContent = list.name;
    ui.sharedListDescription.textContent = list.description || "Nessuna descrizione.";
    ui.sharedListMeta.textContent = `${(list.game_keys || []).length} giochi · aggiornata ${formatDate(list.updated_at || list.created_at, true)}`;
    const authorName = list.author?.display_name || list.author?.username || "Il tuo profilo";
    ui.sharedListAuthor.textContent = list.author?.username
      ? `Creata da ${authorName} · @${list.author.username}`
      : `Creata da ${authorName}`;
    ui.sharedListAuthor.href = list.author?.username ? profileRoute(list.author.username) : "#/profile";
    updateDocumentTitle(list.name);

    await hydrateCatalogKeys(list.game_keys || []);
    if (state.route.name !== "list" || state.route.params.id !== id) return;
    const games = (list.game_keys || []).map(resolveGameByKey).filter(Boolean);
    if (!games.length) {
      ui.sharedListGames.innerHTML = `<div class="empty-state"><strong>Lista vuota</strong><span>I giochi potrebbero non essere ancora presenti nel catalogo locale.</span></div>`;
    } else {
      for (const game of games) ui.sharedListGames.append(renderCard(game));
    }
    await renderSharedListSocial(list);
  } catch (error) {
    console.error("Lista condivisa non disponibile", error);
    ui.sharedListLoading.hidden = true;
    ui.sharedListNotFound.hidden = false;
  }
}

function initialsForAccount(user, profile) {
  const source = profile?.display_name || profile?.username || user?.email || "?";
  return source.trim().slice(0, 2).toUpperCase();
}

function applyAvatar(element, user, profile) {
  if (!element) return;
  const url = profile?.avatar_url;
  element.classList.toggle("has-image", Boolean(url));
  element.style.backgroundImage = url ? `url("${String(url).replaceAll('"', '%22')}")` : "";
  element.textContent = url ? "" : initialsForAccount(user, profile);
}

function updateAccountUI(snapshot) {
  state.auth = snapshot;
  state.admin.loaded = false;
  void refreshAdminContext();
  if (!snapshot.configured) {
    ui.accountLabel.textContent = "Configura account";
    ui.accountAvatar.textContent = "!";
    ui.accountAvatar.style.backgroundImage = "";
    ui.sidebarDataNote.textContent = "Account cloud non configurato.";
    void refreshNotificationCount();
    return;
  }
  if (!snapshot.user) {
    ui.accountLabel.textContent = "Accedi";
    ui.accountAvatar.textContent = "?";
    ui.accountAvatar.style.backgroundImage = "";
    ui.sidebarDataNote.textContent = "I dati personali sono salvati localmente.";
    void refreshNotificationCount();
    return;
  }
  ui.accountLabel.textContent = snapshot.profile?.display_name || snapshot.profile?.username || "Profilo";
  applyAvatar(ui.accountAvatar, snapshot.user, snapshot.profile);
  ui.sidebarDataNote.textContent = "Libreria, liste e attività sono collegate al tuo account.";
  void refreshNotificationCount();
}


function formatBytes(value) {
  const bytes = Math.max(0, Number(value) || 0);
  if (bytes < 1024) return `${bytes} B`;
  const units = ["kB", "MB", "GB", "TB"];
  let current = bytes / 1024;
  let index = 0;
  while (current >= 1024 && index < units.length - 1) {
    current /= 1024;
    index += 1;
  }
  return `${current.toFixed(current >= 100 ? 0 : current >= 10 ? 1 : 2)} ${units[index]}`;
}

function adminCanAccessSection(section) {
  const context = state.admin.context || {};
  if (section === "moderation") return Boolean(context.can_moderate);
  return Boolean(context.is_admin);
}

function updateAdminNavigation() {
  const context = state.admin.context || {};
  const visible = Boolean(state.auth.user && (context.is_admin || context.can_moderate));
  if (ui.adminNavSection) ui.adminNavSection.hidden = !visible;
  $$('[data-route^="admin-"]').forEach((link) => {
    const section = link.dataset.route.replace("admin-", "");
    link.hidden = !adminCanAccessSection(section);
  });
}

async function refreshAdminContext() {
  const requestId = ++state.admin.requestId;
  if (!state.auth.user || !window.VaultAdmin) {
    state.admin.loaded = true;
    state.admin.context = { role: null, is_admin: false, can_moderate: false };
    updateAdminNavigation();
    if (state.route.name === "admin") void renderAdminPage();
    return state.admin.context;
  }
  try {
    const context = await window.VaultAdmin.getContext();
    if (requestId !== state.admin.requestId) return state.admin.context;
    state.admin.context = context;
  } catch (error) {
    console.warn("Contesto amministratore non disponibile", error);
    state.admin.context = { role: null, is_admin: false, can_moderate: false };
  } finally {
    if (requestId === state.admin.requestId) {
      state.admin.loaded = true;
      updateAdminNavigation();
      if (state.route.name === "admin") void renderAdminPage();
    }
  }
  return state.admin.context;
}

function setAdminPanel(section) {
  const panels = {
    catalog: ui.adminCatalogPanel,
    editorial: ui.adminEditorialPanel,
    matching: ui.adminMatchingPanel,
    moderation: ui.adminModerationPanel,
    system: ui.adminSystemPanel,
  };
  Object.entries(panels).forEach(([name, panel]) => {
    if (panel) panel.hidden = name !== section;
  });
  $$('[data-admin-tab]').forEach((tab) => {
    tab.classList.toggle("is-active", tab.dataset.adminTab === section);
  });
}

async function renderAdminPage() {
  const section = state.route.params.section || "catalog";
  updateDocumentTitle("Amministrazione");
  setAdminPanel(section);

  if (!state.admin.loaded) {
    ui.adminAccessRequired.hidden = false;
    ui.adminContent.hidden = true;
    ui.adminRoleBadge.textContent = "VERIFICA ACCESSO";
    void refreshAdminContext();
    return;
  }

  const allowed = adminCanAccessSection(section);
  ui.adminAccessRequired.hidden = allowed;
  ui.adminContent.hidden = !allowed;
  ui.adminRoleBadge.textContent = state.admin.context.role
    ? state.admin.context.role.toLocaleUpperCase("it")
    : "NESSUN RUOLO";
  if (!allowed) return;

  if (section === "editorial") await loadAdminEditorial();
  if (section === "matching") await loadAdminMatches();
  if (section === "moderation") await loadAdminReports();
  if (section === "system") await loadAdminSystemStatus();
}

function renderAdminCatalogResults(games) {
  ui.adminCatalogResults.replaceChildren();
  if (!games.length) {
    ui.adminCatalogResults.innerHTML = `<div class="timeline-empty">Nessun gioco trovato.</div>`;
    return;
  }
  for (const game of games) {
    const button = document.createElement("button");
    button.className = "admin-result-item";
    button.type = "button";
    button.innerHTML = `
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <span><strong>${escapeHtml(game.title || "Senza titolo")}</strong><small>${escapeHtml([game.developer, game.publisher, (game.stores || []).map(storeLabel).join(" · ")].filter(Boolean).join(" · "))}</small></span>
      <b>Modifica →</b>`;
    button.onclick = () => loadAdminCatalogRecord(game.match_key || game.canonical_id);
    ui.adminCatalogResults.append(button);
  }
}

async function searchAdminCatalog() {
  const query = ui.adminCatalogSearch.value.trim();
  if (query.length < 2) {
    ui.adminCatalogResults.innerHTML = `<div class="timeline-empty">Inserisci almeno due caratteri.</div>`;
    return;
  }
  ui.adminCatalogResults.innerHTML = `<div class="route-loading">Ricerca nel catalogo…</div>`;
  try {
    const result = await window.VaultCatalog.search({ query, limit: 20, offset: 0, force: true });
    renderAdminCatalogResults(result.items || []);
  } catch (error) {
    console.error("Ricerca admin fallita", error);
    ui.adminCatalogResults.innerHTML = `<div class="timeline-empty">Ricerca non disponibile.</div>`;
  }
}

function populateAdminOverrideForm(record) {
  const game = record?.game || {};
  const override = record?.override || {};
  const locks = new Set(override.locked_fields || []);
  $$('[data-override-input]').forEach((input) => {
    const field = input.dataset.overrideInput;
    const value = locks.has(field) ? override[field] : game[field];
    input.value = value ?? "";
  });
  $$('[data-lock-field]').forEach((checkbox) => {
    checkbox.checked = locks.has(checkbox.dataset.lockField);
  });
}

async function loadAdminCatalogRecord(key) {
  ui.adminCatalogEditor.hidden = false;
  ui.adminCatalogTitle.textContent = "Caricamento…";
  ui.adminCatalogListings.replaceChildren();
  try {
    const record = await window.VaultAdmin.getCatalogRecord(key);
    if (!record?.game) throw new Error("Gioco non trovato.");
    state.admin.selectedCatalog = record;
    const game = record.game;
    ui.adminCatalogTitle.textContent = game.title;
    ui.adminCatalogKey.textContent = game.match_key;
    ui.adminCatalogOpen.href = gameRoute({ internal_id: game.match_key });
    ui.adminCatalogListings.replaceChildren();
    for (const listing of game.store_listings || []) {
      const item = document.createElement("article");
      item.className = "admin-listing-card";
      item.innerHTML = `<strong>${escapeHtml(storeLabel(listing.store))}</strong><span>${escapeHtml(listing.title || listing.external_id || listing.listing_id || "Listing")}</span><small>${escapeHtml(listing.listing_id || "")}</small>`;
      ui.adminCatalogListings.append(item);
    }
    if (!(game.store_listings || []).length) {
      ui.adminCatalogListings.innerHTML = `<div class="timeline-empty">Nessuna listing associata.</div>`;
    }
    populateAdminOverrideForm(record);
    ui.adminOverrideMessage.hidden = true;
  } catch (error) {
    console.error("Record admin non disponibile", error);
    ui.adminCatalogTitle.textContent = "Errore di caricamento";
    showToast(error.message || "Gioco non disponibile.");
  }
}

function adminOverridePayload() {
  const patch = {};
  const lockedFields = [];
  $$('[data-override-input]').forEach((input) => {
    patch[input.dataset.overrideInput] = input.value;
  });
  $$('[data-lock-field]').forEach((checkbox) => {
    if (checkbox.checked) lockedFields.push(checkbox.dataset.lockField);
  });
  return { patch, lockedFields };
}


function editorialSlug(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 100);
}

function setAdminEditorialMessage(element, message, success = false) {
  element.textContent = message;
  element.classList.toggle("auth-success", success);
  element.hidden = !message;
}

function nextFranchiseOrder(field = "release_order") {
  const games = state.admin.selectedFranchise?.games || [];
  return games.reduce((max, game) => Math.max(max, Number(game?.[field] || 0)), 0) + 1;
}

function franchiseSelectionHas(key) {
  return (state.admin.franchiseGameSelection || []).some((item) => gameKey(item) === key);
}

function currentFranchiseGameKeys() {
  return new Set((state.admin.selectedFranchise?.games || []).map((game) => gameKey(game)));
}

function prepareAdminFranchiseBatchMode() {
  if (!ui.adminFranchiseGameKey.value) return;
  ui.adminFranchiseGameForm.reset();
  ui.adminFranchiseGameKey.value = "";
  ui.adminFranchiseReleaseOrder.value = String(nextFranchiseOrder("release_order"));
}

function setAdminFranchiseGameSelection(game, selected) {
  const key = gameKey(game);
  if (!key || currentFranchiseGameKeys().has(key)) return;
  const items = [...(state.admin.franchiseGameSelection || [])];
  const index = items.findIndex((item) => gameKey(item) === key);
  if (selected && index < 0) {
    prepareAdminFranchiseBatchMode();
    items.push(game);
  } else if (!selected && index >= 0) {
    items.splice(index, 1);
  }
  state.admin.franchiseGameSelection = items;
}

function franchiseReleaseSortValue(game) {
  const rawDate = game?.release_date || game?.releaseDate || game?.first_release_date || "";
  const timestamp = rawDate ? Date.parse(rawDate) : NaN;
  if (Number.isFinite(timestamp)) return timestamp;
  const year = Number(game?.release_year || game?.releaseYear || 0);
  return year > 0 ? Date.UTC(year, 0, 1) : Number.MAX_SAFE_INTEGER;
}

function renderAdminFranchiseSelectedList() {
  if (!ui.adminFranchiseSelectedList) return;
  const selected = state.admin.franchiseGameSelection || [];
  ui.adminFranchiseSelectedList.replaceChildren();
  ui.adminFranchiseSelectedList.hidden = selected.length === 0;

  selected.forEach((game, index) => {
    const item = document.createElement("article");
    item.className = "admin-selected-game";
    item.innerHTML = `
      <span class="admin-selected-game-order">${index + 1}</span>
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <div><strong>${escapeHtml(game.title || "Gioco")}</strong><small>${escapeHtml(String(game.release_year || game.release_date || game.match_key || ""))}</small></div>
      <div class="admin-selected-game-actions">
        <button class="button button-secondary" data-up type="button" aria-label="Sposta su">↑</button>
        <button class="button button-secondary" data-down type="button" aria-label="Sposta giù">↓</button>
        <button class="button button-danger" data-remove type="button">Rimuovi</button>
      </div>`;
    item.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    const move = (direction) => {
      const target = index + direction;
      if (target < 0 || target >= selected.length) return;
      [selected[index], selected[target]] = [selected[target], selected[index]];
      state.admin.franchiseGameSelection = [...selected];
      updateAdminFranchiseSelectionUI();
    };
    item.querySelector("[data-up]").disabled = index === 0;
    item.querySelector("[data-down]").disabled = index === selected.length - 1;
    item.querySelector("[data-up]").onclick = () => move(-1);
    item.querySelector("[data-down]").onclick = () => move(1);
    item.querySelector("[data-remove]").onclick = () => {
      setAdminFranchiseGameSelection(game, false);
      updateAdminFranchiseSelectionUI();
    };
    ui.adminFranchiseSelectedList.append(item);
  });
}

function syncAdminFranchiseSearchRows() {
  ui.adminFranchiseGameSearchResults?.querySelectorAll("[data-franchise-game-key]").forEach((row) => {
    const key = row.dataset.franchiseGameKey;
    const checkbox = row.querySelector('input[type="checkbox"]');
    const selected = franchiseSelectionHas(key);
    row.classList.toggle("is-selected", selected);
    if (checkbox) checkbox.checked = selected;
    const label = row.querySelector("b");
    if (label) label.textContent = checkbox?.disabled ? "Già presente" : selected ? "Selezionato" : "Seleziona";
  });
}

function updateAdminFranchiseSearchActions() {
  const results = state.admin.franchiseSearchResults || [];
  const existing = currentFranchiseGameKeys();
  const available = results.filter((game) => !existing.has(gameKey(game)));
  const selectedHere = available.filter((game) => franchiseSelectionHas(gameKey(game))).length;
  if (ui.adminFranchiseSearchActions) ui.adminFranchiseSearchActions.hidden = available.length === 0;
  if (ui.adminFranchiseSelectAll) {
    ui.adminFranchiseSelectAll.disabled = !available.length || selectedHere === available.length;
    ui.adminFranchiseSelectAll.textContent = `Seleziona tutti i risultati (${available.length})`;
  }
  if (ui.adminFranchiseDeselectResults) {
    ui.adminFranchiseDeselectResults.disabled = selectedHere === 0;
    ui.adminFranchiseDeselectResults.textContent = `Deseleziona questi risultati (${selectedHere})`;
  }
}

function updateAdminFranchiseSelectionUI() {
  const selected = state.admin.franchiseGameSelection || [];
  const count = selected.length;
  ui.adminFranchiseBatchToolbar.hidden = count === 0;
  ui.adminFranchiseBatchSummary.textContent = `${count} ${count === 1 ? "gioco selezionato" : "giochi selezionati"}`;

  if (count) {
    ui.adminFranchiseGameKey.value = "";
    ui.adminFranchiseGameSelected.textContent = count === 1
      ? selected[0].title
      : `${count} giochi pronti per l’inserimento`;
    ui.adminFranchiseGameSubmit.textContent = count === 1 ? "Aggiungi gioco" : `Aggiungi ${count} giochi`;
    if (!Number(ui.adminFranchiseReleaseOrder.value)) {
      ui.adminFranchiseReleaseOrder.value = String(nextFranchiseOrder("release_order"));
    }
  } else if (!ui.adminFranchiseGameKey.value) {
    ui.adminFranchiseGameSelected.textContent = "Nessun gioco selezionato";
    ui.adminFranchiseGameSubmit.textContent = "Aggiungi selezionati";
  }

  renderAdminFranchiseSelectedList();
  syncAdminFranchiseSearchRows();
  updateAdminFranchiseSearchActions();
}

function clearAdminFranchiseSelection({ resetItemForm = true, clearSearch = false } = {}) {
  state.admin.franchiseGameSelection = [];
  if (clearSearch) {
    state.admin.franchiseSearchResults = [];
    ui.adminFranchiseGameSearchResults.replaceChildren();
  }
  if (resetItemForm) {
    ui.adminFranchiseGameForm.reset();
    ui.adminFranchiseGameKey.value = "";
    ui.adminFranchiseReleaseOrder.value = state.admin.selectedFranchise
      ? String(nextFranchiseOrder("release_order"))
      : "";
    ui.adminFranchiseGameSelected.textContent = "Nessun gioco selezionato";
    ui.adminFranchiseGameSubmit.textContent = "Aggiungi selezionati";
  }
  updateAdminFranchiseSelectionUI();
}

function resetAdminFranchiseForm() {
  state.admin.selectedFranchise = null;
  ui.adminFranchiseForm.reset();
  delete ui.adminFranchiseSlug.dataset.edited;
  ui.adminFranchiseId.value = "";
  ui.adminFranchiseStatus.value = "draft";
  ui.adminFranchiseDelete.hidden = true;
  ui.adminFranchiseGamesEditor.hidden = true;
  ui.adminFranchiseGameSearchResults.replaceChildren();
  ui.adminFranchiseGames.replaceChildren();
  clearAdminFranchiseSelection({ clearSearch: true });
  setAdminEditorialMessage(ui.adminFranchiseMessage, "");
}

function resetAdminCollectionForm() {
  state.admin.selectedCollection = null;
  ui.adminCollectionForm.reset();
  delete ui.adminCollectionSlug.dataset.edited;
  ui.adminCollectionId.value = "";
  ui.adminCollectionStatus.value = "draft";
  ui.adminCollectionDelete.hidden = true;
  ui.adminCollectionGamesEditor.hidden = true;
  ui.adminCollectionGameSearchResults.replaceChildren();
  ui.adminCollectionGames.replaceChildren();
  ui.adminCollectionGameForm.reset();
  ui.adminCollectionGameKey.value = "";
  ui.adminCollectionGameSelected.textContent = "Nessun gioco selezionato";
  setAdminEditorialMessage(ui.adminCollectionMessage, "");
}

function renderAdminEditorialLists() {
  ui.adminFranchiseList.replaceChildren();
  for (const franchise of state.admin.franchises || []) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "admin-entity-button";
    button.classList.toggle("is-active", state.admin.selectedFranchise?.franchise?.id === franchise.id);
    button.innerHTML = `<span><strong>${escapeHtml(franchise.name)}</strong><small>${escapeHtml(franchise.slug)} · ${Number(franchise.game_count || 0)} giochi</small></span><b class="pill">${franchise.status === "published" ? "PUBBLICATO" : "BOZZA"}</b>`;
    button.onclick = () => openAdminFranchise(franchise.id);
    ui.adminFranchiseList.append(button);
  }
  if (!(state.admin.franchises || []).length) {
    ui.adminFranchiseList.innerHTML = `<div class="timeline-empty">Nessun franchise configurato.</div>`;
  }

  ui.adminCollectionList.replaceChildren();
  for (const collection of state.admin.collections || []) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "admin-entity-button";
    button.classList.toggle("is-active", state.admin.selectedCollection?.collection?.id === collection.id);
    button.innerHTML = `<span><strong>${escapeHtml(collection.title)}</strong><small>${escapeHtml(collection.slug)} · ${Number(collection.game_count || 0)} giochi</small></span><b class="pill">${collection.status === "published" ? "PUBBLICATA" : "BOZZA"}</b>`;
    button.onclick = () => openAdminCollection(collection.id);
    ui.adminCollectionList.append(button);
  }
  if (!(state.admin.collections || []).length) {
    ui.adminCollectionList.innerHTML = `<div class="timeline-empty">Nessuna collezione configurata.</div>`;
  }
}

async function loadAdminEditorial({ preserveSelection = true } = {}) {
  if (!window.VaultFranchises) {
    ui.adminFranchiseList.innerHTML = `<div class="timeline-empty">Modulo franchise non disponibile.</div>`;
    ui.adminCollectionList.innerHTML = `<div class="timeline-empty">Modulo franchise non disponibile.</div>`;
    return;
  }
  ui.adminFranchiseList.innerHTML = `<div class="route-loading">Caricamento franchise…</div>`;
  ui.adminCollectionList.innerHTML = `<div class="route-loading">Caricamento collezioni…</div>`;
  try {
    const [franchises, collections] = await Promise.all([
      window.VaultFranchises.listAdminFranchises(),
      window.VaultFranchises.listAdminCollections(),
    ]);
    state.admin.franchises = franchises || [];
    state.admin.collections = collections || [];
    renderAdminEditorialLists();
    if (preserveSelection && state.admin.selectedFranchise?.franchise?.id) {
      await openAdminFranchise(state.admin.selectedFranchise.franchise.id);
    }
    if (preserveSelection && state.admin.selectedCollection?.collection?.id) {
      await openAdminCollection(state.admin.selectedCollection.collection.id);
    }
  } catch (error) {
    console.error("Gestione editoriale non disponibile", error);
    ui.adminFranchiseList.innerHTML = `<div class="timeline-empty">Applica la migrazione v4.6 prima di usare questa sezione.</div>`;
    ui.adminCollectionList.innerHTML = `<div class="timeline-empty">Dati non disponibili.</div>`;
  }
}

function renderAdminFranchiseGames() {
  const data = state.admin.selectedFranchise;
  const franchise = data?.franchise;
  const games = data?.games || [];
  ui.adminFranchiseGames.replaceChildren();
  if (!franchise) return;
  ui.adminFranchiseOpen.href = franchiseRoute(franchise.slug);
  for (const game of games) {
    const card = document.createElement("article");
    card.className = "admin-editorial-game-card";
    card.innerHTML = `
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <div><strong>${escapeHtml(game.title)}</strong><span>${escapeHtml(FRANCHISE_RELATION_LABELS[game.relation_type] || game.relation_type)} · Uscita #${Number(game.release_order || 0)}${game.narrative_order ? ` · Narrativa #${Number(game.narrative_order)}` : ""}</span></div>
      <div class="admin-card-actions"><button class="button button-secondary" data-edit type="button">Modifica</button><button class="button button-danger" data-remove type="button">Rimuovi</button></div>`;
    card.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    card.querySelector("[data-edit]").onclick = () => {
      clearAdminFranchiseSelection({ resetItemForm: false });
      ui.adminFranchiseGameKey.value = gameKey(game);
      ui.adminFranchiseGameSelected.textContent = game.title;
      ui.adminFranchiseGameType.value = game.relation_type || "main";
      ui.adminFranchiseReleaseOrder.value = String(game.release_order || games.length + 1);
      ui.adminFranchiseNarrativeOrder.value = game.narrative_order || "";
      ui.adminFranchiseGameNote.value = game.franchise_note || "";
      ui.adminFranchiseGameSubmit.textContent = "Aggiorna gioco";
      ui.adminFranchiseGameForm.scrollIntoView({ behavior: "smooth", block: "center" });
    };
    card.querySelector("[data-remove]").onclick = async () => {
      if (!confirm(`Rimuovere ${game.title} dal franchise?`)) return;
      try {
        state.admin.selectedFranchise = await window.VaultFranchises.removeAdminFranchiseGame(franchise.id, gameKey(game));
        renderAdminFranchiseGames();
        await loadAdminEditorial({ preserveSelection: false });
        showToast("Gioco rimosso dal franchise.");
      } catch (error) {
        showToast(error.message || "Rimozione fallita.");
      }
    };
    ui.adminFranchiseGames.append(card);
  }
  if (!games.length) ui.adminFranchiseGames.innerHTML = `<div class="timeline-empty">Nessun gioco collegato.</div>`;
}

async function openAdminFranchise(id) {
  try {
    const data = await window.VaultFranchises.getAdminFranchise(id);
    if (!data?.franchise) throw new Error("Franchise non trovato.");
    state.admin.selectedFranchise = data;
    const franchise = data.franchise;
    ui.adminFranchiseId.value = franchise.id;
    ui.adminFranchiseName.value = franchise.name || "";
    ui.adminFranchiseSlug.value = franchise.slug || "";
    ui.adminFranchiseStatus.value = franchise.status || "draft";
    ui.adminFranchiseImage.value = franchise.hero_image_url || "";
    ui.adminFranchiseDescription.value = franchise.description || "";
    ui.adminFranchiseDelete.hidden = false;
    ui.adminFranchiseGamesEditor.hidden = false;
    clearAdminFranchiseSelection({ clearSearch: true });
    setAdminEditorialMessage(ui.adminFranchiseMessage, "");
    renderAdminFranchiseGames();
    renderAdminEditorialLists();
  } catch (error) {
    showToast(error.message || "Franchise non disponibile.");
  }
}

function renderAdminCollectionGames() {
  const data = state.admin.selectedCollection;
  const collection = data?.collection;
  const games = data?.games || [];
  ui.adminCollectionGames.replaceChildren();
  if (!collection) return;
  ui.adminCollectionOpen.href = editorialCollectionRoute(collection.slug);
  for (const game of games) {
    const card = document.createElement("article");
    card.className = "admin-editorial-game-card";
    card.innerHTML = `
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <div><strong>${escapeHtml(game.title)}</strong><span>Posizione #${Number(game.collection_position || 0)}</span></div>
      <div class="admin-card-actions"><button class="button button-secondary" data-edit type="button">Modifica</button><button class="button button-danger" data-remove type="button">Rimuovi</button></div>`;
    card.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    card.querySelector("[data-edit]").onclick = () => {
      ui.adminCollectionGameKey.value = gameKey(game);
      ui.adminCollectionGameSelected.textContent = game.title;
      ui.adminCollectionPosition.value = String(game.collection_position || games.length + 1);
      ui.adminCollectionGameNote.value = game.editorial_note || "";
      ui.adminCollectionGameForm.scrollIntoView({ behavior: "smooth", block: "center" });
    };
    card.querySelector("[data-remove]").onclick = async () => {
      if (!confirm(`Rimuovere ${game.title} dalla collezione?`)) return;
      try {
        state.admin.selectedCollection = await window.VaultFranchises.removeAdminCollectionGame(collection.id, gameKey(game));
        renderAdminCollectionGames();
        await loadAdminEditorial({ preserveSelection: false });
        showToast("Gioco rimosso dalla collezione.");
      } catch (error) {
        showToast(error.message || "Rimozione fallita.");
      }
    };
    ui.adminCollectionGames.append(card);
  }
  if (!games.length) ui.adminCollectionGames.innerHTML = `<div class="timeline-empty">Nessun gioco collegato.</div>`;
}

async function openAdminCollection(id) {
  try {
    const data = await window.VaultFranchises.getAdminCollection(id);
    if (!data?.collection) throw new Error("Collezione non trovata.");
    state.admin.selectedCollection = data;
    const collection = data.collection;
    ui.adminCollectionId.value = collection.id;
    ui.adminCollectionTitle.value = collection.title || "";
    ui.adminCollectionSlug.value = collection.slug || "";
    ui.adminCollectionStatus.value = collection.status || "draft";
    ui.adminCollectionImage.value = collection.cover_image_url || "";
    ui.adminCollectionDescription.value = collection.description || "";
    ui.adminCollectionCuratorNote.value = collection.curator_note || "";
    ui.adminCollectionDelete.hidden = false;
    ui.adminCollectionGamesEditor.hidden = false;
    setAdminEditorialMessage(ui.adminCollectionMessage, "");
    renderAdminCollectionGames();
    renderAdminEditorialLists();
  } catch (error) {
    showToast(error.message || "Collezione non disponibile.");
  }
}

function renderAdminEditorialSearchResults(container, games, kind) {
  container.replaceChildren();
  if (!games.length) {
    if (kind === "franchise") {
      state.admin.franchiseSearchResults = [];
      updateAdminFranchiseSearchActions();
    }
    container.innerHTML = `<div class="timeline-empty">Nessun gioco trovato.</div>`;
    return;
  }

  const existingFranchiseKeys = currentFranchiseGameKeys();
  if (kind === "franchise") state.admin.franchiseSearchResults = games;

  for (const game of games) {
    const key = gameKey(game);
    if (kind === "franchise") {
      const alreadyLinked = existingFranchiseKeys.has(key);
      const row = document.createElement("label");
      row.className = "admin-result-item admin-result-check";
      row.dataset.franchiseGameKey = key;
      row.innerHTML = `
        <input class="admin-result-checkbox" type="checkbox" ${alreadyLinked ? "disabled" : ""}>
        <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
        <span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(game.match_key || game.canonical_id || "")}</small></span>
        <b>${alreadyLinked ? "Già presente" : "Seleziona"}</b>`;
      row.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
      const checkbox = row.querySelector(".admin-result-checkbox");
      checkbox.checked = franchiseSelectionHas(key);
      row.classList.toggle("is-selected", checkbox.checked);
      checkbox.addEventListener("change", () => {
        setAdminFranchiseGameSelection(game, checkbox.checked);
        updateAdminFranchiseSelectionUI();
      });
      container.append(row);
      continue;
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "admin-result-item";
    button.innerHTML = `<img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt=""><span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(game.match_key || game.canonical_id || "")}</small></span><b>Seleziona</b>`;
    button.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    button.onclick = () => {
      const gamesCount = state.admin.selectedCollection?.games?.length || 0;
      ui.adminCollectionGameKey.value = key;
      ui.adminCollectionGameSelected.textContent = game.title;
      ui.adminCollectionPosition.value = String(gamesCount + 1);
      ui.adminCollectionGameNote.value = "";
      container.replaceChildren();
    };
    container.append(button);
  }

  if (kind === "franchise") updateAdminFranchiseSelectionUI();
}

async function searchAdminEditorialGames(kind) {
  const input = kind === "franchise" ? ui.adminFranchiseGameSearch : ui.adminCollectionGameSearch;
  const container = kind === "franchise" ? ui.adminFranchiseGameSearchResults : ui.adminCollectionGameSearchResults;
  const query = input.value.trim();
  if (query.length < 2) return;
  container.innerHTML = `<div class="route-loading">Ricerca…</div>`;
  try {
    const result = await window.VaultCatalog.search({ query, limit: kind === "franchise" ? 50 : 12, offset: 0, force: true });
    renderAdminEditorialSearchResults(container, result.items || [], kind);
  } catch (error) {
    console.error("Ricerca gioco editoriale fallita", error);
    container.innerHTML = `<div class="timeline-empty">Ricerca non disponibile.</div>`;
  }
}

async function loadAdminMatches() {
  ui.adminMatchList.innerHTML = `<div class="route-loading">Caricamento coda…</div>`;
  try {
    const result = await window.VaultAdmin.listMatches({ status: ui.adminMatchStatus.value });
    state.admin.matches = result?.items || [];
    ui.adminMatchList.replaceChildren();
    if (!state.admin.matches.length) {
      ui.adminMatchList.innerHTML = `<div class="timeline-empty">Nessun match in questa sezione.</div>`;
      return;
    }
    for (const match of state.admin.matches) {
      const card = document.createElement("article");
      card.className = "admin-action-card";
      card.innerHTML = `
        <div class="admin-action-card-head"><span class="pill">${Math.round(Number(match.confidence || 0) * 100)}%</span><small>${escapeHtml(match.status)}</small></div>
        <div class="admin-match-pair"><div><small>${escapeHtml(match.source_store)}</small><strong>${escapeHtml(match.source_title)}</strong><span>${escapeHtml(match.source_external_id)}</span></div><b>⇄</b><div><small>${escapeHtml(match.candidate_store)}</small><strong>${escapeHtml(match.candidate_title)}</strong><span>${escapeHtml(match.candidate_external_id)}</span></div></div>
        <label>Nota revisione<textarea rows="2" maxlength="1000"></textarea></label>
        <div class="admin-card-actions"><button class="button button-primary admin-match-verify" type="button">Conferma</button><button class="button button-danger admin-match-reject" type="button">Rifiuta</button></div>`;
      const note = card.querySelector("textarea");
      card.querySelector(".admin-match-verify").onclick = async () => {
        await window.VaultAdmin.reviewMatch(match.id, "verified", { note: note.value });
        showToast("Match confermato.");
        await loadAdminMatches();
      };
      card.querySelector(".admin-match-reject").onclick = async () => {
        await window.VaultAdmin.reviewMatch(match.id, "rejected", { note: note.value });
        showToast("Match rifiutato.");
        await loadAdminMatches();
      };
      ui.adminMatchList.append(card);
    }
  } catch (error) {
    console.error("Coda matching non disponibile", error);
    ui.adminMatchList.innerHTML = `<div class="timeline-empty">Coda non disponibile.</div>`;
  }
}

async function loadAdminReports() {
  ui.adminReportList.innerHTML = `<div class="route-loading">Caricamento segnalazioni…</div>`;
  try {
    const result = await window.VaultAdmin.listReports({ status: ui.adminReportStatus.value });
    state.admin.reports = result?.items || [];
    ui.adminReportList.replaceChildren();
    if (!state.admin.reports.length) {
      ui.adminReportList.innerHTML = `<div class="timeline-empty">Nessuna segnalazione in questa sezione.</div>`;
      return;
    }
    for (const report of state.admin.reports) {
      const target = report.target || {};
      const card = document.createElement("article");
      card.className = "admin-action-card";
      card.innerHTML = `
        <div class="admin-action-card-head"><span class="pill">${escapeHtml(report.target_type)}</span><small>${formatDate(report.created_at, true)}</small></div>
        <h3>${escapeHtml(target.label || "Contenuto non più disponibile")}</h3>
        <p>${escapeHtml(target.body || "")}</p>
        <blockquote>${escapeHtml(report.reason)}</blockquote>
        <small>Segnalato da @${escapeHtml(report.reporter_username || "utente")}</small>
        <label>Nota moderazione<textarea rows="2" maxlength="2000"></textarea></label>
        <div class="admin-card-actions"><button class="button button-secondary admin-report-dismiss" type="button">Archivia</button><button class="button button-danger admin-report-remove" type="button">Rimuovi contenuto</button></div>`;
      const note = card.querySelector("textarea");
      card.querySelector(".admin-report-dismiss").onclick = async () => {
        await window.VaultAdmin.resolveReport(report.id, "dismiss", note.value);
        showToast("Segnalazione archiviata.");
        await loadAdminReports();
      };
      card.querySelector(".admin-report-remove").onclick = async () => {
        if (!confirm("Rimuovere definitivamente il contenuto segnalato?")) return;
        await window.VaultAdmin.resolveReport(report.id, "remove", note.value);
        showToast("Contenuto rimosso.");
        await loadAdminReports();
      };
      ui.adminReportList.append(card);
    }
  } catch (error) {
    console.error("Moderazione non disponibile", error);
    ui.adminReportList.innerHTML = `<div class="timeline-empty">Segnalazioni non disponibili.</div>`;
  }
}

async function loadAdminSystemStatus() {
  ui.adminSystemStats.innerHTML = `<div class="route-loading">Lettura metriche…</div>`;
  ui.adminSyncList.replaceChildren();
  try {
    const status = await window.VaultAdmin.getSystemStatus();
    state.admin.system = status;
    const limit = 500 * 1024 * 1024;
    const ratio = Math.min(100, Math.round((Number(status.database_size_bytes || 0) / limit) * 100));
    const stats = [
      ["Database", `${formatBytes(status.database_size_bytes)} · ${ratio}% del piano Free`],
      ["Catalogo", formatBytes(status.catalog_size_bytes)],
      ["Giochi canonici", Number(status.catalog_games || 0).toLocaleString("it-IT")],
      ["Listing", Number(status.catalog_listings || 0).toLocaleString("it-IT")],
      ["Match da revisionare", Number(status.pending_matches || 0).toLocaleString("it-IT")],
      ["Segnalazioni aperte", Number(status.open_reports || 0).toLocaleString("it-IT")],
    ];
    ui.adminSystemStats.replaceChildren();
    for (const [label, value] of stats) {
      const item = document.createElement("article");
      item.innerHTML = `<small>${escapeHtml(label)}</small><strong>${escapeHtml(value)}</strong>`;
      ui.adminSystemStats.append(item);
    }
    for (const sync of status.sync || []) {
      const card = document.createElement("article");
      card.className = "admin-sync-card";
      card.innerHTML = `<div><strong>${escapeHtml(storeLabel(sync.store))}</strong><span>${escapeHtml(sync.status || "unknown")}</span></div><small>${Number(sync.listing_count || 0).toLocaleString("it-IT")} listing · ${sync.completed_at ? formatDate(sync.completed_at, true) : "mai completato"}</small>${sync.error_message ? `<p>${escapeHtml(sync.error_message)}</p>` : ""}`;
      ui.adminSyncList.append(card);
    }
  } catch (error) {
    console.error("Stato sistema non disponibile", error);
    ui.adminSystemStats.innerHTML = `<div class="timeline-empty">Metriche non disponibili.</div>`;
  }
}

async function requestContentReport(targetType, targetId, label) {
  if (!state.auth.user) {
    navigate("#/login");
    return;
  }
  const reason = window.prompt(`Perché vuoi segnalare ${label || "questo contenuto"}?`);
  if (reason === null) return;
  try {
    await window.VaultSocial.reportContent(targetType, targetId, reason);
    showToast("Segnalazione inviata ai moderatori.");
  } catch (error) {
    showToast(error.message || "Segnalazione non inviata.");
  }
}

function renderAuthPage() {
  const mode = state.route.name;
  const isRegister = mode === "register";
  const isForgot = mode === "forgot-password";
  const isReset = mode === "reset-password";
  const isCallback = mode === "auth-callback" || state.route.query.get("confirmed") === "1";
  const titles = {
    register: "Registrati",
    "forgot-password": "Recupera password",
    "reset-password": "Nuova password",
  };
  updateDocumentTitle(titles[mode] || "Accedi");
  ui.authConfigWarning.hidden = Boolean(window.VaultAuth?.configured);
  ui.loginForm.hidden = isRegister || isForgot || isReset || isCallback;
  ui.registerForm.hidden = !isRegister || isCallback;
  ui.forgotPasswordForm.hidden = !isForgot;
  ui.resetPasswordForm.hidden = !isReset;
  ui.authConfirmation.hidden = !isCallback;

  ui.authEyebrow.textContent = isCallback ? "EMAIL CONFERMATA" : "THE FREE VAULT ACCOUNT";
  ui.authTitle.textContent = isCallback
    ? "Account attivato"
    : isRegister
      ? "Crea il tuo account"
      : isForgot
        ? "Recupera la password"
        : isReset
          ? "Scegli una nuova password"
          : "Bentornato";
  ui.authSubtitle.textContent = isCallback
    ? "La conferma è andata a buon fine."
    : isRegister
      ? "Servono solo username, email e password. Il resto si completa dal profilo."
      : isForgot
        ? "Riceverai un link sicuro per impostare una nuova password."
        : isReset
          ? "Inserisci una password nuova di almeno otto caratteri."
          : "Accedi con email e password per sincronizzare il tuo Vault.";

  if (isReset && !state.auth.user && !window.VaultAuth?.recoveryMode) {
    ui.resetPasswordError.textContent = "Il link di recupero non è valido o è scaduto. Richiedine uno nuovo.";
    ui.resetPasswordError.hidden = false;
    ui.resetPasswordSubmit.disabled = true;
  } else if (isReset) {
    ui.resetPasswordError.hidden = true;
    ui.resetPasswordSubmit.disabled = false;
  }

  if (state.auth.user && !isCallback && !isReset) {
    navigate("#/profile");
    return;
  }
  if (state.route.query.get("registered") === "1") {
    ui.authSubtitle.textContent = "Registrazione inviata. Controlla la posta e conferma l’indirizzo email, poi accedi.";
  }
}

function profileStats() {
  const entries = Object.values(state.library);
  const journal = window.VaultJournal?.summarize() || { sessionMinutes: 0, sessions: 0 };
  return {
    library: entries.length,
    completed: entries.filter((entry) => entry.status === "completed").length,
    favorites: entries.filter((entry) => entry.favorite).length,
    lists: Object.keys(state.lists).length,
    hours: formatMinutes(journal.sessionMinutes),
    sessions: journal.sessions,
  };
}

function renderProfileRecentGames() {
  ui.profileRecentGames.replaceChildren();
  const entries = Object.values(state.library)
    .filter((entry) => entry?.game)
    .sort((a, b) => new Date(b.addedAt || b.updatedAt || 0) - new Date(a.addedAt || a.updatedAt || 0))
    .slice(0, 5);
  if (!entries.length) {
    ui.profileRecentGames.innerHTML = `<div class="timeline-empty">La libreria è ancora vuota.</div>`;
    return;
  }
  for (const entry of entries) {
    const game = entry.game;
    const link = document.createElement("a");
    link.className = "profile-game-row";
    link.href = gameRoute(game);
    link.innerHTML = `
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(entry.status || "In libreria")}</small></span>
      <span>→</span>`;
    ui.profileRecentGames.append(link);
  }
}

function renderProfilePage() {
  const { user, profile, configured } = state.auth;
  updateDocumentTitle("Profilo");
  ui.profileSignedOut.hidden = Boolean(user);
  ui.profileSignedIn.hidden = !user;
  if (!user) {
    if (!configured) ui.profileSignedOut.querySelector("p:last-of-type").textContent = "Configura Supabase per abilitare gli account cloud.";
    return;
  }

  const displayName = profile?.display_name || profile?.username || "Profilo";
  applyAvatar(ui.profilePageAvatar, user, profile);
  ui.profilePageName.textContent = displayName;
  ui.profilePageHandle.textContent = profile?.username ? `@${profile.username}` : "";
  ui.profilePageBio.textContent = profile?.bio || "Nessuna bio inserita.";
  ui.profilePageEmail.textContent = user.email || "";
  ui.profileVisibilityBadge.textContent = profile?.is_public === false ? "Profilo privato" : "Profilo pubblico";
  ui.viewPublicProfile.hidden = !profile?.username || profile?.is_public === false;
  if (profile?.username) ui.viewPublicProfile.href = profileRoute(profile.username);
  ui.profileUsername.value = profile?.username || "";
  ui.profileDisplayName.value = profile?.display_name || profile?.username || "";
  ui.profileBio.value = profile?.bio || "";

  const stats = profileStats();
  $("#profile-stat-library").textContent = stats.library;
  $("#profile-stat-completed").textContent = stats.completed;
  $("#profile-stat-favorites").textContent = stats.favorites;
  $("#profile-stat-lists").textContent = stats.lists;
  $("#profile-stat-hours").textContent = stats.hours;
  $("#profile-stat-sessions").textContent = stats.sessions;
  renderProfileRecentGames();
}


async function renderSteamConnectionPanel() {
  if (!ui.steamConnectionCard) return;
  const user = state.auth.user;
  ui.steamSyncMessage.hidden = true;

  if (!user || !window.VaultSteam) {
    ui.steamConnectionName.textContent = "Steam non collegato";
    ui.steamConnectionId.textContent = "Accedi a The Free Vault per collegare Steam.";
    ui.steamConnectionStatus.textContent = "";
    ui.steamConnectButton.hidden = !user;
    ui.steamSyncButton.hidden = true;
    ui.steamDisconnectButton.hidden = true;
    return;
  }

  try {
    const connection = await window.VaultSteam.getConnection();
    const linked = Boolean(connection?.steam_id);
    ui.steamConnectButton.hidden = linked;
    ui.steamSyncButton.hidden = !linked;
    ui.steamDisconnectButton.hidden = !linked;

    if (!linked) {
      ui.steamConnectionAvatar.textContent = "S";
      ui.steamConnectionAvatar.style.backgroundImage = "";
      ui.steamConnectionName.textContent = "Steam non collegato";
      ui.steamConnectionId.textContent = "Usa Steam OpenID per verificare il tuo SteamID.";
      ui.steamConnectionStatus.textContent = "Nessuna libreria importata.";
      return;
    }

    ui.steamConnectionName.textContent = connection.persona_name || "Account Steam";
    ui.steamConnectionId.textContent = `SteamID ${connection.steam_id}`;
    ui.steamConnectionStatus.textContent = connection.last_sync_at
      ? `Ultima sincronizzazione: ${formatDate(connection.last_sync_at, true)}`
      : "Account collegato, libreria non ancora importata.";
    if (connection.avatar_url) {
      ui.steamConnectionAvatar.textContent = "";
      ui.steamConnectionAvatar.style.backgroundImage = `url("${connection.avatar_url}")`;
    } else {
      ui.steamConnectionAvatar.textContent = "S";
      ui.steamConnectionAvatar.style.backgroundImage = "";
    }
  } catch (error) {
    console.error(error);
    ui.steamSyncMessage.textContent = error.message || "Impossibile leggere il collegamento Steam.";
    ui.steamSyncMessage.hidden = false;
  }
}

function importSteamLibrary(games) {
  if (!Array.isArray(games)) return { imported: 0, unmatched: 0 };
  const steamListings = new Map(
    state.catalog
      .map(normalizeCatalog)
      .filter((game) => game.store === "steam")
      .map((game) => [String(game.external_id), game])
  );

  let imported = 0;
  let unmatched = 0;
  const now = new Date().toISOString();

  for (const owned of games) {
    const appid = String(owned.appid || owned.external_id || "");
    if (!appid) continue;
    const listing = steamListings.get(appid);
    const game = listing || {
      match_key: owned.match_key,
      canonical_id: owned.canonical_id,
      listing_id: `steam:${appid}`,
      internal_id: `steam:${appid}`,
      store: "steam",
      stores: ["steam"],
      external_id: appid,
      title: owned.name || `Steam App ${appid}`,
      description: "",
      image_url: owned.img_icon_url
        ? `https://media.steampowered.com/steamcommunity/public/images/apps/${appid}/${owned.img_icon_url}.jpg`
        : `https://cdn.akamai.steamstatic.com/steam/apps/${appid}/header.jpg`,
      store_url: `https://store.steampowered.com/app/${appid}/`,
      category_group: "base_game",
      market_segment: "unclassified",
      source_kind: "catalog",
      platforms: ["pc"],
    };

    if (!listing) unmatched += 1;
    const key = gameKey(game);
    const previous = state.library[key] || {
      addedAt: now,
      status: "saved",
      favorite: false,
      rating: 0,
      notes: "",
    };
    const ownedStores = new Set(previous.ownedStores || []);
    ownedStores.add("steam");
    state.library[key] = {
      ...previous,
      ownedStores: [...ownedStores],
      steamPlaytimeMinutes: Number(owned.playtime_forever || owned.playtime_minutes || 0),
      steamLastPlayedAt: owned.rtime_last_played
        ? new Date(Number(owned.rtime_last_played) * 1000).toISOString()
        : previous.steamLastPlayedAt || null,
      updatedAt: now,
      game: snapshotGame({ ...game, stores: [...new Set([...(game.stores || []), "steam"])] }),
    };
    imported += 1;
  }

  saveLibrary();
  rebuildGameIndex();
  return { imported, unmatched };
}

function renderSettingsPage() {
  const { user, profile, settings, configured } = state.auth;
  updateDocumentTitle("Impostazioni");
  ui.settingsSignedOut.hidden = Boolean(user);
  ui.settingsSignedIn.hidden = !user;
  if (!user) {
    if (!configured) ui.settingsSignedOut.querySelector("p:last-of-type").textContent = "Configura Supabase per abilitare gli account cloud.";
    return;
  }

  const section = ["profile", "account", "connections", "privacy", "data"].includes(state.route.params.section)
    ? state.route.params.section
    : "profile";
  $$('[data-settings-tab]').forEach((link) => link.classList.toggle('is-active', link.dataset.settingsTab === section));
  $$('.settings-panel').forEach((panel) => { panel.hidden = panel.id !== `settings-panel-${section}`; });

  applyAvatar(ui.settingsAvatarPreview, user, profile);
  ui.avatarRemoveButton.disabled = !profile?.avatar_url;
  ui.profileUsername.value = profile?.username || "";
  ui.profileDisplayName.value = profile?.display_name || profile?.username || "";
  ui.profileBio.value = profile?.bio || "";
  ui.changeEmailValue.value = user.email || "";
  ui.privacyPublic.checked = profile?.is_public !== false;
  ui.privacyLibrary.checked = settings?.show_library !== false;
  ui.privacyLists.checked = settings?.show_lists !== false;
  ui.privacyActivity.checked = settings?.show_activity !== false;
  ui.privacyDiary.checked = settings?.show_diary !== false;
  ui.privacyEmails.checked = settings?.email_notifications !== false;
  if (section === "connections") void renderSteamConnectionPanel();
}

async function synchronizeSignedInUser(snapshot) {
  updateAccountUI(snapshot);

  const nextUserId = snapshot.user?.id || null;
  const accountChanged = nextUserId !== activeStorageUserId;
  if (accountChanged) {
    personalStorageGeneration += 1;
    window.VaultCatalog?.clearRecommendationCache?.();
    state.discoveryRecommendations = null;
    synchronizedAccountId = null;
    window.VaultCloud?.cancelScheduledPush();
    switchPersonalStorage(nextUserId);

    try {
      await window.VaultJournal?.setUser(nextUserId);
    } catch (journalError) {
      console.error("Caricamento diario fallito", journalError);
    }
  }

  const generation = personalStorageGeneration;

  if (!snapshot.user) {
    if (ui.cloudStatus) ui.cloudStatus.textContent = "Solo locale";
    refreshCurrentPersonalView();
    return;
  }

  if (synchronizedAccountId === nextUserId) {
    refreshCurrentPersonalView();
    return;
  }

  ui.cloudStatus.textContent = "Sincronizzazione…";
  try {
    const merged = await window.VaultCloud.pull(
      state.library,
      state.lists,
      nextUserId,
    );

    if (
      generation !== personalStorageGeneration ||
      window.VaultAuth?.user?.id !== nextUserId
    ) {
      return;
    }

    state.library = merged.library;
    state.lists = merged.lists;
    persistPersonalDataLocally();

    await window.VaultCloud.push(state.library, state.lists, nextUserId);

    if (
      generation !== personalStorageGeneration ||
      window.VaultAuth?.user?.id !== nextUserId
    ) {
      return;
    }

    synchronizedAccountId = nextUserId;
    rebuildGameIndex();
    ui.cloudStatus.textContent = "Sincronizzato";
    refreshCurrentPersonalView();
    void refreshNotificationCount();
  } catch (error) {
    if (generation !== personalStorageGeneration) return;
    console.error(error);
    ui.cloudStatus.textContent = "Errore di sincronizzazione";
    showToast("Accesso riuscito, ma la sincronizzazione cloud è fallita.");
  }
}

function refreshCurrentPersonalView() {
  if (state.route.name === "profile") renderProfilePage();
  if (state.route.name === "settings") renderSettingsPage();
  if (state.route.name === "game") void renderGamePage();
  if (state.route.name === "public-profile") void renderPublicProfilePage();
  if (state.route.name === "list") void renderSharedListPage();
  if (state.route.name === "feed") void renderFeedPage();
  if (state.route.name === "explore") void renderExplorePage();
  if (state.route.name === "notifications") void renderNotificationsPage();

  if (state.route.name === "diary") renderDiaryPage();
  if (state.route.name === "stats") void renderStatsPage();
  if (state.route.name === "admin") void renderAdminPage();
  if (state.route.name === "discover") void renderDiscoveryPage({ force: true });
  if (routeToDashboardView(state.route.name)) renderDashboard();
}

async function initializeUserSystem() {
  if (!window.VaultAuth) return;
  window.VaultAuth.subscribe((snapshot) => {
    synchronizeSignedInUser(snapshot);
  });
  try {
    const result = await window.VaultAuth.initialize();
    if (result?.returnKind === "confirmation" && result.session) {
      showToast("Email confermata correttamente.");
      handleRoute();
    }
    if (result?.returnKind === "recovery" && result.session) {
      handleRoute();
    }
  } catch (error) {
    console.error("Inizializzazione account fallita", error);
    showToast("Servizio account temporaneamente non disponibile.");
  }
}


function migratePersonalDataToCanonicalKeys() {
  const aliasMap = new Map();
  const signatureMap = new Map();

  for (const rawGame of state.catalog) {
    const game = normalizeCatalog(rawGame);
    for (const alias of gameAliases(game)) aliasMap.set(alias, game);
    const signature = [
      String(game.title || "").trim().toLocaleLowerCase("it"),
      String(game.developer || game.publisher || "").trim().toLocaleLowerCase("it"),
    ].join("|");
    signatureMap.set(signature, game);
  }

  let libraryChanged = false;
  const movedKeys = [];
  const nextLibrary = { ...state.library };

  for (const [oldKey, entry] of Object.entries(state.library)) {
    const snapshot = entry?.game || {};
    let candidate = null;
    for (const alias of [oldKey, ...gameAliases(snapshot)]) {
      candidate = aliasMap.get(alias);
      if (candidate) break;
    }

    if (!candidate && snapshot.title) {
      const signature = [
        String(snapshot.title).trim().toLocaleLowerCase("it"),
        String(snapshot.developer || snapshot.publisher || "").trim().toLocaleLowerCase("it"),
      ].join("|");
      candidate = signatureMap.get(signature);
    }

    const canonicalKey = candidate ? gameKey(candidate) : null;
    if (!canonicalKey || canonicalKey === oldKey) continue;

    const existing = nextLibrary[canonicalKey];
    nextLibrary[canonicalKey] = {
      ...(entry || {}),
      ...(existing || {}),
      game: snapshotGame({ ...snapshot, ...candidate }),
      updatedAt: new Date().toISOString(),
    };
    delete nextLibrary[oldKey];
    movedKeys.push([oldKey, canonicalKey]);
    libraryChanged = true;
  }

  let listsChanged = false;
  if (movedKeys.length) {
    const replacements = new Map(movedKeys);
    for (const list of Object.values(state.lists)) {
      const updated = (list.games || []).map((key) => replacements.get(key) || key);
      const deduplicated = [...new Set(updated)];
      if (JSON.stringify(deduplicated) !== JSON.stringify(list.games || [])) {
        list.games = deduplicated;
        list.updatedAt = new Date().toISOString();
        listsChanged = true;
      }
    }
  }

  if (libraryChanged) {
    state.library = nextLibrary;
    persistPersonalDataLocally();
    for (const [oldKey] of movedKeys) {
      window.VaultCloud?.deleteLibraryItem(oldKey).catch(console.error);
    }
  }
  if (listsChanged) persistPersonalDataLocally();
  if (libraryChanged || listsChanged) {
    window.VaultCloud?.schedulePush(state.library, state.lists);
  }
}


async function fetchOptionalJson(url, fallback) {
  try {
    const response = await fetch(`${url}?v=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) return fallback;
    return await response.json();
  } catch (error) {
    console.warn(`Dati opzionali non disponibili: ${url}`, error);
    return fallback;
  }
}

async function loadData() {
  ui.refresh.disabled = true;
  ui.status.hidden = true;
  try {
    const promotionsResponse = await fetch(`${DATA_URL}?v=${Date.now()}`, { cache: "no-store" });
    if (!promotionsResponse.ok) throw new Error(`Promotions HTTP ${promotionsResponse.status}`);

    const [promotions, history, catalogStats] = await Promise.all([
      promotionsResponse.json(),
      fetchOptionalJson(HISTORY_URL, { games: [] }),
      window.VaultCatalog?.configured()
        ? window.VaultCatalog.getStats({ force: true }).catch((error) => {
            console.warn("Statistiche catalogo non disponibili", error);
            return { total_listings: 0, total_games: 0, stores: {}, years: [], sync: [] };
          })
        : Promise.resolve({ total_listings: 0, total_games: 0, stores: {}, years: [], sync: [] }),
    ]);

    state.current = promotions.current || [];
    state.upcoming = promotions.upcoming || [];
    state.history = history.games || history.history || [];
    state.catalog = [];
    state.catalogMeta = catalogStats;
    state.dataLoaded = true;
    rebuildGameIndex();
    migratePersonalDataToCanonicalKeys();
    ui.sidebarUpdate.textContent = promotions.generated_at
      ? `Aggiornato ${formatDate(promotions.generated_at, true)}`
      : "Dati caricati";
    handleRoute();
  } catch (error) {
    console.error(error);
    state.dataLoaded = true;
    ui.status.hidden = false;
    ui.status.textContent = "Impossibile aggiornare tutti i dati. Il tracker può continuare a usare la cache disponibile.";
    handleRoute();
  } finally {
    ui.refresh.disabled = false;
  }
}

function updateCountdowns() {
  $$(".countdown").forEach((node) => {
    const key = node.closest(".game-card")?.dataset?.gameKey;
    const game = key ? resolveGameByKey(key) : null;
    if (game) node.textContent = countdownText(game);
  });
  if (!ui.hero.hidden && state.current[0]) ui.heroCountdown.textContent = countdownText(normalizePromotion(state.current[0]));
}

function exportData() {
  const payload = {
    app: "The Free Vault",
    schemaVersion: 5,
    exportedAt: new Date().toISOString(),
    library: state.library,
    lists: state.lists,
    journal: window.VaultJournal?.snapshot() || { progress: {}, entries: {} },
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `the-free-vault-backup-${new Date().toISOString().slice(0, 10)}.json`;
  link.click();
  URL.revokeObjectURL(url);
}

async function importData(file) {
  if (!file) return;
  try {
    const payload = JSON.parse(await file.text());
    state.library = { ...state.library, ...(payload.library || {}) };

    const importedLists = Object.values(payload.lists || {}).reduce((result, list) => {
      const id = crypto.randomUUID();
      result[id] = {
        ...list,
        id,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      return result;
    }, {});
    state.lists = { ...state.lists, ...importedLists };

    saveLibrary();
    saveLists();
    if (payload.journal) await window.VaultJournal?.importData(payload.journal);
    rebuildGameIndex();
    handleRoute();
    showToast("Backup importato.");
  } catch (error) {
    console.error(error);
    showToast("File non valido.");
  } finally {
    ui.importLibraryFile.value = "";
  }
}

ui.menuButton?.addEventListener("click", openMobileMenu);
ui.sidebarClose?.addEventListener("click", requestCloseMobileMenu);
ui.sidebarBackdrop?.addEventListener("click", requestCloseMobileMenu);
ui.mobileFilterToggle?.addEventListener("click", openMobileFilters);
ui.mobileFilterClose?.addEventListener("click", requestCloseMobileFilters);
ui.mobileFilterApply?.addEventListener("click", requestCloseMobileFilters);
ui.filterBackdrop?.addEventListener("click", requestCloseMobileFilters);

ui.adminCatalogSearchForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  await searchAdminCatalog();
});

ui.adminOverrideForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const matchKey = state.admin.selectedCatalog?.game?.match_key;
  if (!matchKey) return;
  const { patch, lockedFields } = adminOverridePayload();
  ui.adminOverrideMessage.hidden = true;
  try {
    const record = await window.VaultAdmin.saveCatalogOverride(matchKey, patch, lockedFields);
    state.admin.selectedCatalog = record;
    populateAdminOverrideForm(record);
    ui.adminCatalogTitle.textContent = record.game.title;
    ui.adminOverrideMessage.textContent = "Override salvato e protetto dai prossimi sync.";
    ui.adminOverrideMessage.classList.add("auth-success");
    ui.adminOverrideMessage.hidden = false;
    window.VaultCatalog?.clearCache();
  } catch (error) {
    ui.adminOverrideMessage.classList.remove("auth-success");
    ui.adminOverrideMessage.textContent = error.message || "Salvataggio override fallito.";
    ui.adminOverrideMessage.hidden = false;
  }
});

ui.adminClearOverride?.addEventListener("click", async () => {
  const matchKey = state.admin.selectedCatalog?.game?.match_key;
  if (!matchKey || !confirm("Rimuovere l’override? I dati automatici torneranno al prossimo sync.")) return;
  try {
    const result = await window.VaultAdmin.clearCatalogOverride(matchKey);
    state.admin.selectedCatalog.override = null;
    populateAdminOverrideForm(state.admin.selectedCatalog);
    showToast(result?.message || "Override rimosso.");
  } catch (error) {
    showToast(error.message || "Rimozione override fallita.");
  }
});


$$('[data-franchise-order]').forEach((button) => {
  button.addEventListener("click", () => {
    state.franchiseOrder = button.dataset.franchiseOrder === "narrative" ? "narrative" : "release";
    $$('[data-franchise-order]').forEach((item) => item.classList.toggle("is-active", item === button));
    renderFranchiseSections();
  });
});

ui.adminEditorialRefresh?.addEventListener("click", () => loadAdminEditorial());
ui.adminFranchiseNew?.addEventListener("click", resetAdminFranchiseForm);
ui.adminCollectionNew?.addEventListener("click", resetAdminCollectionForm);

ui.adminFranchiseName?.addEventListener("input", () => {
  if (!ui.adminFranchiseId.value && !ui.adminFranchiseSlug.dataset.edited) {
    ui.adminFranchiseSlug.value = editorialSlug(ui.adminFranchiseName.value);
  }
});
ui.adminFranchiseSlug?.addEventListener("input", () => { ui.adminFranchiseSlug.dataset.edited = "1"; });
ui.adminCollectionTitle?.addEventListener("input", () => {
  if (!ui.adminCollectionId.value && !ui.adminCollectionSlug.dataset.edited) {
    ui.adminCollectionSlug.value = editorialSlug(ui.adminCollectionTitle.value);
  }
});
ui.adminCollectionSlug?.addEventListener("input", () => { ui.adminCollectionSlug.dataset.edited = "1"; });

ui.adminFranchiseForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  setAdminEditorialMessage(ui.adminFranchiseMessage, "");
  try {
    const data = await window.VaultFranchises.saveAdminFranchise({
      id: ui.adminFranchiseId.value || null,
      name: ui.adminFranchiseName.value,
      slug: ui.adminFranchiseSlug.value,
      description: ui.adminFranchiseDescription.value,
      heroImageUrl: ui.adminFranchiseImage.value,
      status: ui.adminFranchiseStatus.value,
    });
    state.admin.selectedFranchise = data;
    ui.adminFranchiseSlug.dataset.edited = "";
    await loadAdminEditorial({ preserveSelection: false });
    await openAdminFranchise(data.franchise.id);
    setAdminEditorialMessage(ui.adminFranchiseMessage, "Franchise salvato.", true);
  } catch (error) {
    setAdminEditorialMessage(ui.adminFranchiseMessage, error.message || "Salvataggio fallito.");
  }
});

ui.adminFranchiseDelete?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise || !confirm(`Eliminare definitivamente il franchise ${franchise.name}?`)) return;
  try {
    await window.VaultFranchises.deleteAdminFranchise(franchise.id);
    resetAdminFranchiseForm();
    await loadAdminEditorial({ preserveSelection: false });
    showToast("Franchise eliminato.");
  } catch (error) {
    showToast(error.message || "Eliminazione fallita.");
  }
});

ui.adminFranchiseGameSearchForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  await searchAdminEditorialGames("franchise");
});

ui.adminFranchiseSelectAll?.addEventListener("click", () => {
  const existing = currentFranchiseGameKeys();
  for (const game of state.admin.franchiseSearchResults || []) {
    if (!existing.has(gameKey(game))) setAdminFranchiseGameSelection(game, true);
  }
  updateAdminFranchiseSelectionUI();
});

ui.adminFranchiseDeselectResults?.addEventListener("click", () => {
  const visibleKeys = new Set((state.admin.franchiseSearchResults || []).map((game) => gameKey(game)));
  state.admin.franchiseGameSelection = (state.admin.franchiseGameSelection || [])
    .filter((game) => !visibleKeys.has(gameKey(game)));
  updateAdminFranchiseSelectionUI();
});

ui.adminFranchiseSortRelease?.addEventListener("click", () => {
  state.admin.franchiseGameSelection = [...(state.admin.franchiseGameSelection || [])]
    .sort((a, b) => franchiseReleaseSortValue(a) - franchiseReleaseSortValue(b)
      || String(a.title || "").localeCompare(String(b.title || ""), "it"));
  updateAdminFranchiseSelectionUI();
});

ui.adminFranchiseBatchClear?.addEventListener("click", () => {
  clearAdminFranchiseSelection();
});

ui.adminFranchiseGameForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const franchise = state.admin.selectedFranchise?.franchise;
  const selected = state.admin.franchiseGameSelection || [];
  const editingKey = ui.adminFranchiseGameKey.value;
  if (!franchise || (!selected.length && !editingKey)) {
    showToast("Seleziona prima uno o più giochi.");
    return;
  }

  try {
    if (selected.length) {
      const releaseStart = Number(ui.adminFranchiseReleaseOrder.value || 0);
      const narrativeValue = ui.adminFranchiseNarrativeOrder.value;
      const narrativeStart = narrativeValue === "" ? null : Number(narrativeValue);
      const payload = selected.map((game, index) => ({
        gameKey: gameKey(game),
        relationType: ui.adminFranchiseGameType.value,
        releaseOrder: releaseStart + index,
        narrativeOrder: narrativeStart === null ? null : narrativeStart + index,
        note: ui.adminFranchiseGameNote.value,
      }));
      state.admin.selectedFranchise = await window.VaultFranchises.saveAdminFranchiseGames(franchise.id, payload);
      showToast(`${payload.length} ${payload.length === 1 ? "gioco collegato" : "giochi collegati"} al franchise.`);
    } else {
      state.admin.selectedFranchise = await window.VaultFranchises.saveAdminFranchiseGame(franchise.id, {
        gameKey: editingKey,
        relationType: ui.adminFranchiseGameType.value,
        releaseOrder: ui.adminFranchiseReleaseOrder.value,
        narrativeOrder: ui.adminFranchiseNarrativeOrder.value,
        note: ui.adminFranchiseGameNote.value,
      });
      showToast("Gioco aggiornato nel franchise.");
    }

    clearAdminFranchiseSelection({ clearSearch: true });
    renderAdminFranchiseGames();
    await loadAdminEditorial({ preserveSelection: false });
  } catch (error) {
    showToast(error.message || "Collegamento fallito.");
  }
});

ui.adminCollectionForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  setAdminEditorialMessage(ui.adminCollectionMessage, "");
  try {
    const data = await window.VaultFranchises.saveAdminCollection({
      id: ui.adminCollectionId.value || null,
      title: ui.adminCollectionTitle.value,
      slug: ui.adminCollectionSlug.value,
      description: ui.adminCollectionDescription.value,
      coverImageUrl: ui.adminCollectionImage.value,
      curatorNote: ui.adminCollectionCuratorNote.value,
      status: ui.adminCollectionStatus.value,
    });
    state.admin.selectedCollection = data;
    ui.adminCollectionSlug.dataset.edited = "";
    await loadAdminEditorial({ preserveSelection: false });
    await openAdminCollection(data.collection.id);
    setAdminEditorialMessage(ui.adminCollectionMessage, "Collezione salvata.", true);
  } catch (error) {
    setAdminEditorialMessage(ui.adminCollectionMessage, error.message || "Salvataggio fallito.");
  }
});

ui.adminCollectionDelete?.addEventListener("click", async () => {
  const collection = state.admin.selectedCollection?.collection;
  if (!collection || !confirm(`Eliminare definitivamente la collezione ${collection.title}?`)) return;
  try {
    await window.VaultFranchises.deleteAdminCollection(collection.id);
    resetAdminCollectionForm();
    await loadAdminEditorial({ preserveSelection: false });
    showToast("Collezione eliminata.");
  } catch (error) {
    showToast(error.message || "Eliminazione fallita.");
  }
});

ui.adminCollectionGameSearchForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  await searchAdminEditorialGames("collection");
});

ui.adminCollectionGameForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const collection = state.admin.selectedCollection?.collection;
  if (!collection || !ui.adminCollectionGameKey.value) {
    showToast("Seleziona prima un gioco.");
    return;
  }
  try {
    state.admin.selectedCollection = await window.VaultFranchises.saveAdminCollectionGame(collection.id, {
      gameKey: ui.adminCollectionGameKey.value,
      position: ui.adminCollectionPosition.value,
      editorialNote: ui.adminCollectionGameNote.value,
    });
    ui.adminCollectionGameForm.reset();
    ui.adminCollectionGameKey.value = "";
    ui.adminCollectionGameSelected.textContent = "Nessun gioco selezionato";
    renderAdminCollectionGames();
    await loadAdminEditorial({ preserveSelection: false });
    showToast("Gioco aggiunto alla collezione.");
  } catch (error) {
    showToast(error.message || "Collegamento fallito.");
  }
});

ui.adminMatchRefresh?.addEventListener("click", loadAdminMatches);
ui.adminMatchStatus?.addEventListener("change", loadAdminMatches);
ui.adminReportRefresh?.addEventListener("click", loadAdminReports);
ui.adminReportStatus?.addEventListener("change", loadAdminReports);
ui.adminSystemRefresh?.addEventListener("click", loadAdminSystemStatus);

ui.sidebar?.addEventListener("click", (event) => {
  const link = event.target.closest('a[href^="#/"]');
  if (!link || !MOBILE_NAV_QUERY.matches) return;
  event.preventDefault();
  closeMobileMenu({ restoreFocus: false, clearHistory: true });
  navigate(link.getAttribute("href"));
});

MOBILE_NAV_QUERY.addEventListener?.("change", (event) => {
  if (!event.matches) {
    closeMobileMenu({ restoreFocus: false, clearHistory: true });
    closeMobileFilters({ restoreFocus: false, clearHistory: true });
    ui.sidebar?.setAttribute("aria-hidden", "false");
  } else if (!document.body.classList.contains("menu-open")) {
    ui.sidebar?.setAttribute("aria-hidden", "true");
  }
});

let globalSearchTimer = null;
let catalogSearchTimer = null;
ui.search.addEventListener("input", () => {
  state.globalSearch = ui.search.value.trim();
  clearTimeout(globalSearchTimer);
  globalSearchTimer = setTimeout(() => { void renderGlobalSearchResults(); }, 240);

  if (state.route.name === "catalog") {
    clearTimeout(catalogSearchTimer);
    catalogSearchTimer = setTimeout(() => {
      const query = state.globalSearch;
      const nextHash = query ? `#/catalog?q=${encodeURIComponent(query)}` : "#/catalog";
      window.history.replaceState({}, "", nextHash);
      state.search = query;
      void loadCatalogPage({ reset: true });
    }, 380);
  }
});

ui.search.addEventListener("focus", () => { void renderGlobalSearchResults(); });
ui.search.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    const query = ui.search.value.trim();
    hideGlobalSearchResults();
    navigate(query ? `#/catalog?q=${encodeURIComponent(query)}` : "#/catalog");
  } else if (event.key === "Escape") {
    hideGlobalSearchResults();
    ui.search.blur();
  }
});

document.addEventListener("click", (event) => {
  if (!event.target.closest(".search-box")) hideGlobalSearchResults();
});

function applyDashboardFilter(update) {
  update();
  updateMobileFilterSummary();
  if (state.route.name === "catalog") void loadCatalogPage({ reset: true });
  else renderDashboard();
}

ui.filter.addEventListener("change", () => applyDashboardFilter(() => { state.statusFilter = ui.filter.value; }));
ui.storeFilter.addEventListener("change", () => applyDashboardFilter(() => { state.storeFilter = ui.storeFilter.value; }));
ui.categoryFilter.addEventListener("change", () => applyDashboardFilter(() => { state.categoryFilter = ui.categoryFilter.value; }));
ui.segmentFilter.addEventListener("change", () => applyDashboardFilter(() => { state.segmentFilter = ui.segmentFilter.value; }));
ui.priceFilter.addEventListener("change", () => applyDashboardFilter(() => { state.priceFilter = ui.priceFilter.value; }));
ui.yearFilter.addEventListener("change", () => applyDashboardFilter(() => { state.yearFilter = ui.yearFilter.value; }));
ui.sort.addEventListener("change", () => applyDashboardFilter(() => { state.sort = ui.sort.value; }));
ui.catalogLoadMore.addEventListener("click", () => { void loadCatalogPage({ reset: false }); });
ui.entityLoadMore?.addEventListener("click", () => { void loadEntityPage({ reset: false }); });
ui.refresh.addEventListener("click", () => {
  window.VaultCatalog?.clearCache();
  state.discoveryData = null;
  state.discoveryRecommendations = null;
  if (state.route.name === "discover") {
    void renderDiscoveryPage({ force: true });
    return;
  }
  if (state.route.name === "entity") {
    void loadEntityPage({ reset: true, force: true });
    return;
  }
  void loadData();
});
ui.createListButton.addEventListener("click", () => openListEditor());
$("#list-dialog-close").addEventListener("click", () => ui.listDialog.close());
ui.saveList.addEventListener("click", saveListEditor);
$("#list-picker-close").addEventListener("click", () => ui.listPicker.close());
$("#picker-create-list").addEventListener("click", () => {
  ui.listPicker.close();
  openListEditor();
});
ui.exportLibrary.addEventListener("click", exportData);
ui.importLibrary.addEventListener("click", () => ui.importLibraryFile.click());
ui.importLibraryFile.addEventListener("change", () => importData(ui.importLibraryFile.files[0]));
ui.accountButton.addEventListener("click", () => navigate(state.auth.user ? "#/profile" : "#/login"));
ui.notificationButton.addEventListener("click", () => navigate(state.auth.user ? "#/notifications" : "#/login"));

ui.feedFollowingTab.addEventListener("click", () => {
  state.social.feedFollowingOnly = true;
  void renderFeedPage();
});
ui.feedPublicTab.addEventListener("click", () => {
  state.social.feedFollowingOnly = false;
  void renderFeedPage();
});
ui.feedShowPublic.addEventListener("click", () => {
  state.social.feedFollowingOnly = false;
  void renderFeedPage();
});

let exploreSearchTimer = null;
ui.exploreUsersSearch.addEventListener("input", () => {
  clearTimeout(exploreSearchTimer);
  exploreSearchTimer = setTimeout(() => {
    if (state.route.name === "explore") void renderExplorePage();
  }, 260);
});

ui.notificationsMarkAll.addEventListener("click", async () => {
  ui.notificationsMarkAll.disabled = true;
  try {
    await window.VaultSocial.markAllNotificationsRead();
    await renderNotificationsPage();
    showToast("Notifiche segnate come lette.");
  } catch (error) {
    showToast(error.message || "Impossibile aggiornare le notifiche.");
  } finally {
    ui.notificationsMarkAll.disabled = false;
  }
});

ui.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.loginError.hidden = true;
  ui.loginSubmit.disabled = true;
  try {
    await window.VaultAuth.signIn({
      email: ui.loginEmail.value.trim(),
      password: ui.loginPassword.value,
    });
    ui.loginForm.reset();
    navigate("#/profile");
  } catch (error) {
    ui.loginError.textContent = error.message || "Accesso fallito.";
    ui.loginError.hidden = false;
  } finally {
    ui.loginSubmit.disabled = false;
  }
});

ui.forgotPasswordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.forgotPasswordError.hidden = true;
  ui.forgotPasswordSuccess.hidden = true;
  ui.forgotPasswordSubmit.disabled = true;
  try {
    await window.VaultAuth.requestPasswordReset(ui.forgotPasswordEmail.value.trim());
    ui.forgotPasswordSuccess.textContent = "Email inviata. Controlla anche la cartella spam.";
    ui.forgotPasswordSuccess.hidden = false;
  } catch (error) {
    ui.forgotPasswordError.textContent = error.message || "Invio fallito.";
    ui.forgotPasswordError.hidden = false;
  } finally {
    ui.forgotPasswordSubmit.disabled = false;
  }
});

ui.resetPasswordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.resetPasswordError.hidden = true;
  try {
    if (ui.resetPasswordValue.value !== ui.resetPasswordConfirm.value) {
      throw new Error("Le password non coincidono.");
    }
    await window.VaultAuth.updatePassword(ui.resetPasswordValue.value);
    ui.resetPasswordForm.reset();
    showToast("Password aggiornata.");
    navigate("#/profile");
  } catch (error) {
    ui.resetPasswordError.textContent = error.message || "Aggiornamento fallito.";
    ui.resetPasswordError.hidden = false;
  }
});

ui.registerForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.registerError.hidden = true;
  ui.registerSubmit.disabled = true;
  try {
    const username = ui.registerUsername.value.trim();
    if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) {
      throw new Error("Username: 3–30 caratteri, solo lettere, numeri e underscore.");
    }
    if (ui.registerPassword.value !== ui.registerPasswordConfirm.value) {
      throw new Error("Le password non coincidono.");
    }
    const result = await window.VaultAuth.signUp({
      email: ui.registerEmail.value.trim(),
      password: ui.registerPassword.value,
      username,
    });
    ui.registerForm.reset();
    if (result.session) navigate("#/profile");
    else navigate("#/login?registered=1");
  } catch (error) {
    ui.registerError.textContent = error.message || "Registrazione fallita.";
    ui.registerError.hidden = false;
  } finally {
    ui.registerSubmit.disabled = false;
  }
});


ui.publicReviewForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.publicReviewError.hidden = true;
  const game = resolveGameByKey(state.route.params.key);
  if (!game) return;
  ui.publicReviewSubmit.disabled = true;
  try {
    await window.VaultSocial.saveReview({
      game,
      rating: ui.publicReviewRating.value,
      title: ui.publicReviewTitle.value,
      body: ui.publicReviewBody.value,
      containsSpoilers: ui.publicReviewSpoilers.checked,
    });
    window.VaultCatalog?.clearRecommendationCache?.();
    state.discoveryRecommendations = null;
    showToast("Recensione pubblicata.");
    await renderGameSocial(game);
  } catch (error) {
    ui.publicReviewError.textContent = error.message || "Pubblicazione fallita.";
    ui.publicReviewError.hidden = false;
  } finally {
    ui.publicReviewSubmit.disabled = false;
  }
});

ui.publicReviewDelete.addEventListener("click", async () => {
  const game = resolveGameByKey(state.route.params.key);
  if (!game || !confirm("Eliminare la tua recensione pubblica?")) return;
  try {
    await window.VaultSocial.deleteReview(reviewKeysForGame(game));
    window.VaultCatalog?.clearRecommendationCache?.();
    state.discoveryRecommendations = null;
    showToast("Recensione eliminata.");
    await renderGameSocial(game);
  } catch (error) {
    showToast(error.message || "Eliminazione fallita.");
  }
});

ui.publicProfileShare.addEventListener("click", () => copyCurrentUrl("Link del profilo copiato."));
ui.sharedListShare.addEventListener("click", () => copyCurrentUrl("Link della lista copiato."));

ui.profileForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.profileError.hidden = true;
  try {
    await window.VaultAuth.updateProfile({
      username: ui.profileUsername.value,
      display_name: ui.profileDisplayName.value,
      bio: ui.profileBio.value,
    });
    showToast("Profilo aggiornato.");
    renderProfilePage();
  } catch (error) {
    ui.profileError.textContent = error.message || "Aggiornamento fallito.";
    ui.profileError.hidden = false;
  }
});

ui.avatarUploadButton.addEventListener("click", () => ui.avatarFile.click());
ui.avatarFile.addEventListener("change", async () => {
  const file = ui.avatarFile.files?.[0];
  if (!file) return;
  ui.avatarUploadButton.disabled = true;
  try {
    await window.VaultAuth.uploadAvatar(file);
    showToast("Avatar aggiornato.");
    renderSettingsPage();
  } catch (error) {
    showToast(error.message || "Caricamento avatar fallito.");
  } finally {
    ui.avatarFile.value = "";
    ui.avatarUploadButton.disabled = false;
  }
});
ui.avatarRemoveButton.addEventListener("click", async () => {
  try {
    await window.VaultAuth.removeAvatar();
    showToast("Avatar rimosso.");
    renderSettingsPage();
  } catch (error) {
    showToast(error.message || "Rimozione fallita.");
  }
});

ui.changeEmailForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.changeEmailMessage.hidden = true;
  try {
    await window.VaultAuth.updateEmail(ui.changeEmailValue.value);
    ui.changeEmailMessage.textContent = "Richiesta inviata. Controlla le email di conferma.";
    ui.changeEmailMessage.classList.add("auth-success");
    ui.changeEmailMessage.hidden = false;
  } catch (error) {
    ui.changeEmailMessage.classList.remove("auth-success");
    ui.changeEmailMessage.textContent = error.message || "Modifica email fallita.";
    ui.changeEmailMessage.hidden = false;
  }
});

ui.changePasswordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.changePasswordMessage.hidden = true;
  try {
    if (ui.changePasswordValue.value !== ui.changePasswordConfirm.value) {
      throw new Error("Le password non coincidono.");
    }
    await window.VaultAuth.updatePassword(ui.changePasswordValue.value);
    ui.changePasswordForm.reset();
    ui.changePasswordMessage.textContent = "Password aggiornata.";
    ui.changePasswordMessage.classList.add("auth-success");
    ui.changePasswordMessage.hidden = false;
  } catch (error) {
    ui.changePasswordMessage.classList.remove("auth-success");
    ui.changePasswordMessage.textContent = error.message || "Modifica password fallita.";
    ui.changePasswordMessage.hidden = false;
  }
});

ui.privacyForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.privacyMessage.hidden = true;
  try {
    await window.VaultAuth.updatePrivacy({
      is_public: ui.privacyPublic.checked,
      show_library: ui.privacyLibrary.checked,
      show_lists: ui.privacyLists.checked,
      show_activity: ui.privacyActivity.checked,
      show_diary: ui.privacyDiary.checked,
      email_notifications: ui.privacyEmails.checked,
    });
    ui.privacyMessage.textContent = "Preferenze salvate.";
    ui.privacyMessage.classList.add("auth-success");
    ui.privacyMessage.hidden = false;
    renderSettingsPage();
  } catch (error) {
    ui.privacyMessage.classList.remove("auth-success");
    ui.privacyMessage.textContent = error.message || "Salvataggio fallito.";
    ui.privacyMessage.hidden = false;
  }
});

ui.steamConnectButton?.addEventListener("click", async () => {
  ui.steamSyncMessage.hidden = true;
  ui.steamConnectButton.disabled = true;
  try {
    await window.VaultSteam.beginLink();
  } catch (error) {
    ui.steamSyncMessage.textContent = error.message || "Collegamento Steam non riuscito.";
    ui.steamSyncMessage.hidden = false;
    ui.steamConnectButton.disabled = false;
  }
});

ui.steamSyncButton?.addEventListener("click", async () => {
  ui.steamSyncMessage.hidden = true;
  ui.steamSyncButton.disabled = true;
  ui.steamSyncButton.textContent = "Sincronizzazione…";
  try {
    const result = await window.VaultSteam.syncLibrary();
    ui.steamSyncMessage.textContent = `${result.game_count || result.games?.length || 0} giochi ricevuti da Steam.`;
    ui.steamSyncMessage.classList.add("auth-success");
    ui.steamSyncMessage.hidden = false;
    await renderSteamConnectionPanel();
  } catch (error) {
    ui.steamSyncMessage.classList.remove("auth-success");
    ui.steamSyncMessage.textContent = error.message || "Importazione Steam fallita. Verifica la privacy della libreria.";
    ui.steamSyncMessage.hidden = false;
  } finally {
    ui.steamSyncButton.disabled = false;
    ui.steamSyncButton.textContent = "Importa libreria";
  }
});

ui.steamDisconnectButton?.addEventListener("click", async () => {
  if (!confirm("Scollegare l’account Steam? I giochi già importati resteranno nella libreria personale.")) return;
  ui.steamDisconnectButton.disabled = true;
  try {
    await window.VaultSteam.disconnect();
    showToast("Account Steam scollegato.");
    await renderSteamConnectionPanel();
  } catch (error) {
    showToast(error.message || "Scollegamento Steam fallito.");
  } finally {
    ui.steamDisconnectButton.disabled = false;
  }
});

window.addEventListener("tfv:steam-library-import", (event) => {
  const result = importSteamLibrary(event.detail?.games || []);
  showToast(`Importati ${result.imported} giochi Steam${result.unmatched ? `, ${result.unmatched} senza match catalogo` : ""}.`);
  if (state.route.name === "library") renderDashboard();
  if (state.route.name === "profile") renderProfilePage();
  if (state.route.name === "franchise") {
    renderFranchiseProgress(state.franchiseData?.games || []);
    renderFranchiseSections();
  }
});

ui.diarySearch?.addEventListener("input", renderDiaryPage);
ui.diaryPlatformFilter?.addEventListener("change", renderDiaryPage);
ui.diaryMonthFilter?.addEventListener("change", renderDiaryPage);
ui.diaryClearFilters?.addEventListener("click", () => {
  ui.diarySearch.value = "";
  ui.diaryPlatformFilter.value = "all";
  ui.diaryMonthFilter.value = "";
  renderDiaryPage();
});

window.addEventListener("tfv:journal-changed", () => {
  window.VaultCatalog?.clearRecommendationCache?.();
  state.discoveryRecommendations = null;
  if (state.route.name === "diary") renderDiaryPage();
  if (state.route.name === "stats") void renderStatsPage();
  if (state.route.name === "profile") renderProfilePage();
  if (state.route.name === "franchise") {
    renderFranchiseProgress(state.franchiseData?.games || []);
    renderFranchiseSections();
  }
});
window.addEventListener("tfv:journal-sync-error", () => {
  showToast("Diario salvato localmente; sincronizzazione cloud non disponibile.");
});

ui.settingsExportData.addEventListener("click", exportData);
ui.settingsImportData.addEventListener("click", () => ui.importLibraryFile.click());
ui.deleteAccountButton.addEventListener("click", async () => {
  ui.deleteAccountMessage.hidden = true;
  if (ui.deleteAccountConfirmation.value.trim() !== "ELIMINA") {
    ui.deleteAccountMessage.textContent = "Scrivi ELIMINA per confermare.";
    ui.deleteAccountMessage.hidden = false;
    return;
  }
  if (!window.confirm("Eliminare definitivamente il tuo account The Free Vault?")) return;
  ui.deleteAccountButton.disabled = true;
  try {
    const deletedUserId = state.auth.user?.id || activeStorageUserId;
    window.VaultCloud?.cancelScheduledPush();
    await window.VaultAuth.deleteAccount();

    if (deletedUserId) {
      clearPersonalStorage(deletedUserId);
      window.VaultJournal?.clearScope(deletedUserId);
    }
    await window.VaultJournal?.setUser(null);
    personalStorageGeneration += 1;
    synchronizedAccountId = null;
    switchPersonalStorage(null);
    showToast("Account eliminato.");
    navigate("#/home");
  } catch (error) {
    ui.deleteAccountMessage.textContent = error.message || "Eliminazione fallita. Verifica che la Edge Function sia stata pubblicata.";
    ui.deleteAccountMessage.hidden = false;
  } finally {
    ui.deleteAccountButton.disabled = false;
  }
});

$("#logout-button").addEventListener("click", async () => {
  try {
    window.VaultCloud?.cancelScheduledPush();
    await window.VaultAuth.signOut();

    await window.VaultJournal?.setUser(null);
    personalStorageGeneration += 1;
    synchronizedAccountId = null;
    switchPersonalStorage(null);
    showToast("Disconnessione completata.");
    navigate("#/home");
  } catch (error) {
    showToast(error.message || "Disconnessione fallita.");
  }
});

$$('[data-back]').forEach((button) => button.addEventListener("click", () => {
  if (window.history.length > 1) window.history.back();
  else navigate("#/home");
}));

window.addEventListener("popstate", () => {
  closeMobileMenu({ restoreFocus: false });
  closeMobileFilters({ restoreFocus: false });
});
window.addEventListener("hashchange", handleRoute);
window.addEventListener("tfv:auth-return", handleRoute);
window.addEventListener("tfv:password-recovery", () => navigate("#/reset-password"));
window.addEventListener("tfv:sync-error", () => {
  if (ui.cloudStatus) ui.cloudStatus.textContent = "Errore di sincronizzazione";
});
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  installPrompt = event;
  ui.install.hidden = false;
});
ui.install.addEventListener("click", async () => {
  if (!installPrompt) return;
  await installPrompt.prompt();
  installPrompt = null;
  ui.install.hidden = true;
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    if (document.body.classList.contains("filters-open")) {
      event.preventDefault();
      requestCloseMobileFilters();
      return;
    }
    if (document.body.classList.contains("menu-open")) {
      event.preventDefault();
      requestCloseMobileMenu();
      return;
    }
  }
  trapMobileOverlayFocus(event);
  if (event.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) {
    event.preventDefault();
    ui.search.focus();
  }
});

if (MOBILE_NAV_QUERY.matches) ui.sidebar?.setAttribute("aria-hidden", "true");
if (!window.location.hash) window.history.replaceState({}, "", "#/home");
if ("serviceWorker" in navigator) navigator.serviceWorker.register("./service-worker.js").catch(console.error);

window.VaultJournal?.setUser(null);
handleRoute();
loadData();
initializeUserSystem();
countdownTimer = setInterval(updateCountdowns, 60000);
window.setInterval(() => {
  if (state.auth.user) void refreshNotificationCount();
}, 60000);
