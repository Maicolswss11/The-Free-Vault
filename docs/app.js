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
const CATALOG_VIEW_KEY = "tfv:catalog:view:v1";

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
  catalogView: localStorage.getItem(CATALOG_VIEW_KEY) === "list" ? "list" : "grid",
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
  homeEditorialLoading: false,
  homeDiscoveryLoading: false,
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
    franchiseEditorRows: [],
    franchiseEditorSelected: new Set(),
    franchiseEditorDirty: new Set(),
    franchiseEditorDragKey: null,
    requestId: 0,
  },
  dataLoaded: false,
};

const HOME_HERO_ROTATION_MS = 9000;
const HOME_CATALOG_ROTATION_MS = 11000;
let homeHeroSlides = [];
let homeHeroIndex = 0;
let homeHeroTimer = null;
let homeCatalogSlides = [];
let homeCatalogIndex = 0;
let homeCatalogTimer = null;
let editorialFeaturedSlides = [];
let editorialFeaturedIndex = 0;
let editorialFeaturedTimer = null;
const EDITORIAL_FEATURED_ROTATION_MS = 10000;

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
  homeStage: $("#home-stage"),
  homeWelcomeName: $("#home-welcome-name"),
  homePersonalGrid: $("#home-personal-grid"),
  homeResumeList: $("#home-resume-list"),
  homeActivityList: $("#home-activity-list"),
  homeDiaryPreview: $("#home-diary-preview"),
  homeEditorialFeature: $("#home-editorial-feature"),
  homeEditorialFeatureKicker: $("#home-editorial-feature-kicker"),
  homeEditorialFeatureTitle: $("#home-editorial-feature-title"),
  homeEditorialFeatureCopy: $("#home-editorial-feature-copy"),
  homeEditorialFeatureLink: $("#home-editorial-feature-link"),
  homeEditorialCarouselControls: $("#home-editorial-carousel-controls"),
  homeEditorialPrevious: $("#home-editorial-previous"),
  homeEditorialNext: $("#home-editorial-next"),
  homeEditorialDots: $("#home-editorial-dots"),
  homeEditorialList: $("#home-editorial-list"),
  libraryShowcase: $("#library-showcase"),
  libraryLanes: $("#library-lanes"),
  librarySummaryVisual: $("#library-summary-visual"),
  librarySummaryTotal: $("#library-summary-total"),
  librarySummaryPlaying: $("#library-summary-playing"),
  librarySummaryCompleted: $("#library-summary-completed"),
  librarySummaryHours: $("#library-summary-hours"),
  librarySummaryFavorites: $("#library-summary-favorites"),
  dashboardPage: $("#dashboard-page"),
  gamePage: $("#game-page"),
  gamePageBackdrop: $("#game-page-backdrop"),
  gameMediaNav: $("#game-media-nav"),
  gameMediaPanel: $("#game-media-panel"),
  gameMediaCount: $("#game-media-count"),
  gameMediaGallery: $("#game-media-gallery"),
  gameMediaDialog: $("#game-media-dialog"),
  gameMediaDialogClose: $("#game-media-dialog-close"),
  gameMediaDialogContent: $("#game-media-dialog-content"),
  gameMediaDialogCaption: $("#game-media-dialog-caption"),
  gameSummaryProgress: $("#game-summary-progress"),
  gameSummaryProgressRing: $("#game-summary-progress-ring"),
  gameSummaryProgressStatus: $("#game-summary-progress-status"),
  gameSummaryLastPlayed: $("#game-summary-last-played"),
  gameSummarySessionCount: $("#game-summary-session-count"),
  gameSummaryHours: $("#game-summary-hours"),
  gameSummaryLatestNote: $("#game-summary-latest-note"),
  gameSummaryStatus: $("#game-summary-status"),
  gameSummaryAdded: $("#game-summary-added"),
  gameSummaryPlatform: $("#game-summary-platform"),
  gameSummaryListCount: $("#game-summary-list-count"),
  gameSummaryRating: $("#game-summary-rating"),
  gameSummaryRatingStars: $("#game-summary-rating-stars"),
  gameSummaryRatingCopy: $("#game-summary-rating-copy"),
  authPage: $("#auth-page"),
  profilePage: $("#profile-page"),
  profileHeroBackdrop: $("#profile-hero-backdrop"),
  profileFavoriteGenres: $("#profile-favorite-genres"),
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
  franchiseOverview: $("#franchise-overview"),
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
  adminOverrideSubmit: $("#admin-override-submit"),
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
  adminFranchiseEnrich: $("#admin-franchise-enrich"),
  adminFranchiseExportJson: $("#admin-franchise-export-json"),
  adminFranchiseCopyPrompt: $("#admin-franchise-copy-prompt"),
  adminFranchiseJsonImport: $("#admin-franchise-json-import"),
  adminFranchiseJsonMessage: $("#admin-franchise-json-message"),
  adminFranchiseValidateJson: $("#admin-franchise-validate-json"),
  adminFranchiseApplyJson: $("#admin-franchise-apply-json"),
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
  adminFranchiseMassEditor: $("#admin-franchise-mass-editor"),
  adminFranchiseEditorStatus: $("#admin-franchise-editor-status"),
  adminFranchiseEditorSelectAll: $("#admin-franchise-editor-select-all"),
  adminFranchiseEditorSelectionCount: $("#admin-franchise-editor-selection-count"),
  adminFranchiseBulkType: $("#admin-franchise-bulk-type"),
  adminFranchiseApplyType: $("#admin-franchise-apply-type"),
  adminFranchiseNumberStart: $("#admin-franchise-number-start"),
  adminFranchiseNumberRelease: $("#admin-franchise-number-release"),
  adminFranchiseNumberNarrative: $("#admin-franchise-number-narrative"),
  adminFranchiseClearNarrative: $("#admin-franchise-clear-narrative"),
  adminFranchiseSortDate: $("#admin-franchise-sort-date"),
  adminFranchiseSaveSelected: $("#admin-franchise-save-selected"),
  adminFranchiseSaveAll: $("#admin-franchise-save-all"),
  adminFranchiseRemoveSelected: $("#admin-franchise-remove-selected"),
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
  catalogViewToggle: $("#catalog-view-toggle"),
  catalogViewGrid: $("#catalog-view-grid"),
  catalogViewList: $("#catalog-view-list"),
  refresh: $("#refresh-button"),
  status: $("#status-message"),
  title: $("#view-title"),
  eyebrow: $("#view-eyebrow"),
  hero: $("#hero"),
  heroKicker: $("#hero .hero-kicker"),
  heroImage: $("#hero-image"),
  heroTitle: $("#hero-title"),
  heroDescription: $("#hero-description"),
  heroPrice: $("#hero-price"),
  heroCountdown: $("#hero-countdown"),
  heroLink: $("#hero-link"),
  heroLibrary: $("#hero-library"),
  heroDetails: $("#hero-details"),
  heroCarouselControls: $("#hero-carousel-controls"),
  heroCarouselPrevious: $("#hero-carousel-previous"),
  heroCarouselNext: $("#hero-carousel-next"),
  heroCarouselDots: $("#hero-carousel-dots"),
  sidebarUpdate: $("#sidebar-update"),
  sidebarDataNote: $("#sidebar-data-note"),
  install: $("#install-button"),
  exportLibrary: $("#export-library"),
  importLibrary: $("#import-library"),
  importLibraryFile: $("#import-library-file"),
  toast: $("#toast"),
  statLibrary: $("#stat-library"),
  statCompleted: $("#stat-completed"),
  statFavorites: $("#stat-favorites"),
  statLists: $("#stat-lists"),
  statTodayMinutes: $("#stat-today-minutes"),
  statTodaySessions: $("#stat-today-sessions"),
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
  accountLevel: $("#account-level"),
  accountMenu: $("#account-menu"),
  accountMenuAvatar: $("#account-menu-avatar"),
  accountMenuName: $("#account-menu-name"),
  accountMenuHandle: $("#account-menu-handle"),
  accountMenuPublic: $("#account-menu-public"),
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
  authCallbackError: $("#auth-callback-error"),
  authCallbackErrorTitle: $("#auth-callback-error-title"),
  authCallbackErrorMessage: $("#auth-callback-error-message"),
  authCallbackErrorAction: $("#auth-callback-error-action"),
  forgotPasswordForm: $("#forgot-password-form"),
  forgotPasswordEmail: $("#forgot-password-email"),
  forgotPasswordError: $("#forgot-password-error"),
  forgotPasswordSuccess: $("#forgot-password-success"),
  forgotPasswordSubmit: $("#forgot-password-submit"),
  recoveryCodeForm: $("#recovery-code-form"),
  recoveryCodeEmail: $("#recovery-code-email"),
  recoveryCodeValue: $("#recovery-code-value"),
  recoveryCodeError: $("#recovery-code-error"),
  recoveryCodeSubmit: $("#recovery-code-submit"),
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
  profileVisibilityText: $("#profile-visibility-text"),
  settingsSignedOut: $("#settings-signed-out"),
  settingsSignedIn: $("#settings-signed-in"),
  settingsAvatarPreview: $("#settings-avatar-preview"),
  avatarFile: $("#avatar-file"),
  avatarUploadButton: $("#avatar-upload-button"),
  avatarRemoveButton: $("#avatar-remove-button"),
  settingsHeroPreview: $("#settings-hero-preview"),
  profileHeroGameSelect: $("#profile-hero-game-select"),
  profileHeroApplyGame: $("#profile-hero-apply-game"),
  profileHeroFile: $("#profile-hero-file"),
  profileHeroUpload: $("#profile-hero-upload"),
  profileHeroReset: $("#profile-hero-reset"),
  profileHeroUrl: $("#profile-hero-url"),
  profileHeroApplyUrl: $("#profile-hero-apply-url"),
  profileHeroMessage: $("#profile-hero-message"),
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
  gameCommunityRatingPanel: $("#game-community-rating-panel"),
  gameCommunityRatingAverage: $("#game-community-rating-average"),
  gameCommunityRatingStars: $("#game-community-rating-stars"),
  gameCommunityRatingCount: $("#game-community-rating-count"),
  gameCommunityRatingDistribution: $("#game-community-rating-distribution"),
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
  publicProfileHeroBackdrop: $("#public-profile-hero-backdrop"),
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
  if (!game || typeof game !== "object") return "";
  return game.canonical_route_key || game.match_key || game.canonical_id || game.internal_id || game.listing_id || game.epic_id || game.promotion_key ||
    `${game.store || "epic"}:${game.namespace || "unknown"}:${game.external_id || game.title}`;
}

function gameAliases(game) {
  if (!game || typeof game !== "object") return [];
  const canonicalAliases = Array.isArray(game.canonical_aliases) ? game.canonical_aliases : [];
  return [
    game.canonical_route_key,
    game.match_key,
    game.canonical_work_key,
    game.requested_key,
    game.canonical_id,
    game.internal_id,
    game.listing_id,
    game.epic_id,
    game.promotion_key,
    game.external_id,
    ...canonicalAliases,
    ...((Array.isArray(game.store_listings) ? game.store_listings : [])
      .map((listing) => listing?.listing_id || listing?.external_id)
      .filter(Boolean)),
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
    canonical_route_key: game.canonical_route_key,
    canonical_work_key: game.canonical_work_key,
    listing_id: game.listing_id || game.internal_id,
    internal_id: game.internal_id || game.listing_id,
    store: game.store || null,
    stores: game.stores || (game.store ? [game.store] : []),
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
    master_game_id: game.master_game_id || null,
  };
}

function getLibraryEntry(game) {
  for (const key of [gameKey(game), ...gameAliases(game)]) {
    if (key && state.library[key]) return state.library[key];
  }
  return null;
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
  if (["catalog", "store", "master", "hybrid"].includes(game.source_kind)) return "catalog";
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
  const explicit = Number(game?.release_year);
  if (Number.isInteger(explicit) && explicit > 1900) return explicit;
  const value = game?.release_date || game?.start_date;
  if (value) {
    const year = new Date(value).getFullYear();
    if (Number.isInteger(year) && year > 1900) return year;
  }
  const titleHint = String(game?.title || game?.canonical_title || "").match(/(?:^|[^0-9])((?:19|20)\d{2})(?:[^0-9]|$)/);
  if (titleHint) {
    const year = Number(titleHint[1]);
    if (Number.isInteger(year) && year > 1900) return year;
  }
  return null;
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

const STORE_BRANDS = Object.freeze({
  epic: { label: "Epic Games", icon: "./icons/stores/epic.png" },
  steam: { label: "Steam", icon: "./icons/stores/steam.png" },
  playstation: { label: "PlayStation", icon: "./icons/stores/playstation.png" },
  xbox: { label: "Xbox", icon: "./icons/stores/xbox.png" },
  gog: { label: "GOG", icon: "./icons/stores/gog.png" },
  nintendo: { label: "Nintendo", icon: "./icons/stores/nintendo.png" },
  igdb: { label: "IGDB", icon: null },
});

const PLATFORM_FAMILY_LABELS = Object.freeze({
  playstation: "PlayStation",
  xbox: "Xbox",
  nintendo: "Nintendo",
  windows: "Windows",
  apple: "Apple",
  linux: "Linux",
  sega: "SEGA",
  pc: "PC",
  mobile: "Mobile",
  arcade: "Arcade",
  retro: "Retro",
});

const PLATFORM_FAMILY_ICONS = Object.freeze({
  playstation: "./icons/platforms/playstation.png",
  xbox: "./icons/platforms/xbox.png",
  nintendo: "./icons/platforms/nintendo.png",
  windows: "./icons/platforms/windows.png",
  apple: "./icons/platforms/apple.png",
  linux: "./icons/platforms/linux.png",
  sega: "./icons/platforms/sega.png",
  pc: "./icons/platforms/pc.png",
  mobile: "./icons/platforms/mobile.png",
  arcade: "./icons/platforms/arcade.png",
  retro: "./icons/platforms/retro.png",
});

function storeLabel(store) {
  const key = String(store || "").toLowerCase();
  return STORE_BRANDS[key]?.label || (store ? String(store) : "Archivio");
}

function storeLogoPath(store) {
  return STORE_BRANDS[String(store || "").toLowerCase()]?.icon || null;
}

function storeLogoMarkup(store, className = "store-brand-logo") {
  const src = storeLogoPath(store);
  if (src) {
    return `<img class="${escapeAttr(className)}" src="${escapeAttr(src)}" alt="${escapeAttr(storeLabel(store))}">`;
  }
  return `<span class="${escapeAttr(className)} store-brand-fallback" aria-hidden="true">${escapeHtml(storeLabel(store).slice(0, 1))}</span>`;
}

function normalizedPlatformToken(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[™®]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-+/g, "-");
}

function platformBrand(value) {
  const raw = String(value || "").trim();
  const token = normalizedPlatformToken(raw);
  const has = (...parts) => parts.some((part) => token === part || token.includes(part));

  if (/^(ps|playstation)-?1$/.test(token) || token === "ps1") return { family: "playstation", label: "PS1" };
  if (/^(ps|playstation)-?2$/.test(token) || token.startsWith("ps2")) return { family: "playstation", label: "PS2" };
  if (/^(ps|playstation)-?3$/.test(token) || token.startsWith("ps3")) return { family: "playstation", label: "PS3" };
  if (/^(ps|playstation)-?4$/.test(token) || token.startsWith("ps4")) return { family: "playstation", label: "PS4" };
  if (/^(ps|playstation)-?5$/.test(token) || token.startsWith("ps5")) return { family: "playstation", label: "PS5" };
  if (has("ps-vita", "psvita", "playstation-vita")) return { family: "playstation", label: "PS Vita" };
  if (has("psp", "playstation-portable")) return { family: "playstation", label: "PSP" };
  if (has("playstation")) return { family: "playstation", label: raw || "PlayStation" };

  if (has("xbox-360", "xbox360", "x360")) return { family: "xbox", label: "Xbox 360" };
  if (has("xbox-one", "xone")) return { family: "xbox", label: "Xbox One" };
  if (has("xbox-series", "series-x", "series-s", "xsx", "xbsx")) return { family: "xbox", label: "Xbox Series X|S" };
  if (token === "xbox" || token.startsWith("xbox-")) return { family: "xbox", label: raw || "Xbox" };

  if (has("switch")) return { family: "nintendo", label: "Switch" };
  if (has("wii-u", "wiiu")) return { family: "nintendo", label: "Wii U" };
  if (token === "wii" || token.startsWith("wii-")) return { family: "nintendo", label: "Wii" };
  if (has("gamecube", "game-cube", "ngc")) return { family: "nintendo", label: "GameCube" };
  if (has("nintendo-64", "n64")) return { family: "nintendo", label: "Nintendo 64" };
  if (has("super-nintendo", "snes")) return { family: "nintendo", label: "SNES" };
  if (token === "nes" || has("nintendo-entertainment-system")) return { family: "nintendo", label: "NES" };
  if (has("game-boy-advance", "gameboy-advance", "gba")) return { family: "nintendo", label: "Game Boy Advance" };
  if (has("game-boy-color", "gameboy-color", "gbc")) return { family: "nintendo", label: "Game Boy Color" };
  if (has("game-boy", "gameboy")) return { family: "nintendo", label: "Game Boy" };
  if (has("3ds")) return { family: "nintendo", label: "Nintendo 3DS" };
  if (token === "ds" || has("nintendo-ds", "nds")) return { family: "nintendo", label: "Nintendo DS" };
  if (has("nintendo")) return { family: "nintendo", label: raw || "Nintendo" };

  if (has("dreamcast")) return { family: "sega", label: "Dreamcast" };
  if (has("saturn")) return { family: "sega", label: "Saturn" };
  if (has("mega-drive", "megadrive", "genesis")) return { family: "sega", label: token.includes("genesis") ? "Genesis" : "Mega Drive" };
  if (has("master-system")) return { family: "sega", label: "Master System" };
  if (has("game-gear")) return { family: "sega", label: "Game Gear" };
  if (has("sega")) return { family: "sega", label: raw || "SEGA" };

  if (has("windows", "win32", "win64") || token === "win") return { family: "windows", label: "PC" };
  if (has("macos", "mac-os", "macintosh") || token === "mac") return { family: "apple", label: "macOS" };
  if (has("ios", "iphone", "ipad")) return { family: "apple", label: "iOS" };
  if (has("linux", "steamos")) return { family: "linux", label: token.includes("steamos") ? "SteamOS" : "Linux" };
  if (has("android")) return { family: "mobile", label: "Android" };
  if (has("mobile", "java-me", "j2me", "phone")) return { family: "mobile", label: "Mobile" };
  if (has("arcade")) return { family: "arcade", label: "Arcade" };
  if (has("dos", "ms-dos")) return { family: "pc", label: "DOS" };
  if (token === "pc" || has("computer")) return { family: "pc", label: "PC" };

  return { family: "retro", label: raw || "Piattaforma" };
}

function platformBadgesMarkup(platforms, { limit = 6, compact = false } = {}) {
  const source = Array.isArray(platforms) ? platforms : [];
  const unique = [];
  const seen = new Set();
  for (const value of source) {
    const info = platformBrand(value);
    const key = `${info.family}:${info.label.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(info);
  }
  const visible = unique.slice(0, Math.max(0, limit));
  const chips = visible.map((info) => {
    const icon = PLATFORM_FAMILY_ICONS[info.family] || PLATFORM_FAMILY_ICONS.retro;
    return `<span class="platform-chip platform-${escapeAttr(info.family)}${compact ? " is-compact" : ""}" title="${escapeAttr(PLATFORM_FAMILY_LABELS[info.family] || info.label)}"><img src="${escapeAttr(icon)}" alt=""><b>${escapeHtml(info.label)}</b></span>`;
  });
  if (unique.length > visible.length) chips.push(`<span class="platform-chip platform-more${compact ? " is-compact" : ""}"><b>+${unique.length - visible.length}</b></span>`);
  return chips.join("");
}

const GAME_TYPE_LABELS = Object.freeze({
  main_game: "Gioco principale",
  dlc_addon: "DLC / add-on",
  expansion: "Espansione",
  bundle: "Raccolta / bundle",
  standalone_expansion: "Espansione autonoma",
  mod: "Mod",
  episode: "Episodio",
  season: "Stagione",
  remake: "Remake",
  remaster: "Remaster",
  expanded_game: "Edizione ampliata",
  port: "Porting",
  fork: "Versione derivata",
  pack: "Pacchetto",
  update: "Aggiornamento",
  unknown: "Gioco enciclopedico",
});

const GAME_TYPE_PRIORITY = Object.freeze({
  main_game: 0,
  remake: 1,
  remaster: 2,
  expanded_game: 3,
  standalone_expansion: 4,
  expansion: 5,
  port: 6,
  episode: 7,
  bundle: 8,
  dlc_addon: 9,
  pack: 10,
  update: 11,
  unknown: 20,
});

function gameTypeLabel(game) {
  const type = String(game?.game_type || "unknown").toLowerCase();
  return GAME_TYPE_LABELS[type] || type.replace(/_/g, " ");
}

function normalizedEditorialTitle(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[™®©]/g, "")
    .replace(/\s*[\[(](?:19|20)\d{2}[\])]\s*$/g, "")
    .replace(/\s+(?:19|20)\d{2}\s*$/g, "")
    .replace(/[^a-z0-9]+/g, "")
    .trim();
}

function normalizedCoverIdentity(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .split("?")[0]
    .replace(/^https?:\/\//, "")
    .replace(/\/t_[^/]+\//g, "/");
  if (!normalized) return "";

  const filename = normalized.split("/").pop() || "";
  const token = filename.replace(/\.(?:avif|gif|jpe?g|png|webp)$/i, "");
  if (/^[a-z0-9_-]{5,}$/i.test(token)) return token;
  return normalized;
}

const SUBORDINATE_GAME_TYPES = new Set(["port", "fork", "expanded_game"]);
const SEPARATE_GAME_TYPES = new Set([
  "remake",
  "remaster",
  "bundle",
  "dlc_addon",
  "expansion",
  "standalone_expansion",
  "episode",
  "pack",
  "update",
]);

function normalizedGameType(game) {
  return String(game?.game_type || "unknown").toLowerCase();
}

function catalogTextForVariantSignals(game) {
  return [
    game?.title,
    game?.canonical_title,
    game?.description,
    game?.category_group,
    game?.market_segment,
  ].filter(Boolean).join(" ").toLocaleLowerCase("it");
}

function hasPortOrStoreVariantSignal(game) {
  const text = catalogTextForVariantSignals(game);
  return /\b(port|ports|ported|version|versions|conversion|release for|released for|bundle containing|containing ports|contains ports|includes? .*expansion|undead nightmare|riedizion|store listing|store version)\b/.test(text);
}

function containsStandaloneOfferSignal(game) {
  const text = catalogTextForVariantSignals(game);
  return /(bundle|bundle\]|pack|collection|offer|edition|store listing|store version|free to play|include|includes|including|containing|contains)/.test(text);
}

function strongestBaseTitleContainedInOffer(game, titleKeys) {
  const ownTitle = normalizedEditorialTitle(game?.title);
  if (!ownTitle || !containsStandaloneOfferSignal(game)) return "";
  const candidates = [...titleKeys]
    .filter((title) => title && title !== ownTitle && title.length >= 8 && ownTitle.includes(title))
    .sort((a, b) => b.length - a.length);
  return candidates[0] || "";
}

function isBundleOrStoreOffer(game) {
  const type = normalizedGameType(game);
  const category = String(game?.category_group || "").toLowerCase();
  const text = catalogTextForVariantSignals(game);
  return ["bundle", "pack"].includes(type)
    || ["bundle", "edition"].includes(category)
    || /\b(bundle|bundle\]|collection|pack)\b/.test(text);
}

function isSubordinateVariant(game) {
  return SUBORDINATE_GAME_TYPES.has(normalizedGameType(game)) || hasPortOrStoreVariantSignal(game);
}

function isPrimaryWorkCandidate(game) {
  const type = normalizedGameType(game);
  return !SUBORDINATE_GAME_TYPES.has(type) && !SEPARATE_GAME_TYPES.has(type);
}

function normalizedMasterIdentity(value) {
  return String(value || "")
    .trim()
    .replace(/^master:/, "");
}

function masterIdentityForGame(game) {
  if (!game || typeof game !== "object") return "";
  const direct = game.master_game_id || game.game_id;
  if (direct) return normalizedMasterIdentity(direct);
  const key = String(gameKey(game) || "");
  return key.startsWith("master:") ? normalizedMasterIdentity(key) : "";
}

function variantParentIdentity(game) {
  const direct = game?.variant_parent_id
    || game?.metadata?.parent_game
    || game?.metadata?.version_parent;
  if (!direct) return "";
  const normalized = normalizedMasterIdentity(direct);
  return normalized.startsWith("igdb:") ? normalized : `igdb:${normalized}`;
}

function editorialIdentityForGame(game) {
  if (game?.editorial_work_key) return String(game.editorial_work_key);
  if (game?.editorial_identity) return String(game.editorial_identity);
  const parent = variantParentIdentity(game);
  if (parent) return `work:${parent}`;
  const title = normalizedEditorialTitle(game?.title);
  const cover = normalizedCoverIdentity(game?.image_url);
  return title && cover ? `${title}|${cover}` : `game:${gameKey(game)}`;
}

function gameVariantPriority(game) {
  const type = normalizedGameType(game);
  const completeness = [
    game?.release_date || game?.release_year,
    game?.developer,
    Array.isArray(game?.platforms) && game.platforms.length,
    game?.description,
  ].filter(Boolean).length;
  return [
    GAME_TYPE_PRIORITY[type] ?? 20,
    -completeness,
    franchiseReleaseSortValue(game),
    String(gameKey(game) || ""),
  ];
}

function compareVariantRepresentatives(a, b) {
  const left = gameVariantPriority(a);
  const right = gameVariantPriority(b);
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] < right[index]) return -1;
    if (left[index] > right[index]) return 1;
  }
  return 0;
}

function uniqueMergedValues(games, field) {
  const values = [];
  const seen = new Set();
  for (const game of games || []) {
    const source = Array.isArray(game?.[field]) ? game[field] : [];
    for (const value of source) {
      const key = String(value || "").toLowerCase();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      values.push(value);
    }
  }
  return values;
}

function flattenedUniqueVariants(games) {
  const output = [];
  const seen = new Set();
  for (const game of games || []) {
    if (!game || typeof game !== "object") continue;
    const variants = Array.isArray(game.variants) && game.variants.length ? game.variants : [game];
    for (const variant of variants) {
      if (!variant || typeof variant !== "object") continue;
      const key = gameKey(variant) || `${variant.title || ""}:${variant.image_url || ""}`;
      if (!key || seen.has(key)) continue;
      seen.add(key);
      output.push(variant);
    }
  }
  return output;
}

function candidateGroupTitleKey(game) {
  return normalizedEditorialTitle(game?.canonical_title || game?.title);
}

function candidateGroupYears(group) {
  const variants = flattenedUniqueVariants([group]);
  const years = variants
    .map((variant) => releaseYearOf(variant))
    .filter((year) => Number.isInteger(year) && year > 1900);
  const representativeYear = releaseYearOf(group);
  if (Number.isInteger(representativeYear) && representativeYear > 1900) years.push(representativeYear);
  return [...new Set(years)].sort((a, b) => a - b);
}

function candidateGroupHasSeparateEditorialMarker(group) {
  const variants = flattenedUniqueVariants([group]);
  return variants.some((variant) => {
    if (hasPortOrStoreVariantSignal(variant)) return false;
    if (SEPARATE_GAME_TYPES.has(normalizedGameType(variant))) return true;
    const title = String(variant?.title || variant?.canonical_title || "").toLowerCase();
    return /\b(remake|remaster|collection|demo|trial|deluxe|gold|complete|ultimate|director'?s\s+cut|cloud|dlc|expansion)\b/.test(title);
  });
}

function candidateGroupsYearCompatible(left, right) {
  const leftYears = candidateGroupYears(left);
  const rightYears = candidateGroupYears(right);
  if (leftYears.length && rightYears.length) {
    return leftYears.some((leftYear) => rightYears.some((rightYear) => Math.abs(leftYear - rightYear) <= 2));
  }
  return !candidateGroupHasSeparateEditorialMarker(left) && !candidateGroupHasSeparateEditorialMarker(right);
}

function mergeAdminFranchiseCanonicalGroups(groups) {
  const merged = [];
  for (const group of groups || []) {
    const titleKey = candidateGroupTitleKey(group);
    let target = null;

    if (titleKey) {
      target = merged.find((candidate) =>
        candidateGroupTitleKey(candidate) === titleKey
        && candidateGroupsYearCompatible(candidate, group)
      );
    }

    if (!target) {
      merged.push({ ...group });
      continue;
    }

    const variants = flattenedUniqueVariants([target, group]).sort(compareVariantRepresentatives);
    const representative = variants[0] || target;
    Object.assign(target, {
      ...representative,
      editorial_identity: target.editorial_identity || group.editorial_identity || `canonical:${titleKey}:${candidateGroupYears(representative)[0] || "unknown"}`,
      editorial_work_key: target.editorial_work_key || group.editorial_work_key || target.editorial_identity,
      variants,
      variant_keys: [...new Set([
        ...(Array.isArray(target.variant_keys) ? target.variant_keys : []),
        ...(Array.isArray(group.variant_keys) ? group.variant_keys : []),
        ...variants.map((item) => gameKey(item)),
      ].filter(Boolean))],
      variant_count: Math.max(
        Number(target.variant_count || 0),
        Number(group.variant_count || 0),
        variants.length
      ),
      platforms: uniqueMergedValues(variants, "platforms"),
      stores: uniqueMergedValues(variants, "stores"),
    });
  }
  return merged;
}

function groupGameVariants(games, { limit = Infinity } = {}) {
  const flatGames = flattenedUniqueVariants(games);
  const titleBuckets = new Map();
  const referencedParents = new Set();

  for (const game of flatGames) {
    const title = normalizedEditorialTitle(game?.title);
    if (!titleBuckets.has(title)) titleBuckets.set(title, []);
    titleBuckets.get(title).push(game);
    const parent = variantParentIdentity(game);
    if (parent) referencedParents.add(parent);
  }

  const titleAnchors = new Map();
  for (const [title, bucket] of titleBuckets.entries()) {
    const primaries = bucket.filter(isPrimaryWorkCandidate).sort(compareVariantRepresentatives);
    const primaryCoverGroups = new Map();
    for (const primary of primaries) {
      const cover = normalizedCoverIdentity(primary?.image_url) || `key:${gameKey(primary)}`;
      if (!primaryCoverGroups.has(cover)) primaryCoverGroups.set(cover, []);
      primaryCoverGroups.get(cover).push(primary);
    }
    const hasSubordinateRows = bucket.some((item) => isSubordinateVariant(item) || isBundleOrStoreOffer(item));
    if (primaries.length && (primaryCoverGroups.size === 1 || hasSubordinateRows)) {
      titleAnchors.set(title, primaries[0]);
    }
  }
  const knownTitleKeys = new Set(titleBuckets.keys());

  const grouped = new Map();
  flatGames.forEach((game, index) => {
    const title = normalizedEditorialTitle(game?.title);
    const offerBaseTitle = strongestBaseTitleContainedInOffer(game, knownTitleKeys);
    const groupingTitle = offerBaseTitle || title;
    const parent = variantParentIdentity(game);
    const master = masterIdentityForGame(game);
    const anchor = titleAnchors.get(groupingTitle);
    const anchorMaster = masterIdentityForGame(anchor);
    const hasSubordinates = (titleBuckets.get(groupingTitle) || []).some((item) => isSubordinateVariant(item) || isBundleOrStoreOffer(item));

    let identity = "";
    if (parent) {
      identity = `work:${parent}`;
    } else if (master && referencedParents.has(master)) {
      identity = `work:${master}`;
    } else if (anchor && anchorMaster && (hasSubordinates || offerBaseTitle) && (isSubordinateVariant(game) || isPrimaryWorkCandidate(game) || isBundleOrStoreOffer(game))) {
      identity = `work:${anchorMaster}`;
    } else if ((hasPortOrStoreVariantSignal(game) || isBundleOrStoreOffer(game) || offerBaseTitle) && groupingTitle) {
      identity = `title-variant:${groupingTitle}`;
    } else {
      identity = editorialIdentityForGame(game);
    }

    if (!grouped.has(identity)) grouped.set(identity, { firstIndex: index, variants: [] });
    grouped.get(identity).variants.push(game);
  });

  return [...grouped.entries()]
    .map(([identity, group]) => {
      const ordered = [...group.variants].sort(compareVariantRepresentatives);
      const representative = ordered[0];
      return {
        ...representative,
        editorial_identity: identity,
        editorial_work_key: identity,
        variants: ordered,
        variant_keys: ordered.map((item) => gameKey(item)).filter(Boolean),
        variant_count: ordered.length,
        platforms: uniqueMergedValues(ordered, "platforms"),
        stores: uniqueMergedValues(ordered, "stores"),
        _variant_group_index: group.firstIndex,
      };
    })
    .sort((a, b) => a._variant_group_index - b._variant_group_index)
    .slice(0, limit);
}

function normalizeAdminFranchiseCandidateGroups(games) {
  const source = (games || []).filter((game) => game && typeof game === "object");
  if (!source.length) return [];

  const alreadyCanonical = source.some((game) =>
    game.editorial_work_key
    || game.editorial_identity
    || game.canonical_route_key
    || Array.isArray(game.variants)
    || Number(game.variant_count || 0) > 1
  );

  const baseGroups = alreadyCanonical ? source : groupGameVariants(source);
  const normalizedGroups = baseGroups.map((game) => {
    const variants = flattenedUniqueVariants([game]);
    const variantKeys = [...new Set([
      ...(Array.isArray(game.variant_keys) ? game.variant_keys : []),
      ...variants.map((item) => gameKey(item)),
      gameKey(game),
    ].filter(Boolean))];
    const variantCount = Math.max(
      Number(game.variant_count || 0),
      variants.length || 0,
      variantKeys.length || 0,
      1
    );
    const identity = editorialIdentityForGame(game);

    return {
      ...game,
      editorial_identity: identity,
      editorial_work_key: identity,
      variants: variants.length ? variants : [game],
      variant_keys: variantKeys,
      variant_count: variantCount,
    };
  });

  return mergeAdminFranchiseCanonicalGroups(normalizedGroups);
}

function gameDisambiguationMarkup(game, { includeDeveloper = true } = {}) {
  const parts = [];
  const year = Number(game?.release_year || releaseYearOf(game) || 0);
  if (year > 0) parts.push(String(year));
  const platforms = (game?.platforms || []).slice(0, 3).map((value) => platformBrand(value).label);
  if (platforms.length) parts.push(platforms.join(", "));
  parts.push(gameTypeLabel(game));
  if (includeDeveloper && game?.developer) parts.push(game.developer);
  return parts.filter(Boolean).join(" · ");
}

function commercialListingsForGame(game) {
  const commercialStores = new Set(["epic", "steam", "playstation", "xbox", "gog", "nintendo"]);
  const candidates = listingsForGame(game)
    .filter((listing) => commercialStores.has(String(listing?.store || "").toLowerCase()) && listing?.store_url);

  if (!candidates.length && commercialStores.has(String(game?.store || "").toLowerCase()) && game?.store_url) {
    candidates.push({
      ...game,
      store: String(game.store).toLowerCase(),
      store_url: game.store_url,
      listing_id: game.listing_id || game.external_id || game.store_url,
    });
  }

  const seen = new Set();
  return candidates.filter((listing) => {
    const key = `${String(listing.store || "").toLowerCase()}:${listing.listing_id || listing.external_id || listing.store_url}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function configureStoreAction(link, game, { detail = false } = {}) {
  if (!link) return;
  const listings = commercialListingsForGame(game);
  const stores = [...new Set(listings.map((listing) => String(listing.store || "").toLowerCase()).filter(Boolean))];
  link.onclick = null;
  link.classList.toggle("is-multistore-action", stores.length > 1);

  if (!stores.length) {
    link.hidden = true;
    link.removeAttribute("href");
    link.removeAttribute("target");
    link.removeAttribute("rel");
    return;
  }

  link.hidden = false;
  if (stores.length === 1) {
    const listing = listings[0];
    link.href = listing.store_url;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = `Apri su ${storeLabel(listing.store)}`;
    return;
  }

  link.removeAttribute("target");
  link.removeAttribute("rel");
  link.textContent = `Confronta ${stores.length} store`;
  if (detail) {
    link.href = "#game-page-availability";
    link.onclick = (event) => {
      event.preventDefault();
      document.querySelector("#game-page-availability")?.scrollIntoView({ behavior: "smooth", block: "start" });
    };
  } else {
    link.href = gameRoute(game);
  }
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
  const store = game.store || null;
  return {
    ...game,
    listing_id: game.listing_id || game.internal_id,
    canonical_route_key: game.canonical_route_key || game.match_key || game.canonical_id,
    canonical_work_key: game.canonical_work_key || null,
    canonical_source: game.canonical_source || null,
    is_canonical: game.is_canonical === true,
    source_kind: game.source_kind || "catalog",
    store,
    stores: game.stores || (store ? [store] : []),
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
    .map(([key, entry]) => entry?.game?.canonical_route_key || entry?.game?.match_key || entry?.game?.canonical_id || (/^(?:title|game):/.test(key) ? key : null))
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

    const normalizedIncoming = response.items.map(normalizeCatalog);
    const incoming = state.route.name === "catalog" ? groupGameVariants(normalizedIncoming) : normalizedIncoming;
    if (reset) {
      state.catalog = incoming;
    } else {
      const merged = new Map(state.catalog.map((game) => [gameKey(game), game]));
      for (const game of incoming) merged.set(gameKey(game), game);
      state.catalog = [...merged.values()];
    }
    state.catalogTotal = response.total;
    state.catalogOffset = state.catalog.length;
    state.catalogHasMore = typeof response.hasMore === "boolean"
      ? response.hasMore
      : Number.isFinite(response.total) && state.catalog.length < response.total;
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
  const hasExactTotal = Number.isFinite(total);
  ui.catalogPageSummary.textContent = state.catalogLoading && shown === 0
    ? "Caricamento…"
    : shown === 0
      ? "Nessun risultato"
      : hasExactTotal
        ? `${shown.toLocaleString("it-IT")} di ${total.toLocaleString("it-IT")} giochi`
        : `${shown.toLocaleString("it-IT")} risultati caricati`;
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
  if (/^#(?:access_token|refresh_token|error|error_code|error_description)=/.test(rawHash)) {
    return {
      name: "auth-callback",
      params: {},
      query: new URLSearchParams(rawHash.slice(1)),
    };
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
  document.title = label ? `${label} · Ludograph` : "Ludograph";
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
  document.body.dataset.route = state.route.name;
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
  const canonicalRouteKey = game?.canonical_route_key || gameKey(game);
  if (canonicalRouteKey && state.route.params.key !== canonicalRouteKey) {
    state.route.params.key = canonicalRouteKey;
    window.history.replaceState(null, "", gameRoute(game));
  }

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
  if (query.length < 3) {
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
        limit: 24,
        offset: 0,
        sort: "relevance",
      });
      if (requestId !== state.globalSearchRequestId || state.globalSearch.trim() !== rawQuery) return;
      const searchItems = Array.isArray(response?.items) ? response.items : [];
      results = groupGameVariants(searchItems, { limit: 8 });
    } else {
      results = groupGameVariants(
        uniqueSearchGames().filter((game) => allSearchText(game).includes(query)),
        { limit: 8 },
      );
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
        const variantCount = Number(game.variant_count || 1);
        button.innerHTML = `
          <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
          <span>
            <strong>${escapeHtml(game.title)}</strong>
            <small>${escapeHtml(gameDisambiguationMarkup(game))}</small>
            ${variantCount > 1 ? `<small class="search-variant-note">${variantCount} versioni raggruppate</small>` : ""}
          </span>
          <em>${variantCount > 1 ? `${variantCount} versioni` : escapeHtml((game.stores || [game.store]).filter(Boolean).map(storeLabel).join(" + "))}</em>`;
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

function homeLocalDateKey(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function updateStats() {
  const entries = libraryEntryRecords();
  const journalEntries = window.VaultJournal?.listEntries() || [];
  const todayKey = homeLocalDateKey();
  const todayEntries = journalEntries.filter((entry) => homeLocalDateKey(entry.playedAt || entry.createdAt) === todayKey);
  const todayMinutes = todayEntries.reduce((sum, entry) => sum + Math.max(0, Number(entry.minutesPlayed || 0)), 0);

  ui.statLibrary.textContent = entries.length.toLocaleString("it-IT");
  ui.statCompleted.textContent = entries.filter((entry) => entry.status === "completed").length.toLocaleString("it-IT");
  ui.statFavorites.textContent = entries.filter((entry) => entry.favorite).length.toLocaleString("it-IT");
  ui.statLists.textContent = Object.keys(state.lists).length.toLocaleString("it-IT");
  ui.statTodayMinutes.textContent = formatMinutes(todayMinutes);
  ui.statTodaySessions.textContent = todayEntries.length.toLocaleString("it-IT");
  updateAccountLevelLabel();
}

function homeArtwork(game) {
  return game?.hero_image_url
    || game?.background_image_url
    || game?.wide_image_url
    || game?.image_url
    || PLACEHOLDER;
}

function uniqueHomeItems(items, keyOf) {
  const seen = new Set();
  return items.filter((item) => {
    const key = String(keyOf(item) || "").trim().toLocaleLowerCase("it");
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function buildHomeHeroSlides(entries = libraryEntryRecords()) {
  const diaryEntries = window.VaultJournal?.listEntries({ limit: 12 }) || [];
  const byKey = new Map(entries.map((entry) => [gameKey(entry.game), entry]));
  const diaryEntriesInLibrary = diaryEntries
    .map((entry) => byKey.get(entry.gameKey) || byKey.get(gameKey(journalGame(entry))))
    .filter(Boolean);
  const active = entries.filter((entry) => ["playing", "paused", "replay"].includes(entry.status));
  const favorites = entries.filter((entry) => entry.favorite);
  const personal = uniqueHomeItems(
    [...diaryEntriesInLibrary, ...active, ...favorites, ...entries],
    (entry) => gameKey(entry.game)
  ).slice(0, 4).map((entry) => ({ kind: "personal", entry, game: entry.game }));

  const promotions = state.current.slice(0, 2)
    .map(normalizePromotion)
    .filter(Boolean)
    .map((game) => ({ kind: "promotion", entry: null, game }));

  return uniqueHomeItems(
    [...personal, ...promotions],
    (slide) => gameKey(slide.game) || slide.game?.title
  ).filter((slide) => slide.game?.title).slice(0, 4);
}

function stopHomeHeroRotation() {
  if (homeHeroTimer) window.clearInterval(homeHeroTimer);
  homeHeroTimer = null;
}

function startHomeHeroRotation() {
  stopHomeHeroRotation();
  if (state.route.name !== "home" || homeHeroSlides.length < 2) return;
  homeHeroTimer = window.setInterval(() => {
    renderHomeHeroSlide((homeHeroIndex + 1) % homeHeroSlides.length, { restartTimer: false });
  }, HOME_HERO_ROTATION_MS);
}

function renderHomeHeroDots() {
  if (!ui.heroCarouselControls || !ui.heroCarouselDots) return;
  ui.heroCarouselControls.hidden = homeHeroSlides.length < 2;
  ui.heroCarouselDots.replaceChildren();
  homeHeroSlides.forEach((slide, index) => {
    const dot = document.createElement("button");
    dot.type = "button";
    dot.className = "carousel-dot";
    dot.setAttribute("role", "tab");
    dot.setAttribute("aria-label", `Mostra ${slide.game.title}`);
    dot.setAttribute("aria-selected", String(index === homeHeroIndex));
    dot.classList.toggle("is-active", index === homeHeroIndex);
    dot.addEventListener("click", () => renderHomeHeroSlide(index));
    ui.heroCarouselDots.append(dot);
  });
}

function renderHomeHeroSlide(index, { restartTimer = true } = {}) {
  if (!homeHeroSlides.length) return;
  homeHeroIndex = (Number(index) + homeHeroSlides.length) % homeHeroSlides.length;
  const slide = homeHeroSlides[homeHeroIndex];
  const { game, entry: personalEntry } = slide;
  const isPersonal = slide.kind === "personal";
  const artwork = homeArtwork(game);

  ui.hero.classList.toggle("is-personal-hero", isPersonal);
  ui.hero.dataset.slideKind = slide.kind;
  ui.heroImage.src = artwork;
  ui.heroImage.alt = game.title || "";
  ui.heroImage.onerror = () => { ui.heroImage.src = PLACEHOLDER; };
  ui.heroTitle.textContent = game.title;

  if (isPersonal) {
    const gameJournalEntries = window.VaultJournal?.listEntries({ gameKey: gameKey(game) }) || [];
    const latestEntry = gameJournalEntries[0] || null;
    const journalMinutes = gameJournalEntries.reduce((sum, item) => sum + Number(item.minutesPlayed || 0), 0);
    const progress = window.VaultJournal?.getProgress(gameKey(game));
    const totalMinutes = Math.max(journalMinutes, Number(progress?.manualPlaytimeMinutes || 0), Number(personalEntry?.steamPlaytimeMinutes || 0));
    ui.heroKicker.textContent = "IN EVIDENZA · DALLA TUA LIBRERIA";
    ui.heroDescription.textContent = `Riprendi ${game.title} e continua a costruire la tua storia di gioco.`;
    ui.heroPrice.textContent = latestEntry ? `Giocato ${relativeTime(latestEntry.playedAt || latestEntry.createdAt)}` : statusLabel(personalEntry?.status);
    ui.heroCountdown.textContent = totalMinutes ? `${formatMinutes(totalMinutes)} totali` : `${entryProgress(personalEntry)}% completato`;
    ui.heroLink.textContent = "Vedi scheda gioco";
    ui.heroLink.href = gameRoute(game);
    ui.heroLink.removeAttribute("target");
    ui.heroLink.removeAttribute("rel");
    ui.heroLibrary.hidden = true;
    ui.heroDetails.hidden = true;
  } else {
    ui.heroKicker.textContent = "IN EVIDENZA · GRATIS ORA";
    ui.heroDescription.textContent = "Disponibile gratuitamente per un periodo limitato. Aggiungilo ora alla tua libreria.";
    ui.heroPrice.textContent = game.fmt_original_price ? `${game.fmt_original_price} → GRATIS` : "GRATIS";
    ui.heroCountdown.textContent = countdownText(game);
    ui.heroLink.textContent = "Riscatta su Epic";
    ui.heroLink.href = game.store_url;
    ui.heroLink.target = "_blank";
    ui.heroLink.rel = "noopener noreferrer";
    ui.heroLibrary.hidden = false;
    ui.heroDetails.hidden = false;
    const inLibrary = Boolean(getLibraryEntry(game));
    ui.heroLibrary.textContent = inLibrary ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
    ui.heroLibrary.onclick = () => toggleLibraryWithoutRerender(game);
    ui.heroDetails.onclick = () => navigate(gameRoute(game));
  }

  renderHomeHeroDots();
  if (restartTimer) startHomeHeroRotation();
}

function renderHero() {
  const previousKey = homeHeroSlides[homeHeroIndex]
    ? gameKey(homeHeroSlides[homeHeroIndex].game) || homeHeroSlides[homeHeroIndex].game?.title
    : null;
  homeHeroSlides = buildHomeHeroSlides();
  const retainedIndex = previousKey
    ? homeHeroSlides.findIndex((slide) => (gameKey(slide.game) || slide.game?.title) === previousKey)
    : -1;
  homeHeroIndex = retainedIndex >= 0 ? retainedIndex : 0;

  ui.hero.hidden = state.route.name !== "home" || !homeHeroSlides.length;
  if (!homeHeroSlides.length) {
    stopHomeHeroRotation();
    return;
  }
  renderHomeHeroSlide(homeHeroIndex);
}

function badgeText(game) {
  const mode = getMode(game);
  if (game.source_kind === "master") return "ENCICLOPEDIA";
  if (game.is_mystery_game) return "MYSTERY GAME";
  if (mode === "current") return "GRATIS ORA";
  if (mode === "upcoming") return "IN ARRIVO";
  if (mode === "expired") return "REGALO PASSATO";
  const stores = (game.stores?.length ? game.stores : (game.store ? [game.store] : [])).filter(Boolean);
  if (!stores.length) return "ARCHIVIO";
  return stores.length > 1
    ? stores.map((store) => storeLabel(store).replace(" Games", "")).join(" + ").toUpperCase()
    : `${storeLabel(stores[0]).toUpperCase()} STORE`;
}

function applyPriceToCard(game, originalPrice, priceLabel) {
  if (game.source_kind === "master") {
    originalPrice.hidden = true;
    originalPrice.textContent = "";
    priceLabel.textContent = "SCHEDA ENCICLOPEDICA";
    return;
  }
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
    else {
      const storeCount = new Set(commercialListingsForGame(game).map((listing) => listing.store)).size;
      priceLabel.textContent = game.fmt_discount_price
        || game.fmt_original_price
        || (storeCount > 1 ? `Disponibile su ${storeCount} store` : `Vedi su ${storeLabel(game.store)}`);
    }
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
  const platforms = fragment.querySelector(".card-platforms");
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
  const cardStores = [...new Set(commercialListingsForGame(game).map((listing) => listing.store))];
  publisher.textContent = game.developer
    || game.publisher
    || (game.source_kind === "master" ? "Archivio IGDB" : cardStores.map(storeLabel).join(" · ") || "Catalogo");
  title.textContent = game.title;
  description.textContent = game.description || "Descrizione non disponibile.";
  platforms.innerHTML = platformBadgesMarkup(game.platforms, { limit: 3, compact: true });
  platforms.hidden = !platforms.innerHTML;
  applyPriceToCard(game, originalPrice, priceLabel);
  countdown.textContent = countdownText(game);
  progress.hidden = game.source_kind !== "promotion";
  configureStoreAction(storeLink, game);
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
  const catalogListView = state.route.name === "catalog" && state.catalogView === "list";
  ui.grid.classList.toggle("is-list-view", catalogListView);
  ui.grid.classList.toggle("is-compact-catalog", state.route.name === "catalog");
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
  if (ui.catalogViewToggle) ui.catalogViewToggle.hidden = route !== "catalog";
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

function updateCatalogViewControls() {
  if (!ui.catalogViewGrid || !ui.catalogViewList) return;
  const isCatalog = state.route.name === "catalog";
  ui.catalogViewToggle.hidden = !isCatalog;
  ui.catalogViewGrid.classList.toggle("is-active", state.catalogView === "grid");
  ui.catalogViewList.classList.toggle("is-active", state.catalogView === "list");
  ui.catalogViewGrid.setAttribute("aria-pressed", String(state.catalogView === "grid"));
  ui.catalogViewList.setAttribute("aria-pressed", String(state.catalogView === "list"));
}

function setCatalogView(view) {
  state.catalogView = view === "list" ? "list" : "grid";
  localStorage.setItem(CATALOG_VIEW_KEY, state.catalogView);
  updateCatalogViewControls();
  renderGames();
}

function renderDashboardHeader() {
  const labels = {
    home: ["LUDOGRAPH", "Scopri i giochi gratuiti"],
    current: ["FREE TRACKER", "Gratis adesso"],
    upcoming: ["FREE TRACKER", "In arrivo"],
    history: ["FREE TRACKER", "Cronologia dei regali"],
    catalog: ["DISCOVER", "Catalogo universale"],
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
  updateCatalogViewControls();

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

function libraryEntryRecords() {
  return Object.values(state.library)
    .filter((entry) => entry?.game)
    .sort((a, b) => new Date(b.updatedAt || b.addedAt || 0) - new Date(a.updatedAt || a.addedAt || 0));
}

function entryProgress(entry) {
  const key = gameKey(entry?.game);
  const journal = key ? window.VaultJournal?.getProgress(key) : null;
  return Math.max(0, Math.min(100, Number(journal?.progressPercent ?? entry?.progressPercent ?? (entry?.status === "completed" ? 100 : 0)) || 0));
}

function routeGameArtwork(entries = libraryEntryRecords()) {
  const selected = entries.find((entry) => entry?.favorite && homeArtwork(entry.game))
    || entries.find((entry) => ["playing", "paused", "completed"].includes(entry?.status) && homeArtwork(entry.game))
    || entries.find((entry) => homeArtwork(entry.game));
  return selected ? homeArtwork(selected.game) : "";
}

function profileWideArtwork(game) {
  return game?.hero_image_url
    || game?.background_image_url
    || game?.wide_image_url
    || "";
}

function profileBackdropArtwork(entries = libraryEntryRecords(), profile = state.auth.profile) {
  const customArtwork = String(profile?.hero_image_url || "").trim();
  if (customArtwork) return customArtwork;

  const personal = entries.find((entry) => entry?.favorite && profileWideArtwork(entry.game))
    || entries.find((entry) => ["playing", "paused", "replay"].includes(entry?.status) && profileWideArtwork(entry.game))
    || entries.find((entry) => entry?.status === "completed" && profileWideArtwork(entry.game))
    || entries.find((entry) => profileWideArtwork(entry.game));
  if (personal) return profileWideArtwork(personal.game);

  const promotion = [...state.current, ...state.upcoming]
    .map(normalizePromotion)
    .find((game) => profileWideArtwork(game));
  if (promotion) return profileWideArtwork(promotion);

  return routeGameArtwork(entries);
}

function renderHomeDiaryPreview(diaryEntries = []) {
  if (!ui.homeDiaryPreview) return;
  const latest = diaryEntries[0] || null;
  if (!latest) {
    ui.homeDiaryPreview.innerHTML = `<div class="v55-empty compact"><strong>Il diario è ancora vuoto.</strong><span>Registra una sessione o una riflessione per iniziare.</span><a href="#/diary">Scrivi la prima pagina</a></div>`;
    return;
  }

  const game = journalGame(latest);
  const date = new Date(latest.playedAt || latest.createdAt || Date.now());
  const validDate = !Number.isNaN(date.getTime());
  const day = validDate ? String(date.getDate()).padStart(2, "0") : "—";
  const monthYear = validDate
    ? date.toLocaleDateString("it-IT", { month: "short", year: "numeric" }).replace(".", "").toLocaleUpperCase("it")
    : "DATA N/D";
  const note = String(latest.note || "Una nuova pagina della tua storia di gioco.").trim();
  const title = latest.note ? `${latest.gameTitle || game.title} — ${note.split(/[.!?]/)[0]}` : (latest.gameTitle || game.title);
  ui.homeDiaryPreview.innerHTML = `<a class="home-diary-entry" href="${escapeAttr(gameRoute(game))}">
    <time><strong>${escapeHtml(day)}</strong><span>${escapeHtml(monthYear)}</span></time>
    <span class="home-diary-copy"><strong>${escapeHtml(title)}</strong><p>${escapeHtml(note)}</p><small>${latest.minutesPlayed ? `${escapeHtml(formatMinutes(latest.minutesPlayed))} registrati` : "Apri la pagina del gioco"}</small></span>
    <img src="${escapeAttr(latest.gameImageUrl || game.image_url || PLACEHOLDER)}" alt="">
  </a>`;
}

function catalogGameSlide(game, source = "catalog") {
  if (!game?.title) return null;
  const copyBySource = {
    recommendation: "Una proposta selezionata a partire dalla tua libreria e dai tuoi segnali di gioco.",
    community: "Tra i titoli più apprezzati e discussi dalla community di Ludograph.",
    recent: "Una delle uscite più recenti entrate nell’archivio universale.",
    indie: "Una scoperta indipendente scelta dall’archivio universale.",
    catalog: "Un’opera da scoprire nell’archivio universale di Ludograph.",
  };
  const kickerBySource = {
    recommendation: "SCELTO PER TE",
    community: "IN EVIDENZA NEL CATALOGO",
    recent: "NUOVO NELL’ARCHIVIO",
    indie: "SCOPERTA INDIPENDENTE",
    catalog: "IN EVIDENZA NEL CATALOGO",
  };
  return {
    key: `game:${gameKey(game) || game.title}`,
    title: game.title,
    copy: copyBySource[source] || copyBySource.catalog,
    artwork: homeArtwork(game),
    href: gameRoute(game),
    kicker: kickerBySource[source] || kickerBySource.catalog,
    button: "Vedi scheda gioco",
  };
}

function buildHomeCatalogSlides(entries = libraryEntryRecords()) {
  const directory = state.editorialDirectory || { franchises: [], collections: [] };
  const discovery = state.discoveryData || {};
  const candidates = [];

  for (const game of (state.discoveryRecommendations?.items || []).slice(0, 2)) {
    candidates.push(catalogGameSlide(game, "recommendation"));
  }
  if (discovery.communityTop?.[0]) candidates.push(catalogGameSlide(discovery.communityTop[0], "community"));
  if (discovery.recent?.[0]) candidates.push(catalogGameSlide(discovery.recent[0], "recent"));
  if (discovery.indie?.[0]) candidates.push(catalogGameSlide(discovery.indie[0], "indie"));

  for (const franchise of (directory.franchises || []).slice(0, 2)) {
    candidates.push({
      key: `franchise:${franchise.slug}`,
      title: franchise.name,
      copy: franchise.description || `Ripercorri ${franchise.game_count || "tutti i"} giochi, continuità e diramazioni della saga.`,
      artwork: franchise.hero_image_url || PLACEHOLDER,
      href: franchiseRoute(franchise.slug),
      kicker: "FRANCHISE IN EVIDENZA",
      button: "Esplora il franchise",
    });
  }
  for (const collection of (directory.collections || []).slice(0, 1)) {
    candidates.push({
      key: `collection:${collection.slug}`,
      title: collection.title,
      copy: collection.description || "Una selezione editoriale curata per attraversare la storia del videogioco.",
      artwork: collection.cover_image_url || PLACEHOLDER,
      href: editorialCollectionRoute(collection.slug),
      kicker: "COLLEZIONE IN EVIDENZA",
      button: "Apri la collezione",
    });
  }

  if (!candidates.filter(Boolean).length) {
    for (const entry of entries.slice(0, 3)) candidates.push(catalogGameSlide(entry.game, "catalog"));
  }

  return uniqueHomeItems(candidates.filter(Boolean), (slide) => slide.key || slide.title).slice(0, 4);
}

function stopHomeCatalogRotation() {
  if (homeCatalogTimer) window.clearInterval(homeCatalogTimer);
  homeCatalogTimer = null;
}

function startHomeCatalogRotation() {
  stopHomeCatalogRotation();
  if (state.route.name !== "home" || homeCatalogSlides.length < 2) return;
  homeCatalogTimer = window.setInterval(() => {
    renderHomeCatalogSlide((homeCatalogIndex + 1) % homeCatalogSlides.length, { restartTimer: false });
  }, HOME_CATALOG_ROTATION_MS);
}

function renderHomeCatalogDots() {
  if (!ui.homeEditorialCarouselControls || !ui.homeEditorialDots) return;
  ui.homeEditorialCarouselControls.hidden = homeCatalogSlides.length < 2;
  ui.homeEditorialDots.replaceChildren();
  homeCatalogSlides.forEach((slide, index) => {
    const dot = document.createElement("button");
    dot.type = "button";
    dot.className = "carousel-dot";
    dot.setAttribute("role", "tab");
    dot.setAttribute("aria-label", `Mostra ${slide.title}`);
    dot.setAttribute("aria-selected", String(index === homeCatalogIndex));
    dot.classList.toggle("is-active", index === homeCatalogIndex);
    dot.addEventListener("click", () => renderHomeCatalogSlide(index));
    ui.homeEditorialDots.append(dot);
  });
}

function renderHomeCatalogSlide(index, { restartTimer = true } = {}) {
  if (!homeCatalogSlides.length) return;
  homeCatalogIndex = (Number(index) + homeCatalogSlides.length) % homeCatalogSlides.length;
  const slide = homeCatalogSlides[homeCatalogIndex];
  ui.homeEditorialFeatureKicker.textContent = slide.kicker;
  ui.homeEditorialFeatureTitle.textContent = slide.title;
  ui.homeEditorialFeatureCopy.textContent = slide.copy;
  ui.homeEditorialFeatureLink.href = slide.href;
  ui.homeEditorialFeatureLink.textContent = slide.button;
  ui.homeEditorialFeature.style.setProperty("--home-feature-art", slide.artwork ? `url("${String(slide.artwork).replaceAll('"', '%22')}")` : "none");
  renderHomeCatalogDots();
  if (restartTimer) startHomeCatalogRotation();
}

function renderHomeCatalogFeature(entries = libraryEntryRecords()) {
  const previousKey = homeCatalogSlides[homeCatalogIndex]?.key || null;
  homeCatalogSlides = buildHomeCatalogSlides(entries);
  const retainedIndex = previousKey ? homeCatalogSlides.findIndex((slide) => slide.key === previousKey) : -1;
  homeCatalogIndex = retainedIndex >= 0 ? retainedIndex : 0;

  if (!homeCatalogSlides.length) {
    stopHomeCatalogRotation();
    ui.homeEditorialFeatureKicker.textContent = "ARCHIVIO EDITORIALE";
    ui.homeEditorialFeatureTitle.textContent = "Esplora oltre la libreria.";
    ui.homeEditorialFeatureCopy.textContent = "Franchise, continuità e collezioni curate per riscoprire la storia del medium.";
    ui.homeEditorialFeatureLink.href = "#/franchises";
    ui.homeEditorialFeatureLink.textContent = "Esplora l’archivio";
    ui.homeEditorialFeature.style.setProperty("--home-feature-art", "none");
    ui.homeEditorialCarouselControls.hidden = true;
    return;
  }
  renderHomeCatalogSlide(homeCatalogIndex);
}

function renderHomeEditorialHighlights(entries = libraryEntryRecords()) {
  if (!ui.homeEditorialList) return;
  const directory = state.editorialDirectory || { franchises: [], collections: [] };
  const editorialItems = [
    ...(directory.collections || []).map((item) => ({
      title: item.title,
      imageUrl: item.cover_image_url,
      count: item.game_count,
      href: editorialCollectionRoute(item.slug),
    })),
    ...(directory.franchises || []).map((item) => ({
      title: item.name,
      imageUrl: item.hero_image_url,
      count: item.game_count,
      href: franchiseRoute(item.slug),
    })),
  ].filter((item) => item.title).slice(0, 3);

  const fallbackItems = entries.slice(0, 3).map((entry) => ({
    title: entry.game.title,
    imageUrl: entry.game.image_url,
    count: null,
    href: gameRoute(entry.game),
  }));
  const items = editorialItems.length ? editorialItems : fallbackItems;

  ui.homeEditorialList.replaceChildren();
  if (!items.length) {
    ui.homeEditorialList.innerHTML = `<div class="v55-empty compact"><strong>L'archivio ti aspetta.</strong><a href="#/franchises">Esplora franchise e collezioni</a></div>`;
    return;
  }

  for (const item of items) {
    const link = document.createElement("a");
    link.href = item.href;
    link.innerHTML = `<img src="${escapeAttr(item.imageUrl || PLACEHOLDER)}" alt=""><span><strong>${escapeHtml(item.title)}</strong>${item.count != null ? `<small>${Number(item.count).toLocaleString("it-IT")} giochi</small>` : ""}</span>`;
    ui.homeEditorialList.append(link);
  }
}

async function hydrateHomeHighlights(entries = libraryEntryRecords()) {
  if (state.homeEditorialLoading || state.homeDiscoveryLoading) return;
  state.homeEditorialLoading = true;
  state.homeDiscoveryLoading = true;
  try {
    const tasks = [];
    if (!state.editorialDirectory && window.VaultFranchises) {
      tasks.push(window.VaultFranchises.getDirectory().then((directory) => {
        state.editorialDirectory = directory || { franchises: [], collections: [] };
      }));
    }
    if (!state.discoveryData && window.VaultCatalog?.configured()) {
      tasks.push(window.VaultCatalog.getDiscovery({ limit: 8 }).then((data) => { state.discoveryData = data; }));
    }
    if (!state.discoveryRecommendations && state.auth.user && window.VaultCatalog?.getRecommendations) {
      tasks.push(window.VaultCatalog.getRecommendations({ limit: 8 }).then((data) => { state.discoveryRecommendations = data; }));
    }
    if (tasks.length) await Promise.allSettled(tasks);
    if (state.route.name === "home") {
      renderHomeCatalogFeature(entries);
      renderHomeEditorialHighlights(entries);
    }
  } catch (error) {
    console.warn("Highlights Home non disponibili", error);
  } finally {
    state.homeEditorialLoading = false;
    state.homeDiscoveryLoading = false;
  }
}

function homeActivityIcon(type) {
  const icon = {
    journal: "diary",
    session: "clock",
    completed: "trophy",
    favorite: "heart",
    library: "library-add",
  }[type] || "library-add";
  return `<svg aria-hidden="true"><use href="#icon-${icon}"></use></svg>`;
}

function buildHomeActivity(entries, diaryEntries) {
  const activities = [];
  for (const item of diaryEntries) {
    activities.push({
      ...item,
      type: item.note ? "journal" : "session",
      detail: item.note ? "Ha aggiunto una nuova entrata al diario" : "Ha aggiornato il tempo di gioco",
      timestamp: item.playedAt || item.createdAt,
    });
  }
  for (const entry of entries) {
    const type = entry.status === "completed" ? "completed" : entry.favorite ? "favorite" : "library";
    const detail = type === "completed"
      ? "Ha completato"
      : type === "favorite"
        ? "Ha aggiunto ai preferiti"
        : "Ha aggiunto alla libreria";
    activities.push({
      gameKey: gameKey(entry.game),
      gameTitle: entry.game.title,
      gameImageUrl: entry.game.image_url,
      type,
      detail,
      timestamp: entry.updatedAt || entry.addedAt,
    });
  }
  return uniqueHomeItems(
    activities.sort((a, b) => new Date(b.timestamp || 0) - new Date(a.timestamp || 0)),
    (item) => `${item.type}:${item.gameKey || item.gameTitle}`
  ).slice(0, 4);
}

function renderHomeExperience() {
  const isHome = state.route.name === "home";
  ui.homeStage.hidden = !isHome;
  ui.homePersonalGrid.hidden = !isHome;
  document.querySelector("#dashboard-page > .stats-grid").hidden = !isHome;
  if (!isHome) {
    stopHomeHeroRotation();
    stopHomeCatalogRotation();
    return;
  }

  const displayName = state.auth.profile?.display_name || state.auth.profile?.username || "GIOCATORE";
  ui.homeWelcomeName.textContent = String(displayName).toLocaleUpperCase("it");
  const entries = libraryEntryRecords();
  const activeEntries = entries.filter((entry) => ["playing", "paused", "replay"].includes(entry.status));
  const resume = (activeEntries.length ? activeEntries : entries).slice(0, 4);
  ui.homeResumeList.replaceChildren();
  if (!resume.length) {
    ui.homeResumeList.innerHTML = `<div class="v55-empty"><strong>La prossima avventura ti aspetta.</strong><span>Imposta un gioco come “In corso” per ritrovarlo qui.</span><a href="#/library">Apri la libreria</a></div>`;
  } else {
    for (const entry of resume) {
      const game = entry.game;
      const progress = entryProgress(entry);
      const item = document.createElement("a");
      item.className = "home-resume-item";
      item.href = gameRoute(game);
      item.innerHTML = `<img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt=""><span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(statusLabel(entry.status))} · ${relativeTime(entry.updatedAt || entry.addedAt)}</small><i><b style="width:${progress}%"></b></i></span><em>${progress}%</em>`;
      ui.homeResumeList.append(item);
    }
  }

  const diaryEntries = window.VaultJournal?.listEntries({ limit: 8 }) || [];
  const activity = buildHomeActivity(entries, diaryEntries);
  ui.homeActivityList.replaceChildren();
  if (!activity.length) {
    ui.homeActivityList.innerHTML = `<div class="v55-empty"><strong>La tua storia comincia qui.</strong><span>Aggiungi giochi o registra una sessione.</span></div>`;
  } else {
    for (const itemData of activity) {
      const game = journalGame(itemData);
      const item = document.createElement("a");
      item.className = `home-activity-item is-${itemData.type}`;
      item.href = gameRoute(game);
      item.innerHTML = `<span class="activity-symbol">${homeActivityIcon(itemData.type)}</span><span><small>${escapeHtml(itemData.detail)}</small><strong>${escapeHtml(itemData.gameTitle || game.title)}</strong></span><time>${relativeTime(itemData.timestamp)}</time>`;
      ui.homeActivityList.append(item);
    }
  }

  renderHomeDiaryPreview(diaryEntries);
  renderHomeCatalogFeature(entries);
  renderHomeEditorialHighlights(entries);
  void hydrateHomeHighlights(entries);
}

function libraryLaneMarkup(title, entries, variant = "compact") {
  if (!entries.length) return "";
  const cards = entries.slice(0, variant === "feature" ? 4 : 5).map((entry) => {
    const game = entry.game;
    const progress = entryProgress(entry);
    return `<a class="library-lane-card ${variant}" href="${escapeAttr(gameRoute(game))}">
      <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
      <span class="library-lane-copy"><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(statusLabel(entry.status))}${entry.favorite ? " · Preferito" : ""}</small>${variant === "feature" ? `<i><b style="width:${progress}%"></b></i><em>${progress}%</em>` : ""}</span>
    </a>`;
  }).join("");
  return `<section class="library-lane"><header><h2>${escapeHtml(title)}</h2><span>${entries.length}</span></header><div class="library-lane-track">${cards}</div></section>`;
}

function renderLibraryExperience() {
  const isLibrary = state.route.name === "library";
  ui.libraryShowcase.hidden = !isLibrary;
  ui.libraryLanes.hidden = !isLibrary;
  if (!isLibrary) return;
  const entries = libraryEntryRecords();
  const summary = window.VaultJournal?.summarize() || { totalMinutes: 0 };
  const playing = entries.filter((entry) => ["playing", "paused", "replay"].includes(entry.status));
  const completed = entries.filter((entry) => entry.status === "completed");
  const backlog = entries.filter((entry) => ["backlog", "saved"].includes(entry.status));
  const favorites = entries.filter((entry) => entry.favorite);
  ui.librarySummaryTotal.textContent = entries.length.toLocaleString("it-IT");
  ui.librarySummaryPlaying.textContent = playing.length.toLocaleString("it-IT");
  ui.librarySummaryCompleted.textContent = completed.length.toLocaleString("it-IT");
  ui.librarySummaryHours.textContent = formatMinutes(summary.totalMinutes || summary.sessionMinutes || 0);
  ui.librarySummaryFavorites.textContent = favorites.length.toLocaleString("it-IT");
  const artwork = routeGameArtwork(entries);
  ui.librarySummaryVisual.style.setProperty("--library-art", artwork ? `url("${artwork.replaceAll('"', '%22')}")` : "none");
  ui.libraryLanes.innerHTML = [
    libraryLaneMarkup("In corso", playing, "feature"),
    libraryLaneMarkup("Completati", completed),
    libraryLaneMarkup("Backlog", backlog),
    libraryLaneMarkup("Aggiunti di recente", entries),
  ].filter(Boolean).join("") || `<div class="v55-empty"><strong>La tua libreria è ancora vuota.</strong><span>Esplora il catalogo universale e aggiungi la prima opera.</span><a href="#/catalog">Apri il catalogo</a></div>`;
}

function renderRouteExperience() {
  renderHomeExperience();
  renderLibraryExperience();
}

function renderDashboard() {
  renderHero();
  renderDashboardHeader();
  renderRouteExperience();
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

function ratingStarsMarkup(value) {
  const rounded = Math.max(0, Math.min(5, Math.round(Number(value) || 0)));
  return `${"★".repeat(rounded)}${"☆".repeat(5 - rounded)}`;
}

function updatePersonalGameRatingSummary(value) {
  const rating = Math.max(0, Math.min(5, Number(value) || 0));
  if (ui.gameSummaryRatingStars) ui.gameSummaryRatingStars.textContent = ratingStarsMarkup(rating);
  if (ui.gameSummaryRating) ui.gameSummaryRating.textContent = rating ? `${rating}/5` : "—";
  if (ui.gameSummaryRatingCopy) {
    ui.gameSummaryRatingCopy.textContent = rating
      ? rating >= 5 ? "Tra i tuoi giochi imprescindibili."
        : rating >= 4 ? "Un titolo che consiglieresti."
          : rating >= 3 ? "Una buona esperienza, con qualche riserva."
            : "La tua valutazione personale."
      : "Non hai ancora valutato questo gioco.";
  }
}

function renderCommunityGameRating(reviews, unavailableMessage = "") {
  if (!ui.gameCommunityRatingAverage || !ui.gameCommunityRatingDistribution) return;
  const values = Array.isArray(reviews)
    ? reviews.map((review) => Number(review?.rating || 0)).filter((rating) => rating >= 1 && rating <= 5)
    : [];
  const count = values.length;
  const average = count ? values.reduce((sum, rating) => sum + rating, 0) / count : 0;
  ui.gameCommunityRatingAverage.textContent = count ? average.toFixed(1) : "—";
  ui.gameCommunityRatingStars.textContent = count ? ratingStarsMarkup(average) : "☆☆☆☆☆";
  ui.gameCommunityRatingCount.textContent = unavailableMessage || (count
    ? `Basato su ${count.toLocaleString("it-IT")} ${count === 1 ? "voto pubblico" : "voti pubblici"}`
    : "Nessun voto pubblico");
  ui.gameCommunityRatingDistribution.replaceChildren();
  for (let rating = 5; rating >= 1; rating -= 1) {
    const ratingCount = values.filter((value) => value === rating).length;
    const percent = count ? Math.round((ratingCount / count) * 100) : 0;
    const row = document.createElement("div");
    row.className = "game-rating-distribution-row";
    row.innerHTML = `<span>${rating} ★</span><i><b style="width:${percent}%"></b></i><em>${percent}%</em>`;
    ui.gameCommunityRatingDistribution.append(row);
  }
}

function gameMediaUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  try {
    const parsed = new URL(raw, window.location.href);
    return ["http:", "https:"].includes(parsed.protocol) ? parsed.href : "";
  } catch {
    return "";
  }
}

function normalizedGameMedia(game) {
  const seenImages = new Set();
  const images = [];
  const appendImages = (items, kind) => {
    for (const item of Array.isArray(items) ? items : []) {
      const source = typeof item === "string" ? item : item?.url;
      const url = gameMediaUrl(source);
      if (!url || seenImages.has(url)) continue;
      seenImages.add(url);
      images.push({
        type: "image",
        kind,
        url,
        thumbnailUrl: gameMediaUrl(item?.thumbnail_url) || url,
        caption: kind === "artwork" ? `Artwork di ${game?.title || "gioco"}` : `Screenshot di ${game?.title || "gioco"}`,
      });
    }
  };
  appendImages(game?.screenshots, "screenshot");
  appendImages(game?.artworks, "artwork");

  const seenVideos = new Set();
  const videos = [];
  for (const item of Array.isArray(game?.videos) ? game.videos : []) {
    const rawId = String(item?.video_id || "").trim();
    if (!/^[A-Za-z0-9_-]{6,32}$/.test(rawId) || seenVideos.has(rawId)) continue;
    seenVideos.add(rawId);
    videos.push({
      type: "video",
      videoId: rawId,
      thumbnailUrl: gameMediaUrl(item?.thumbnail_url) || `https://i.ytimg.com/vi/${rawId}/hqdefault.jpg`,
      embedUrl: `https://www.youtube-nocookie.com/embed/${rawId}`,
      caption: String(item?.name || "Trailer").trim() || "Trailer",
    });
  }
  return [...images, ...videos];
}

function closeGameMediaDialog() {
  if (!ui.gameMediaDialog) return;
  ui.gameMediaDialogContent?.replaceChildren();
  if (ui.gameMediaDialog.open) ui.gameMediaDialog.close();
}

function openGameMediaDialog(item) {
  if (!ui.gameMediaDialog || !ui.gameMediaDialogContent) return;
  ui.gameMediaDialogContent.replaceChildren();
  if (item.type === "video") {
    const iframe = document.createElement("iframe");
    iframe.src = `${item.embedUrl}?autoplay=1&rel=0`;
    iframe.title = item.caption;
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share";
    iframe.allowFullscreen = true;
    iframe.referrerPolicy = "strict-origin-when-cross-origin";
    ui.gameMediaDialogContent.append(iframe);
  } else {
    const image = document.createElement("img");
    image.src = item.url;
    image.alt = item.caption;
    ui.gameMediaDialogContent.append(image);
  }
  if (ui.gameMediaDialogCaption) ui.gameMediaDialogCaption.textContent = item.caption;
  if (!ui.gameMediaDialog.open) ui.gameMediaDialog.showModal();
}

function renderGameMedia(game) {
  if (!ui.gameMediaPanel || !ui.gameMediaGallery) return;
  const media = normalizedGameMedia(game);
  const available = media.length > 0;
  ui.gameMediaPanel.hidden = !available;
  if (ui.gameMediaNav) ui.gameMediaNav.hidden = !available;
  ui.gameMediaGallery.replaceChildren();
  if (ui.gameMediaCount) {
    ui.gameMediaCount.textContent = available
      ? `${media.length.toLocaleString("it-IT")} ${media.length === 1 ? "contenuto" : "contenuti"}`
      : "";
  }
  closeGameMediaDialog();
  if (!available) return;

  media.slice(0, 5).forEach((item, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `game-media-item${index === 0 ? " is-featured" : ""}${item.type === "video" ? " is-video" : ""}`;
    button.setAttribute("aria-label", item.type === "video" ? `Riproduci ${item.caption}` : `Apri ${item.caption}`);
    const image = document.createElement("img");
    image.src = item.thumbnailUrl || item.url;
    image.alt = "";
    image.loading = index === 0 ? "eager" : "lazy";
    image.decoding = "async";
    image.onerror = () => { image.src = game.image_url || PLACEHOLDER; };
    button.append(image);
    const overlay = document.createElement("span");
    overlay.className = "game-media-item-overlay";
    overlay.innerHTML = item.type === "video"
      ? `<i aria-hidden="true">▶</i><b>${escapeHtml(item.caption)}</b>`
      : `<b>${item.kind === "artwork" ? "Artwork" : "Screenshot"}</b>`;
    button.append(overlay);
    if (index === 4 && media.length > 5) {
      const more = document.createElement("em");
      more.textContent = `+${media.length - 5}`;
      button.append(more);
    }
    button.onclick = () => openGameMediaDialog(item);
    ui.gameMediaGallery.append(button);
  });

  if (ui.gameMediaDialogClose) ui.gameMediaDialogClose.onclick = closeGameMediaDialog;
  ui.gameMediaDialog.onclick = (event) => {
    if (event.target === ui.gameMediaDialog) closeGameMediaDialog();
  };
  ui.gameMediaDialog.onclose = () => ui.gameMediaDialogContent?.replaceChildren();
}

function gameDetailArtwork(game) {
  return game?.hero_image_url
    || game?.background_image_url
    || game?.wide_image_url
    || gameMediaUrl(game?.artworks?.[0]?.url)
    || gameMediaUrl(game?.screenshots?.[0]?.url)
    || game?.image_url
    || PLACEHOLDER;
}

function renderRating(game, entry) {
  ui.gamePageRating.replaceChildren();
  const selected = Number(entry?.rating || 0);
  updatePersonalGameRatingSummary(selected);
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
      updatePersonalGameRatingSummary(nextRating);
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
  const listings = commercialListingsForGame(game)
    .sort((a, b) => {
      const priority = { epic: 0, steam: 1, playstation: 2, xbox: 3 };
      return (priority[a.store] ?? 99) - (priority[b.store] ?? 99);
    });

  if (!listings.length) {
    ui.gamePageStoreOptions.innerHTML = '<div class="timeline-empty">Nessuna disponibilità digitale registrata per questo titolo.</div>';
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
      <div class="store-option-logo">${storeLogoMarkup(listing.store)}</div>
      <div class="store-option-copy">
        <strong>${escapeHtml(storeLabel(listing.store))}</strong>
        <span>${escapeHtml(edition)}</span>
        <small>${escapeHtml(price)}</small>
      </div>
      <a class="button button-secondary" href="${escapeAttr(listing.store_url)}" target="_blank" rel="noopener noreferrer">
        Apri su ${escapeHtml(storeLabel(listing.store))}
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
    ? `${total.toLocaleString("it-IT")} giochi nel catalogo universale`
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

  if (!window.VaultCatalog?.configured() || getMode(game) !== "catalog") {
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

const FRANCHISE_TRACK_TYPE_LABELS = {
  continuity: "Continuità",
  timeline: "Linea temporale",
  subseries: "Sottosaga",
  story_arc: "Arco narrativo",
  anthology: "Antologia",
  remake_line: "Linea remake",
  collection: "Raccolte",
  other: "Percorso editoriale",
};

const FRANCHISE_CANON_LABELS = {
  canon: "Canonico",
  alternate_canon: "Continuità alternativa",
  reimagining: "Reinterpretazione",
  non_canon: "Non canonico",
  unknown: "Canonicità non definita",
  editorial_only: "Elemento editoriale",
};

const FRANCHISE_RELATION_TYPE_LABELS = {
  sequel_to: "Sequel di",
  prequel_to: "Prequel di",
  remake_of: "Remake di",
  remaster_of: "Remaster di",
  reimagines: "Reinterpreta",
  alternate_version_of: "Versione alternativa di",
  parallel_to: "Parallelo a",
  expansion_of: "Espansione di",
  collection_of: "Raccolta di",
  contains: "Contiene",
  spiritual_successor_to: "Successore spirituale di",
  related_to: "Collegato a",
};

function editorialCard({ title, description, imageUrl, count, href, badge, kind = "franchise", paths = null, yearLabel = "Cronologia" }) {
  const article = document.createElement("article");
  article.className = `editorial-directory-card franchise-index-card ${kind === "collection" ? "is-collection" : "is-franchise"}`;
  const numericCount = Number(count || 0);
  const numericPaths = Number(paths || 0);
  const primaryLabel = kind === "collection"
    ? `${numericCount.toLocaleString("it-IT")} articoli`
    : `${numericCount.toLocaleString("it-IT")} giochi`;
  const secondaryLabel = kind === "collection"
    ? "Curata"
    : (numericPaths > 0 ? `${numericPaths.toLocaleString("it-IT")} percorsi` : "Percorsi");
  const tertiaryLabel = kind === "collection" ? "Set editoriale" : yearLabel;
  article.innerHTML = `
    <a class="editorial-card-cover" href="${escapeAttr(href)}">
      <img src="${escapeAttr(imageUrl || PLACEHOLDER)}" alt="" loading="lazy">
      <span class="editorial-card-scrim"></span>
      <span class="official-badge">${escapeHtml(badge)}</span>
    </a>
    <div class="editorial-card-copy">
      <h3><a href="${escapeAttr(href)}">${escapeHtml(title)}</a></h3>
      <p>${escapeHtml(description || "Descrizione editoriale in preparazione.")}</p>
      <div class="franchise-index-card-meta" aria-label="Metadati">
        <span><svg aria-hidden="true"><use href="#icon-gamepad"></use></svg><b>${escapeHtml(primaryLabel)}</b></span>
        <span><svg aria-hidden="true"><use href="${kind === "collection" ? "#icon-star" : "#icon-franchise"}"></use></svg><b>${escapeHtml(secondaryLabel)}</b></span>
        <span><svg aria-hidden="true"><use href="#icon-calendar"></use></svg><b>${escapeHtml(tertiaryLabel)}</b></span>
      </div>
      <div class="franchise-index-card-footer"><span><i></i>${kind === "collection" ? "Pubblicata" : "Attiva"}</span><a href="${escapeAttr(href)}">Apri →</a></div>
    </div>`;
  const image = article.querySelector("img");
  image.onerror = () => { image.src = PLACEHOLDER; };
  return article;
}

function stopEditorialFeaturedCarousel() {
  if (editorialFeaturedTimer) window.clearInterval(editorialFeaturedTimer);
  editorialFeaturedTimer = null;
}

function renderEditorialFeaturedSlide() {
  const hero = document.getElementById("franchise-featured-hero");
  if (!hero) return;
  const featured = editorialFeaturedSlides[editorialFeaturedIndex];
  if (!featured) return;
  const count = Number(featured.game_count || 0);
  const slideCount = editorialFeaturedSlides.length;
  const route = franchiseRoute(featured.slug);
  hero.innerHTML = `
    <img src="${escapeAttr(featured.hero_image_url || PLACEHOLDER)}" alt="" loading="lazy">
    <span class="franchise-featured-scrim"></span>
    <div class="franchise-featured-copy">
      <span class="official-badge">FRANCHISE UFFICIALE</span>
      <h2>${escapeHtml(featured.name)}</h2>
      <p>${escapeHtml(featured.description || `Ripercorri ${featured.name}: uscite, cronologia, spin-off e percorsi editoriali.`)}</p>
      <div class="franchise-featured-stats">
        <span><svg aria-hidden="true"><use href="#icon-gamepad"></use></svg><b>${count.toLocaleString("it-IT")}</b><small>Giochi totali</small></span>
        <span><svg aria-hidden="true"><use href="#icon-franchise"></use></svg><b>Percorsi</b><small>Narrativi</small></span>
      </div>
      <div class="franchise-featured-actions">
        <a class="button button-primary" href="${escapeAttr(route)}">Apri franchise <svg aria-hidden="true"><use href="#icon-chevron-right"></use></svg></a>
        <a class="button button-secondary" href="${escapeAttr(`${route}?tab=paths`)}">Esplora percorsi</a>
      </div>
    </div>
    ${slideCount > 1 ? `<div class="franchise-featured-dots" aria-label="Franchise in evidenza">${editorialFeaturedSlides.map((_, index) => `<button class="${index === editorialFeaturedIndex ? "is-active" : ""}" type="button" data-featured-index="${index}" aria-label="Mostra franchise ${index + 1}"></button>`).join("")}</div>` : ""}`;
  const image = hero.querySelector("img");
  image.onerror = () => { image.src = PLACEHOLDER; };
  hero.querySelectorAll("[data-featured-index]").forEach((button) => {
    button.addEventListener("click", () => {
      editorialFeaturedIndex = Number(button.dataset.featuredIndex || 0);
      renderEditorialFeaturedSlide();
      startEditorialFeaturedCarousel();
    });
  });
}

function startEditorialFeaturedCarousel() {
  stopEditorialFeaturedCarousel();
  if (editorialFeaturedSlides.length <= 1) return;
  editorialFeaturedTimer = window.setInterval(() => {
    editorialFeaturedIndex = (editorialFeaturedIndex + 1) % editorialFeaturedSlides.length;
    renderEditorialFeaturedSlide();
  }, EDITORIAL_FEATURED_ROTATION_MS);
}

function renderEditorialFeaturedHero(directory = {}) {
  const hero = document.getElementById("franchise-featured-hero");
  if (!hero) return;
  stopEditorialFeaturedCarousel();
  const franchises = [...(directory.franchises || [])]
    .filter((item) => item && item.slug)
    .sort((a, b) => Number(b.game_count || 0) - Number(a.game_count || 0));
  editorialFeaturedSlides = [...franchises.filter((item) => item.hero_image_url), ...franchises.filter((item) => !item.hero_image_url)].slice(0, 5);
  editorialFeaturedIndex = 0;
  if (!editorialFeaturedSlides.length) {
    hero.innerHTML = `
      <div class="franchise-featured-empty">
        <p class="eyebrow">FRANCHISE UFFICIALE</p>
        <h2>Archivio in preparazione</h2>
        <p>Le saghe pubblicate dagli amministratori appariranno qui.</p>
      </div>`;
    return;
  }
  hero.onmouseenter = stopEditorialFeaturedCarousel;
  hero.onmouseleave = startEditorialFeaturedCarousel;
  hero.onfocusin = stopEditorialFeaturedCarousel;
  hero.onfocusout = startEditorialFeaturedCarousel;
  renderEditorialFeaturedSlide();
  startEditorialFeaturedCarousel();
}

function bindEditorialDirectoryFilters() {
  const buttons = $$("[data-editorial-filter]");
  if (!buttons.length) return;
  const franchiseBlock = document.querySelector('[data-editorial-block="franchises"]');
  const collectionBlock = document.querySelector('[data-editorial-block="collections"]');
  for (const button of buttons) {
    button.onclick = () => {
      const filter = button.dataset.editorialFilter || "all";
      buttons.forEach((item) => item.classList.toggle("is-active", item === button));
      if (franchiseBlock) franchiseBlock.hidden = filter === "collections";
      if (collectionBlock) collectionBlock.hidden = !["all", "collections", "remakes"].includes(filter);
      if (["paths", "franchise", "remakes"].includes(filter) && franchiseBlock) franchiseBlock.hidden = false;
    };
  }
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
    renderEditorialFeaturedHero(state.editorialDirectory);
    bindEditorialDirectoryFilters();
    ui.franchiseDirectoryGrid.replaceChildren();
    ui.collectionDirectoryGrid.replaceChildren();
    const franchiseCountLabel = document.getElementById("franchise-directory-count");
    if (franchiseCountLabel) franchiseCountLabel.textContent = `${Number((state.editorialDirectory.franchises || []).length || 0).toLocaleString("it-IT")} ufficiali`;

    for (const franchise of state.editorialDirectory.franchises || []) {
      ui.franchiseDirectoryGrid.append(editorialCard({
        title: franchise.name,
        description: franchise.description,
        imageUrl: franchise.hero_image_url,
        count: franchise.game_count,
        href: franchiseRoute(franchise.slug),
        badge: "FRANCHISE",
        kind: "franchise",
        paths: franchise.track_count || franchise.path_count || franchise.narrative_path_count || franchise.paths_count || null,
      }));
    }
    for (const collection of state.editorialDirectory.collections || []) {
      ui.collectionDirectoryGrid.append(editorialCard({
        title: collection.title,
        description: collection.description,
        imageUrl: collection.cover_image_url,
        count: collection.game_count,
        href: editorialCollectionRoute(collection.slug),
        badge: "COLLEZIONE CURATA",
        kind: "collection",
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
  ui.franchiseProgress.style.setProperty("--progress", `${average}%`);
  ui.franchiseProgress.hidden = false;
}

function franchiseOrderValue(game) {
  if (state.franchiseOrder === "narrative") {
    return Number(game.narrative_order || 100000 + Number(game.release_order || 0));
  }
  return Number(game.release_order || 100000);
}

function franchiseWorkVariants(game) {
  const primaryKey = gameKey(game);
  const variants = Array.isArray(game?.variants) ? game.variants : [];
  const seen = new Set();
  return variants.filter((variant) => {
    const key = gameKey(variant);
    if (!key || key === primaryKey || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function renderFranchiseVariantItems(list, variants, game) {
  list.replaceChildren();
  for (const variant of variants) {
    const item = document.createElement("article");
    item.className = "franchise-variant-item";
    item.innerHTML = `
      <img src="${escapeAttr(variant.image_url || game.image_url || PLACEHOLDER)}" alt="">
      <div>
        <strong>${escapeHtml(variant.title || game.title)}</strong>
        <small>${escapeHtml(gameDisambiguationMarkup(variant))}</small>
        <div class="platform-chip-list">${platformBadgesMarkup(variant.platforms, { limit: 4, compact: true })}</div>
      </div>
      <div class="franchise-variant-actions">
        <a class="button button-secondary" href="${escapeAttr(gameRoute(variant))}">Scheda</a>
        <button class="button button-secondary" type="button" data-variant-library>${getLibraryEntry(variant) ? "Rimuovi" : "Aggiungi"}</button>
      </div>`;
    item.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    item.querySelector("[data-variant-library]").onclick = () => {
      toggleLibraryWithoutRerender(variant);
      item.querySelector("[data-variant-library]").textContent = getLibraryEntry(variant) ? "Rimuovi" : "Aggiungi";
      renderFranchiseProgress(state.franchiseData?.games || []);
    };
    list.append(item);
  }
}

function renderFranchiseGameRow(game) {
  const progress = franchiseGameProgress(game);
  const variantsLoaded = game.__franchiseVariantsLoaded === true || Array.isArray(game?.variants);
  if (Array.isArray(game?.variants)) game.__franchiseVariantsLoaded = true;
  const variants = franchiseWorkVariants(game);
  const row = document.createElement("article");
  row.className = "franchise-game-row";
  row.innerHTML = `
    <button class="franchise-game-cover" type="button"><img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt=""></button>
    <div class="franchise-game-copy">
      <div class="franchise-game-heading">
        <div><small>${escapeHtml(game.developer || game.publisher || "")}</small><h3>${escapeHtml(game.title)}</h3></div>
        <span class="pill">${escapeHtml(game.release_year || "Anno n/d")}</span>
      </div>
      <div class="platform-chip-list franchise-platforms">${platformBadgesMarkup(game.platforms, { limit: 5, compact: true })}</div>
      <div class="franchise-game-orders">
        <span>Uscita #${Number(game.release_order || 0)}</span>
        ${game.narrative_order ? `<span>Narrativa #${Number(game.narrative_order)}</span>` : `<span>Narrativa non definita</span>`}
        ${progress.status ? `<span>${escapeHtml(statusLabel(progress.status))} · ${Math.max(0, Math.min(100, progress.percent || 0))}%</span>` : `<span>Non iniziato</span>`}
      </div>
      ${game.franchise_note ? `<p>${escapeHtml(game.franchise_note)}</p>` : ""}
      <button class="franchise-variants-toggle" type="button" aria-expanded="false" ${variantsLoaded && !variants.length ? "disabled" : ""}>
        <span>${variantsLoaded ? (variants.length ? `${variants.length} ${variants.length === 1 ? "versione o porting" : "versioni e porting"}` : "Nessuna versione aggiuntiva") : "Versioni e porting"}</span>
        <b aria-hidden="true">⌄</b>
      </button>
      <div class="franchise-variant-list" hidden></div>
      <div class="franchise-game-actions"><a class="button button-secondary" href="${escapeAttr(gameRoute(game))}">Scheda</a><button class="button button-secondary" data-saga-library type="button">${getLibraryEntry(game) ? "Rimuovi dalla libreria" : "Aggiungi alla libreria"}</button></div>
    </div>`;
  row.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
  row.querySelector(".franchise-game-cover").onclick = () => navigate(gameRoute(game));
  row.querySelector("[data-saga-library]").onclick = () => {
    toggleLibraryWithoutRerender(game);
    row.querySelector("[data-saga-library]").textContent = getLibraryEntry(game) ? "Rimuovi dalla libreria" : "Aggiungi alla libreria";
    renderFranchiseProgress(state.franchiseData?.games || []);
  };

  const toggle = row.querySelector(".franchise-variants-toggle");
  const toggleLabel = toggle.querySelector("span");
  const list = row.querySelector(".franchise-variant-list");
  if (variants.length) renderFranchiseVariantItems(list, variants, game);

  toggle.onclick = async () => {
    if (game.__franchiseVariantsLoading) return;

    if (!game.__franchiseVariantsLoaded) {
      const slug = state.route.params.slug;
      const key = gameKey(game);
      game.__franchiseVariantsLoading = true;
      toggle.disabled = true;
      toggleLabel.textContent = "Caricamento versioni…";
      try {
        const payload = await window.VaultFranchises.getFranchiseGameVariants(slug, key);
        if (!row.isConnected || state.route.name !== "franchise" || state.route.params.slug !== slug) return;
        game.variants = Array.isArray(payload?.variants) ? payload.variants : [];
        game.variant_count = Number(payload?.variant_count || game.variants.length || 0);
        game.editorial_work_key = payload?.editorial_work_key || game.editorial_work_key || null;
        game.__franchiseVariantsLoaded = true;
        const loadedVariants = franchiseWorkVariants(game);
        renderFranchiseVariantItems(list, loadedVariants, game);
        if (!loadedVariants.length) {
          toggleLabel.textContent = "Nessuna versione aggiuntiva";
          toggle.disabled = true;
          list.hidden = true;
          return;
        }
        toggleLabel.textContent = `${loadedVariants.length} ${loadedVariants.length === 1 ? "versione o porting" : "versioni e porting"}`;
        toggle.disabled = false;
        toggle.setAttribute("aria-expanded", "true");
        list.hidden = false;
      } catch (error) {
        console.error("Versioni del gioco non disponibili", error);
        if (!row.isConnected) return;
        toggleLabel.textContent = "Versioni non disponibili · Riprova";
        toggle.disabled = false;
      } finally {
        game.__franchiseVariantsLoading = false;
      }
      return;
    }

    const loadedVariants = franchiseWorkVariants(game);
    if (!loadedVariants.length) return;
    const expanded = toggle.getAttribute("aria-expanded") === "true";
    toggle.setAttribute("aria-expanded", String(!expanded));
    list.hidden = expanded;
  };
  return row;
}

function franchiseGameByKeyMap() {
  const map = new Map();
  for (const game of state.franchiseData?.games || []) map.set(gameKey(game), game);
  return map;
}

function franchiseTrackGames(track) {
  const memberships = [];
  for (const game of state.franchiseData?.games || []) {
    const membership = (game.track_memberships || []).find((item) => item.track_key === track.track_key);
    if (membership) memberships.push({ game, membership });
  }
  memberships.sort((a, b) => Number(a.membership.narrative_order || 100000) - Number(b.membership.narrative_order || 100000)
    || Number(a.game.release_order || 100000) - Number(b.game.release_order || 100000)
    || String(a.game.title || "").localeCompare(String(b.game.title || ""), "it"));
  return memberships;
}

function franchiseTrackCompletion(memberships = []) {
  if (!memberships.length) return { completed: 0, total: 0, percent: 0 };
  let completed = 0;
  let totalPercent = 0;
  for (const { game } of memberships) {
    const progress = franchiseGameProgress(game);
    const done = progress.status === "completed";
    if (done) completed += 1;
    totalPercent += done ? 100 : Math.max(0, Math.min(100, progress.percent || 0));
  }
  return { completed, total: memberships.length, percent: Math.round(totalPercent / memberships.length) };
}

function franchiseTrackBadges(track, memberships = []) {
  const statuses = new Set(memberships.map(({ membership }) => membership.canon_status || "unknown"));
  const labels = [];
  if (track.track_type) labels.push(FRANCHISE_TRACK_TYPE_LABELS[track.track_type] || "Percorso");
  if (statuses.has("canon")) labels.push("Canonico");
  if (statuses.has("alternate_canon") || statuses.has("reimagining")) labels.push("Alternativo");
  if (!labels.length) labels.push("Editoriale");
  return labels.slice(0, 3).map((label) => `<span>${escapeHtml(label)}</span>`).join("");
}

function renderFranchiseTimelineItem(game, membership = {}) {
  const progress = franchiseGameProgress(game);
  const percent = Math.max(0, Math.min(100, progress.percent || (progress.status === "completed" ? 100 : 0)));
  const item = document.createElement("article");
  item.className = "franchise-timeline-item";
  item.innerHTML = `
    <a class="franchise-timeline-cover" href="${escapeAttr(gameRoute(game))}"><img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="" loading="lazy"></a>
    <div class="franchise-timeline-copy">
      <strong><a href="${escapeAttr(gameRoute(game))}">${escapeHtml(game.title || "Titolo")}</a></strong>
      <span>${escapeHtml(releaseYearOf(game) || game.release_year || "Anno n/d")}</span>
      <small>Ordine ${escapeHtml(membership.narrative_order || game.narrative_order || game.release_order || "—")}</small>
      ${percent ? `<i style="--item-progress:${percent}%"></i>` : ""}
    </div>`;
  const image = item.querySelector("img");
  image.onerror = () => { image.src = PLACEHOLDER; };
  return item;
}

function renderFranchiseTrackSection(track, gameMap) {
  void gameMap;
  const memberships = franchiseTrackGames(track);
  const completion = franchiseTrackCompletion(memberships);
  const section = document.createElement("section");
  section.className = "franchise-group franchise-track-group franchise-path-lane";
  const parent = track.parent_track_key ? (state.franchiseData?.tracks || []).find((item) => item.track_key === track.parent_track_key) : null;
  section.innerHTML = `
    <div class="franchise-path-summary">
      <div class="franchise-path-number">${escapeHtml(track.sort_order || "•")}</div>
      <div class="franchise-path-copy">
        <div class="franchise-track-kicker">${franchiseTrackBadges(track, memberships)}${parent ? `<span>Dentro ${escapeHtml(parent.name)}</span>` : ""}</div>
        <h2>${escapeHtml(track.name || "Percorso narrativo")}</h2>
        ${track.description ? `<p>${escapeHtml(track.description)}</p>` : `<p>Linea editoriale ordinata per attraversare questo arco della saga.</p>`}
        <div class="franchise-path-progress"><strong>${completion.percent}%</strong><span><i style="width:${completion.percent}%"></i></span><small>${completion.completed}/${completion.total} completati</small></div>
      </div>
    </div>`;
  const timeline = document.createElement("div");
  timeline.className = "franchise-timeline-strip";
  if (!memberships.length) {
    timeline.innerHTML = `<div class="timeline-empty">Nessun gioco assegnato a questo percorso.</div>`;
  } else {
    for (const { game, membership } of memberships) timeline.append(renderFranchiseTimelineItem(game, membership));
  }
  section.append(timeline);
  return section;
}

function renderFranchiseRelations(gameMap) {
  const relations = state.franchiseData?.relations || [];
  if (!relations.length) return null;
  const section = document.createElement("section");
  section.className = "franchise-group franchise-relations-group";
  section.innerHTML = `<header><div><p class="eyebrow">GRAFO EDITORIALE</p><h2>Relazioni tra giochi</h2></div><span>${relations.length}</span></header>`;
  const list = document.createElement("div");
  list.className = "franchise-relation-list";
  for (const relation of relations) {
    const source = gameMap.get(relation.source_game_key);
    const target = gameMap.get(relation.target_game_key);
    const item = document.createElement("article");
    item.className = "franchise-relation-card";
    item.innerHTML = `
      <a class="relation-game" href="${escapeAttr(source ? gameRoute(source) : "#")}"><img src="${escapeAttr(source?.image_url || PLACEHOLDER)}" alt=""><strong>${escapeHtml(source?.title || relation.source_game_key)}</strong></a>
      <span class="relation-kind"><b>${escapeHtml(FRANCHISE_RELATION_TYPE_LABELS[relation.relation_type] || relation.relation_type)}</b><i aria-hidden="true">→</i></span>
      <a class="relation-game relation-game-target" href="${escapeAttr(target ? gameRoute(target) : "#")}"><img src="${escapeAttr(target?.image_url || PLACEHOLDER)}" alt=""><strong>${escapeHtml(target?.title || relation.target_game_key)}</strong></a>
      ${relation.note ? `<p>${escapeHtml(relation.note)}</p>` : ""}`;
    item.querySelectorAll("img").forEach((image) => { image.onerror = () => { image.src = PLACEHOLDER; }; });
    list.append(item);
  }
  section.append(list);
  return section;
}

function franchisePrimaryGames(games = []) {
  return [...games].filter((game) => (game.relation_type || "main") === "main")
    .sort((a, b) => Number(a.release_order || 100000) - Number(b.release_order || 100000)
      || String(a.title || "").localeCompare(String(b.title || ""), "it"));
}

function renderFranchiseContextRail(data = {}) {
  const rail = document.getElementById("franchise-context-rail");
  if (!rail) return;
  const games = data.games || [];
  const tracks = data.tracks || [];
  const mainGames = franchisePrimaryGames(games);
  const firstMain = mainGames[0] || games[0];
  const firstTrack = tracks[0];
  const modernStart = [...mainGames].reverse().find((game) => releaseYearOf(game) && Number(releaseYearOf(game)) >= 2015) || mainGames[mainGames.length - 1] || firstMain;
  const collections = (state.editorialDirectory?.collections || []).slice(0, 3);
  rail.innerHTML = `
    <section class="franchise-rail-panel franchise-main-games-panel">
      <header><div><p class="eyebrow">GIOCHI PRINCIPALI</p><h2>Sequenza centrale</h2></div><a href="#" data-franchise-show-release>Visualizza tutti →</a></header>
      <div class="franchise-main-games-list">
        ${mainGames.slice(0, 6).map((game) => {
          const progress = franchiseGameProgress(game);
          const percent = Math.max(0, Math.min(100, progress.status === "completed" ? 100 : progress.percent || 0));
          return `<a href="${escapeAttr(gameRoute(game))}" class="franchise-main-game-link">
            <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="" loading="lazy">
            <span><strong>${escapeHtml(game.title || "Titolo")}</strong><small>${escapeHtml(releaseYearOf(game) || game.release_year || "Anno n/d")}</small></span>
            <em>${escapeHtml(FRANCHISE_RELATION_LABELS[game.relation_type || "main"] || "Titolo")}</em>
            <i style="--rail-progress:${percent}%"></i>
          </a>`;
        }).join("") || `<p class="muted">Nessun gioco principale pubblicato.</p>`}
      </div>
    </section>

    <section class="franchise-rail-panel">
      <header><div><p class="eyebrow">COLLEZIONI EDITORIALI</p><h2>Raccolte correlate</h2></div></header>
      <div class="franchise-linked-collections">
        ${collections.length ? collections.map((collection) => `<a href="${escapeAttr(editorialCollectionRoute(collection.slug))}"><img src="${escapeAttr(collection.cover_image_url || PLACEHOLDER)}" alt="" loading="lazy"><span><strong>${escapeHtml(collection.title)}</strong><small>${Number(collection.game_count || 0).toLocaleString("it-IT")} giochi</small></span></a>`).join("") : `<p class="muted">Le collezioni editoriali collegate appariranno qui quando saranno pubblicate.</p>`}
      </div>
    </section>

    <section class="franchise-rail-panel franchise-start-guide">
      <header><div><p class="eyebrow">DA DOVE INIZIARE</p><h2>Guida rapida</h2></div></header>
      <a href="${escapeAttr(firstMain ? gameRoute(firstMain) : "#/franchises")}"><svg aria-hidden="true"><use href="#icon-star"></use></svg><span><small>Miglior punto di partenza</small><strong>${escapeHtml(firstMain?.title || "Scegli un titolo principale")}</strong></span></a>
      <button type="button" data-franchise-show-release><svg aria-hidden="true"><use href="#icon-calendar"></use></svg><span><small>Esperienza completa</small><strong>Ordine di uscita</strong></span></button>
      <button type="button" data-franchise-show-paths><svg aria-hidden="true"><use href="#icon-franchise"></use></svg><span><small>Percorso editoriale</small><strong>${escapeHtml(firstTrack?.name || "Percorsi narrativi")}</strong></span></button>
      <a href="${escapeAttr(modernStart ? gameRoute(modernStart) : "#/franchises")}"><svg aria-hidden="true"><use href="#icon-sparkles"></use></svg><span><small>Approccio moderno</small><strong>${escapeHtml(modernStart?.title || "Titolo recente")}</strong></span></a>
    </section>`;
  rail.querySelectorAll("img").forEach((image) => { image.onerror = () => { image.src = PLACEHOLDER; }; });
  rail.querySelectorAll("[data-franchise-show-release]").forEach((control) => {
    control.addEventListener("click", (event) => {
      event.preventDefault();
      state.franchiseOrder = "release";
      $$('[data-franchise-order]').forEach((item) => item.classList.toggle("is-active", item.dataset.franchiseOrder === "release"));
      renderFranchiseSections();
    });
  });
  rail.querySelectorAll("[data-franchise-show-paths]").forEach((control) => {
    control.addEventListener("click", () => {
      state.franchiseOrder = "paths";
      $$('[data-franchise-order]').forEach((item) => item.classList.toggle("is-active", item.dataset.franchiseOrder === "paths"));
      renderFranchiseSections();
    });
  });
  rail.hidden = false;
}

function renderFranchiseSections() {
  const gameMap = franchiseGameByKeyMap();
  const games = [...(state.franchiseData?.games || [])].sort((a, b) => {
    const order = franchiseOrderValue(a) - franchiseOrderValue(b);
    return order || String(a.title || "").localeCompare(String(b.title || ""), "it");
  });
  ui.franchiseSections.replaceChildren();
  if (!games.length) {
    ui.franchiseSections.innerHTML = `<div class="empty-state"><strong>Saga in preparazione</strong><span>I giochi verranno collegati dal pannello amministrativo.</span></div>`;
    return;
  }

  if (state.franchiseOrder === "paths") {
    const tracks = [...(state.franchiseData?.tracks || [])].sort((a, b) => Number(a.sort_order || 0) - Number(b.sort_order || 0)
      || String(a.name || "").localeCompare(String(b.name || ""), "it"));
    if (!tracks.length) {
      ui.franchiseSections.innerHTML = `<div class="empty-state"><strong>Percorsi non configurati</strong><span>Questa saga non ha ancora continuità, sottosaghe o archi narrativi.</span></div>`;
    } else {
      for (const track of tracks) ui.franchiseSections.append(renderFranchiseTrackSection(track, gameMap));
      const relationSection = renderFranchiseRelations(gameMap);
      if (relationSection) ui.franchiseSections.append(relationSection);
    }
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

function franchiseYearRange(games) {
  const years = (games || []).map(releaseYearOf).filter((year) => Number.isInteger(year) && year > 1900);
  if (!years.length) return "N/D";
  const first = Math.min(...years);
  const last = Math.max(...years);
  return first === last ? String(first) : `${first}–${last}`;
}

function renderFranchiseOverview(data) {
  if (!ui.franchiseOverview) return;
  const games = data?.games || [];
  const tracks = data?.tracks || [];
  const relations = data?.relations || [];
  const continuities = tracks.filter((track) => ["continuity", "timeline"].includes(track.track_type)).length;
  ui.franchiseOverview.innerHTML = `
    <article><span class="franchise-overview-icon"><svg aria-hidden="true"><use href="#icon-gamepad"></use></svg></span><div><strong>${games.length.toLocaleString("it-IT")}</strong><small>Titoli collegati</small></div></article>
    <article><span class="franchise-overview-icon"><svg aria-hidden="true"><use href="#icon-franchise"></use></svg></span><div><strong>${tracks.length.toLocaleString("it-IT")}</strong><small>Percorsi editoriali</small></div></article>
    <article><span class="franchise-overview-icon"><svg aria-hidden="true"><use href="#icon-chart"></use></svg></span><div><strong>${relations.length.toLocaleString("it-IT")}</strong><small>Relazioni mappate</small></div></article>
    <article><span class="franchise-overview-icon"><svg aria-hidden="true"><use href="#icon-clock"></use></svg></span><div><strong>${escapeHtml(franchiseYearRange(games))}</strong><small>${continuities ? `${continuities} continuità/timeline` : "Arco di pubblicazione"}</small></div></article>`;
  ui.franchiseOverview.hidden = false;
}

async function renderFranchisePage() {
  const requestId = ++state.editorialRequestId;
  const slug = state.route.params.slug;
  state.franchiseData = null;
  state.franchiseOrder = "paths";
  $$('[data-franchise-order]').forEach((button) => button.classList.toggle("is-active", button.dataset.franchiseOrder === "paths"));
  updateDocumentTitle("Caricamento franchise");
  ui.franchiseTitle.textContent = "Caricamento…";
  ui.franchiseDescription.textContent = "Recupero la cronologia della saga.";
  ui.franchiseMeta.replaceChildren();
  ui.franchiseStatus.hidden = true;
  ui.franchiseHero.classList.remove("uses-game-art");
  ui.franchiseHeroImage.onerror = null;
  ui.franchiseHeroImage.removeAttribute("src");
  ui.franchiseHeroImage.alt = "";
  ui.franchiseHeroImage.hidden = true;
  ui.franchiseSections.innerHTML = `<div class="route-loading">Caricamento saga…</div>`;
  ui.franchiseOverview.replaceChildren();
  ui.franchiseOverview.hidden = true;
  ui.franchiseProgress.hidden = true;
  const franchiseContextRail = document.getElementById("franchise-context-rail");
  if (franchiseContextRail) {
    franchiseContextRail.replaceChildren();
    franchiseContextRail.hidden = true;
  }
  const franchiseHeroActions = document.getElementById("franchise-hero-actions");
  if (franchiseHeroActions) franchiseHeroActions.replaceChildren();
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
    const trackCount = Number((data.tracks || []).length);
    const relationCount = Number((data.relations || []).length);
    const spinOffCount = (data.games || []).filter((game) => ["spin_off", "other"].includes(game.relation_type || "")).length;
    ui.franchiseMeta.innerHTML = `
      <span><svg aria-hidden="true"><use href="#icon-gamepad"></use></svg><b>${Number((data.games || []).length).toLocaleString("it-IT")}</b><small>Giochi totali</small></span>
      <span><svg aria-hidden="true"><use href="#icon-franchise"></use></svg><b>${trackCount || "—"}</b><small>Percorsi narrativi</small></span>
      <span><svg aria-hidden="true"><use href="#icon-sparkles"></use></svg><b>${spinOffCount}</b><small>Spin-off e diramazioni</small></span>
      <span><svg aria-hidden="true"><use href="#icon-calendar"></use></svg><b>${escapeHtml(franchiseYearRange(data.games || []))}</b><small>Anni coperti</small></span>`;
    if (franchiseHeroActions) {
      franchiseHeroActions.innerHTML = `
        <button class="button button-primary" type="button" data-franchise-follow><span>Segui franchise</span><svg aria-hidden="true"><use href="#icon-star"></use></svg></button>
        <button class="button button-secondary" type="button" data-franchise-share><span>Condividi</span><svg aria-hidden="true"><use href="#icon-external"></use></svg></button>
        <a class="button button-secondary" href="#/library"><span>Apri nella libreria</span><svg aria-hidden="true"><use href="#icon-library"></use></svg></a>`;
      franchiseHeroActions.querySelector("[data-franchise-share]")?.addEventListener("click", async () => {
        const shareUrl = `${location.origin}${location.pathname}${franchiseRoute(franchise.slug)}`;
        try {
          if (navigator.share) await navigator.share({ title: franchise.name, url: shareUrl });
          else await navigator.clipboard?.writeText(shareUrl);
        } catch (_) {}
      });
    }
    const fallbackHero = [...(data.games || [])]
      .sort((a, b) => Number(a.release_order || 100000) - Number(b.release_order || 100000))
      .find((game) => game.image_url)?.image_url || "";
    const heroImage = franchise.hero_image_url || fallbackHero;
    ui.franchiseHero.classList.toggle("uses-game-art", !franchise.hero_image_url && Boolean(heroImage));
    ui.franchiseHeroImage.hidden = !heroImage;
    if (heroImage) {
      ui.franchiseHeroImage.src = heroImage;
      ui.franchiseHeroImage.alt = franchise.name;
      ui.franchiseHeroImage.onerror = () => { ui.franchiseHeroImage.hidden = true; };
    }
    state.franchiseOrder = (data.tracks || []).length ? "paths" : "release";
    $$('[data-franchise-order]').forEach((button) => button.classList.toggle("is-active", button.dataset.franchiseOrder === state.franchiseOrder));
    renderFranchiseOverview(data);
    renderFranchiseProgress(data.games || []);
    renderFranchiseContextRail(data);
    renderFranchiseSections();
  } catch (error) {
    console.error("Franchise non disponibile", error);
    if (requestId !== state.editorialRequestId) return;
    updateDocumentTitle("Franchise non trovato");
    ui.franchiseTitle.textContent = "Franchise non disponibile";
    ui.franchiseDescription.textContent = "La saga richiesta non è pubblicata oppure la migrazione v4.6 non è stata applicata.";
    state.franchiseData = null;
    ui.franchiseStatus.textContent = error.message || "Franchise non disponibile.";
    ui.franchiseStatus.hidden = false;
    ui.franchiseHero.classList.remove("uses-game-art");
    ui.franchiseHeroImage.onerror = null;
    ui.franchiseHeroImage.removeAttribute("src");
    ui.franchiseHeroImage.alt = "";
    ui.franchiseHeroImage.hidden = true;
    ui.franchiseMeta.replaceChildren();
    ui.franchiseOverview.replaceChildren();
    ui.franchiseOverview.hidden = true;
    ui.franchiseProgress.hidden = true;
    const franchiseContextRail = document.getElementById("franchise-context-rail");
    if (franchiseContextRail) {
      franchiseContextRail.replaceChildren();
      franchiseContextRail.hidden = true;
    }
    const franchiseHeroActions = document.getElementById("franchise-hero-actions");
    if (franchiseHeroActions) franchiseHeroActions.replaceChildren();
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
    ui.editorialCollectionMeta.innerHTML = `<span>${Number((data.games || []).length).toLocaleString("it-IT")} giochi</span><span>Selezione ufficiale Ludograph</span>`;
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
  if (!window.VaultFranchises || getMode(game) !== "catalog") return;
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
  if (game && window.VaultCatalog?.configured() && !Object.prototype.hasOwnProperty.call(game, "media_count")) {
    try {
      const detailedGame = await window.VaultCatalog.getGame(state.route.params.key, { force: true });
      if (detailedGame) {
        game = detailedGame;
        registerCatalogGame(game);
      }
    } catch (error) {
      console.warn("Caricamento media della scheda fallito", error);
    }
  }

  if (!game || state.route.name !== "game") {
    updateDocumentTitle("Gioco non trovato");
    ui.gamePageTitle.textContent = "Gioco non trovato";
    ui.gamePageDescription.textContent = "Il titolo richiesto non è disponibile nel catalogo.";
    ui.gamePageImage.src = PLACEHOLDER;
    ui.gamePageMeta.replaceChildren();
    ui.gamePagePromotions.replaceChildren();
    if (ui.gameMediaPanel) ui.gameMediaPanel.hidden = true;
    if (ui.gameMediaNav) ui.gameMediaNav.hidden = true;
    ui.gameRelatedSection.hidden = true;
    return;
  }

  const entry = getLibraryEntry(game);
  const journalProgress = window.VaultJournal?.getProgress(gameKey(game)) || null;
  const journalEntries = window.VaultJournal?.listEntries({ gameKey: gameKey(game) }) || [];
  const sessionMinutes = journalEntries.reduce((sum, item) => sum + Number(item.minutesPlayed || 0), 0);
  const latestSession = journalEntries[0] || null;
  const progressPercent = Math.max(0, Math.min(100, Number(journalProgress?.progressPercent ?? entry?.progressPercent ?? (entry?.status === "completed" ? 100 : 0)) || 0));
  const progressStatus = journalProgress?.status || entry?.status || "saved";
  const primaryPlatform = journalProgress?.primaryPlatform || entry?.primaryPlatform || "";
  const aliases = new Set(reviewKeysForGame(game).map(String));
  const listCount = Object.values(state.lists || {}).filter((list) => (list.games || []).some((key) => aliases.has(String(key)))).length;
  updateDocumentTitle(game.title);
  ui.gamePageImage.src = game.image_url || PLACEHOLDER;
  ui.gamePageImage.alt = `Copertina di ${game.title}`;
  if (ui.gamePageBackdrop) {
    const backdrop = gameDetailArtwork(game);
    ui.gamePageBackdrop.style.backgroundImage = `url("${String(backdrop).replaceAll('"', '%22')}")`;
  }
  ui.gamePageImage.onerror = () => { ui.gamePageImage.src = PLACEHOLDER; };
  ui.gamePageBadge.textContent = badgeText(game);
  ui.gamePageTitle.textContent = game.title;
  const availableStores = [...new Set(commercialListingsForGame(game).map((listing) => listing.store).filter(Boolean))];
  const bylineParts = [];
  if (game.developer) {
    bylineParts.push(`<a href="${escapeAttr(entityRoute("developer", game.developer))}">${escapeHtml(game.developer)}</a>`);
  }
  if (game.publisher) {
    bylineParts.push(`<a href="${escapeAttr(entityRoute("publisher", game.publisher))}">${escapeHtml(game.publisher)}</a>`);
  }
  ui.gamePageByline.innerHTML = bylineParts.join(" · ")
    || escapeHtml(availableStores.map(storeLabel).join(" · "))
    || (game.source_kind === "master" ? "Scheda enciclopedica IGDB" : "Store non disponibile");
  ui.gamePageDescription.textContent = game.description || "Descrizione non disponibile.";
  const genreMarkup = (game.genres || []).slice(0, 5).map((genre) => `<span class="game-genre-chip">${escapeHtml(genre)}</span>`).join("");
  ui.gamePageMeta.innerHTML = [
    game.release_date ? `<span class="game-fact"><small>USCITA</small><b>${escapeHtml(formatDate(game.release_date))}</b></span>` : "",
    game.offer_type ? `<span class="game-fact"><small>TIPO</small><b>${escapeHtml(game.offer_type === "IGDB_MASTER" ? "Scheda enciclopedica" : game.offer_type)}</b></span>` : "",
    genreMarkup ? `<span class="game-genre-list">${genreMarkup}</span>` : "",
    game.platforms?.length ? `<span class="game-platform-meta"><small>PIATTAFORME</small><span class="platform-chip-list">${platformBadgesMarkup(game.platforms, { limit: 8 })}</span></span>` : "",
  ].filter(Boolean).join("");
  configureStoreAction(ui.gamePageStoreLink, game, { detail: true });
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
  const recordedMinutes = sessionMinutes || journalProgress?.manualPlaytimeMinutes || 0;
  ui.gamePageManualPlaytime.textContent = formatMinutes(recordedMinutes);
  if (ui.gameSummaryProgress) ui.gameSummaryProgress.textContent = `${progressPercent}%`;
  if (ui.gameSummaryProgressRing) ui.gameSummaryProgressRing.style.setProperty("--progress", `${progressPercent}%`);
  if (ui.gameSummaryProgressStatus) ui.gameSummaryProgressStatus.textContent = entry ? statusLabel(progressStatus) : "Non iniziato";
  if (ui.gameSummaryLastPlayed) ui.gameSummaryLastPlayed.textContent = latestSession ? relativeTime(latestSession.playedAt || latestSession.createdAt) : "Nessuna sessione";
  if (ui.gameSummarySessionCount) ui.gameSummarySessionCount.textContent = journalEntries.length.toLocaleString("it-IT");
  if (ui.gameSummaryHours) ui.gameSummaryHours.textContent = formatMinutes(recordedMinutes);
  if (ui.gameSummaryLatestNote) ui.gameSummaryLatestNote.textContent = latestSession?.note || (latestSession ? `Ultima sessione ${formatDate(latestSession.playedAt)}` : "Nessuna sessione registrata.");
  if (ui.gameSummaryStatus) ui.gameSummaryStatus.textContent = entry ? statusLabel(progressStatus) : "Non in libreria";
  if (ui.gameSummaryAdded) ui.gameSummaryAdded.textContent = entry?.addedAt ? formatDate(entry.addedAt) : "—";
  if (ui.gameSummaryPlatform) ui.gameSummaryPlatform.textContent = primaryPlatform || (game.platforms?.length === 1 ? game.platforms[0] : "Non indicata");
  if (ui.gameSummaryListCount) ui.gameSummaryListCount.textContent = listCount.toLocaleString("it-IT");
  updatePersonalGameRatingSummary(entry?.rating || 0);
  renderCommunityGameRating([], "Caricamento voti…");
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
  renderGameMedia(game);
  void renderRelatedGames(game);
  void renderGameEditorialMemberships(game);
  void renderGameSocial(game);
  ui.gamePage.querySelectorAll("[data-game-scroll]").forEach((control) => {
    control.onclick = () => {
      const target = document.getElementById(control.dataset.gameScroll || "");
      target?.scrollIntoView({ behavior: "smooth", block: "start" });
    };
  });

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
  const authorName = author.display_name || author.username || "Utente Ludograph";
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
    renderCommunityGameRating([], "Community non configurata");
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
    renderCommunityGameRating(reviews);

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
    renderCommunityGameRating([], "Voti temporaneamente non disponibili");
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
    ui.publicProfileMemberSince.textContent = `Su Ludograph dal ${formatDate(profile.created_at)}`;
    if (ui.publicProfileHeroBackdrop) {
      const publicArtwork = String(profile.hero_image_url || "").trim();
      ui.publicProfileHeroBackdrop.style.backgroundImage = publicArtwork ? `url("${publicArtwork.replaceAll('"', '%22')}")` : "";
      ui.publicProfileHeroBackdrop.classList.toggle("has-art", Boolean(publicArtwork));
    }

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

function updateAccountLevelLabel(snapshot = state.auth) {
  if (!ui.accountLevel) return;
  if (!snapshot?.configured) ui.accountLevel.textContent = "Configurazione richiesta";
  else if (!snapshot?.user) ui.accountLevel.textContent = "Profilo personale";
  else ui.accountLevel.textContent = snapshot.profile?.username ? `@${snapshot.profile.username}` : "Profilo personale";
}

function closeAccountMenu() {
  if (!ui.accountMenu || !ui.accountButton) return;
  ui.accountMenu.hidden = true;
  ui.accountButton.setAttribute("aria-expanded", "false");
}

function toggleAccountMenu() {
  if (!state.auth.user) {
    navigate("#/login");
    return;
  }
  if (!ui.accountMenu || !ui.accountButton) return;
  const opening = ui.accountMenu.hidden;
  ui.accountMenu.hidden = !opening;
  ui.accountButton.setAttribute("aria-expanded", opening ? "true" : "false");
  if (opening) ui.accountMenu.querySelector('a, button')?.focus({ preventScroll: true });
}

function updateAccountUI(snapshot) {
  const previousUserId = state.auth.user?.id || null;
  const nextUserId = snapshot.user?.id || null;
  const accountChanged = previousUserId !== nextUserId;
  state.auth = snapshot;
  closeAccountMenu();
  if (accountChanged || !state.admin.loaded) {
    state.admin.loaded = false;
    void refreshAdminContext();
  } else {
    updateAdminNavigation();
  }
  if (!snapshot.configured) {
    ui.accountLabel.textContent = "Configura account";
    ui.accountAvatar.textContent = "!";
    ui.accountAvatar.classList.remove("has-image");
    ui.accountAvatar.style.backgroundImage = "";
    ui.accountButton.setAttribute("aria-label", "Configura account");
    updateAccountLevelLabel(snapshot);
    ui.sidebarDataNote.textContent = "Account cloud non configurato.";
    void refreshNotificationCount();
    return;
  }
  if (!snapshot.user) {
    ui.accountLabel.textContent = "Accedi";
    ui.accountAvatar.textContent = "?";
    ui.accountAvatar.classList.remove("has-image");
    ui.accountAvatar.style.backgroundImage = "";
    ui.accountButton.setAttribute("aria-label", "Accedi");
    updateAccountLevelLabel(snapshot);
    ui.sidebarDataNote.textContent = "I dati personali sono salvati localmente.";
    void refreshNotificationCount();
    return;
  }
  ui.accountLabel.textContent = snapshot.profile?.display_name || snapshot.profile?.username || "Profilo";
  ui.accountButton.setAttribute("aria-label", `Apri account di ${ui.accountLabel.textContent}`);
  applyAvatar(ui.accountAvatar, snapshot.user, snapshot.profile);
  applyAvatar(ui.accountMenuAvatar, snapshot.user, snapshot.profile);
  if (ui.accountMenuName) ui.accountMenuName.textContent = ui.accountLabel.textContent;
  if (ui.accountMenuHandle) ui.accountMenuHandle.textContent = snapshot.profile?.username ? `@${snapshot.profile.username}` : (snapshot.user.email || "Account Ludograph");
  if (ui.accountMenuPublic) {
    ui.accountMenuPublic.hidden = !snapshot.profile?.username || snapshot.profile?.is_public === false;
    ui.accountMenuPublic.href = snapshot.profile?.username ? profileRoute(snapshot.profile.username) : "#/profile";
  }
  updateAccountLevelLabel(snapshot);
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


function setButtonLoading(button, loading, loadingLabel = "Caricamento…") {
  if (!button) return;
  if (loading) {
    if (!button.dataset.idleLabel) button.dataset.idleLabel = button.textContent.trim();
    button.disabled = true;
    button.classList.add("is-loading");
    button.setAttribute("aria-busy", "true");
    button.textContent = loadingLabel;
    return;
  }
  button.disabled = false;
  button.classList.remove("is-loading");
  button.removeAttribute("aria-busy");
  if (button.dataset.idleLabel) button.textContent = button.dataset.idleLabel;
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

function setAdminFranchiseJsonMessage(message, success = false) {
  if (!ui.adminFranchiseJsonMessage) return;
  ui.adminFranchiseJsonMessage.textContent = message || "";
  ui.adminFranchiseJsonMessage.classList.toggle("auth-success", Boolean(success));
  ui.adminFranchiseJsonMessage.hidden = !message;
}

function franchiseEditorialFilename(franchise, suffix = "editorial") {
  return `${editorialSlug(franchise?.slug || franchise?.name || "franchise")}-${suffix}.json`;
}

function downloadJson(filename, payload) {
  const blob = new Blob([`${JSON.stringify(payload, null, 2)}
`], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function buildFranchiseEditorialPrompt(payload) {
  return `Analizza il franchise contenuto nel JSON allegato.

Compila esclusivamente i campi editoriali senza modificare franchise.id, games.game_key, games.game_id e games.title.

Organizza:
- ordine di uscita;
- continuità e linee temporali alternative;
- sottosaghe e archi narrativi;
- canonicità;
- remake, remaster, reinterpretazioni, raccolte e relazioni tra giochi.

Restituisci esclusivamente un JSON valido conforme a tfv-franchise-editorial-v2.

JSON:
${JSON.stringify(payload, null, 2)}`;
}

function parseAdminFranchiseEditorialJson() {
  const raw = ui.adminFranchiseJsonImport?.value?.trim() || "";
  if (!raw) throw new Error("Incolla prima un JSON editoriale.");
  const payload = JSON.parse(raw);
  if (payload?.schema_version !== "tfv-franchise-editorial-v2") {
    throw new Error("schema_version non valida. Serve tfv-franchise-editorial-v2.");
  }
  return payload;
}

async function fetchAdminFranchiseEditorialExport(button) {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise) throw new Error("Apri prima un franchise.");
  if (button) setButtonLoading(button, true, "Preparazione…");
  try {
    return await window.VaultFranchises.exportAdminFranchiseEditorial(franchise.id);
  } finally {
    if (button) setButtonLoading(button, false);
  }
}

function describeFranchiseImportResult(result) {
  const counts = result?.counts || {};
  return `${result?.status === "applied" ? "Import applicato" : "JSON valido"}: ${Number(counts.games || 0)} giochi, ${Number(counts.tracks || 0)} percorsi, ${Number(counts.track_memberships || 0)} assegnazioni, ${Number(counts.relations || 0)} relazioni.`;
}

function nextFranchiseOrder(field = "release_order") {
  const games = state.admin.selectedFranchise?.games || [];
  return games.reduce((max, game) => Math.max(max, Number(game?.[field] || 0)), 0) + 1;
}

function franchiseSelectionHas(key) {
  return (state.admin.franchiseGameSelection || []).some((item) => gameKey(item) === key);
}

function franchiseSelectionHasIdentity(identity) {
  return (state.admin.franchiseGameSelection || [])
    .some((item) => editorialIdentityForGame(item) === identity);
}

function currentFranchiseGameKeys() {
  return new Set((state.admin.selectedFranchise?.games || []).map((game) => gameKey(game)));
}

function currentFranchiseEditorialIdentities() {
  return new Set((state.admin.selectedFranchise?.games || []).map(editorialIdentityForGame));
}

function prepareAdminFranchiseBatchMode() {
  if (!ui.adminFranchiseGameKey.value) return;
  ui.adminFranchiseGameForm.reset();
  ui.adminFranchiseGameKey.value = "";
  ui.adminFranchiseReleaseOrder.value = String(nextFranchiseOrder("release_order"));
}

function setAdminFranchiseGameSelection(game, selected) {
  const key = gameKey(game);
  const identity = editorialIdentityForGame(game);
  if (!key || currentFranchiseGameKeys().has(key) || currentFranchiseEditorialIdentities().has(identity)) return;
  const items = [...(state.admin.franchiseGameSelection || [])];
  const index = items.findIndex((item) => editorialIdentityForGame(item) === identity);
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
      <div><strong>${escapeHtml(game.title || "Gioco")}</strong><small>${escapeHtml(gameDisambiguationMarkup(game, { includeDeveloper: false }))}${Number(game.variant_count || 1) > 1 ? ` · ${Number(game.variant_count)} versioni unite` : ""}</small></div>
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
  ui.adminFranchiseGameSearchResults?.querySelectorAll("[data-franchise-identity]").forEach((row) => {
    const identity = row.dataset.franchiseIdentity;
    const checkbox = row.querySelector('input[type="checkbox"]');
    const selected = franchiseSelectionHasIdentity(identity);
    row.classList.toggle("is-selected", selected);
    if (checkbox) checkbox.checked = selected;
    const label = row.querySelector("[data-selection-label]");
    if (label) label.textContent = checkbox?.disabled ? "Già presente" : selected ? "Selezionato" : "Seleziona";
  });
}

function updateAdminFranchiseSearchActions() {
  const results = state.admin.franchiseSearchResults || [];
  const existing = currentFranchiseEditorialIdentities();
  const available = results.filter((game) => !existing.has(editorialIdentityForGame(game)));
  const selectedHere = available.filter((game) => franchiseSelectionHasIdentity(editorialIdentityForGame(game))).length;
  if (ui.adminFranchiseSearchActions) ui.adminFranchiseSearchActions.hidden = available.length === 0;
  if (ui.adminFranchiseSelectAll) {
    ui.adminFranchiseSelectAll.disabled = !available.length || selectedHere === available.length;
    ui.adminFranchiseSelectAll.textContent = `Seleziona opere canoniche (${available.length})`;
  }
  if (ui.adminFranchiseDeselectResults) {
    ui.adminFranchiseDeselectResults.disabled = selectedHere === 0;
    ui.adminFranchiseDeselectResults.textContent = `Deseleziona opere visibili (${selectedHere})`;
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
  state.admin.franchiseEditorRows = [];
  state.admin.franchiseEditorSelected = new Set();
  state.admin.franchiseEditorDirty = new Set();
  if (ui.adminFranchiseMassEditor) ui.adminFranchiseMassEditor.hidden = true;
  if (ui.adminFranchiseJsonImport) ui.adminFranchiseJsonImport.value = "";
  setAdminFranchiseJsonMessage("");
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

function franchiseEditorRowFromGame(game) {
  return {
    gameKey: gameKey(game),
    title: game.title || "Senza titolo",
    imageUrl: game.image_url || PLACEHOLDER,
    releaseDate: game.release_date || null,
    releaseYear: Number(game.release_year || releaseYearOf(game) || 0) || null,
    platforms: Array.isArray(game.platforms) ? game.platforms : [],
    relationType: game.relation_type || "main",
    releaseOrder: Number(game.release_order || 0),
    narrativeOrder: game.narrative_order === null || game.narrative_order === undefined
      ? null
      : Number(game.narrative_order),
    note: game.franchise_note || game.note || "",
  };
}

function syncFranchiseEditorRows(data = state.admin.selectedFranchise) {
  state.admin.franchiseEditorRows = (data?.games || [])
    .map(franchiseEditorRowFromGame)
    .sort((a, b) => a.releaseOrder - b.releaseOrder || a.title.localeCompare(b.title, "it"));
  state.admin.franchiseEditorSelected = new Set();
  state.admin.franchiseEditorDirty = new Set();
  state.admin.franchiseEditorDragKey = null;
}

function franchiseEditorPayload(row) {
  return {
    gameKey: row.gameKey,
    relationType: row.relationType || "main",
    releaseOrder: Number(row.releaseOrder || 0),
    narrativeOrder: row.narrativeOrder === null || row.narrativeOrder === "" ? null : Number(row.narrativeOrder),
    note: row.note || null,
  };
}

function franchiseEditorTargets() {
  const selected = state.admin.franchiseEditorSelected;
  const rows = state.admin.franchiseEditorRows || [];
  return selected?.size ? rows.filter((row) => selected.has(row.gameKey)) : rows;
}

function markFranchiseEditorDirty(gameKeyValue) {
  state.admin.franchiseEditorDirty.add(gameKeyValue);
  updateFranchiseEditorToolbar();
}

function updateFranchiseEditorToolbar() {
  const rows = state.admin.franchiseEditorRows || [];
  const selected = state.admin.franchiseEditorSelected || new Set();
  const dirty = state.admin.franchiseEditorDirty || new Set();
  const selectedCount = selected.size;

  if (ui.adminFranchiseMassEditor) ui.adminFranchiseMassEditor.hidden = !state.admin.selectedFranchise?.franchise;
  if (ui.adminFranchiseEditorSelectionCount) {
    ui.adminFranchiseEditorSelectionCount.textContent = `${selectedCount} ${selectedCount === 1 ? "selezionato" : "selezionati"}`;
  }
  if (ui.adminFranchiseEditorSelectAll) {
    ui.adminFranchiseEditorSelectAll.checked = rows.length > 0 && selectedCount === rows.length;
    ui.adminFranchiseEditorSelectAll.indeterminate = selectedCount > 0 && selectedCount < rows.length;
  }
  if (ui.adminFranchiseEditorStatus) {
    ui.adminFranchiseEditorStatus.textContent = dirty.size
      ? `${dirty.size} ${dirty.size === 1 ? "gioco modificato" : "giochi modificati"} non salvati.`
      : `${rows.length} ${rows.length === 1 ? "gioco nella saga" : "giochi nella saga"} · nessuna modifica non salvata.`;
    ui.adminFranchiseEditorStatus.classList.toggle("has-unsaved-changes", dirty.size > 0);
  }
  if (ui.adminFranchiseSaveSelected) ui.adminFranchiseSaveSelected.disabled = selectedCount === 0;
  if (ui.adminFranchiseSaveAll) ui.adminFranchiseSaveAll.disabled = rows.length === 0 || dirty.size === 0;
  if (ui.adminFranchiseRemoveSelected) ui.adminFranchiseRemoveSelected.disabled = selectedCount === 0;
}

function updateFranchiseEditorRow(gameKeyValue, patch = {}) {
  const row = (state.admin.franchiseEditorRows || []).find((item) => item.gameKey === gameKeyValue);
  if (!row) return;
  Object.assign(row, patch);
  markFranchiseEditorDirty(gameKeyValue);
}

function moveFranchiseEditorRow(gameKeyValue, delta) {
  const rows = state.admin.franchiseEditorRows || [];
  const index = rows.findIndex((row) => row.gameKey === gameKeyValue);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= rows.length) return;
  [rows[index], rows[target]] = [rows[target], rows[index]];
  rows.forEach((row, rowIndex) => {
    row.releaseOrder = rowIndex + 1;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  });
  renderAdminFranchiseGames();
}

function reorderFranchiseEditorRows(dragKey, targetKey) {
  if (!dragKey || !targetKey || dragKey === targetKey) return;
  const rows = state.admin.franchiseEditorRows || [];
  const from = rows.findIndex((row) => row.gameKey === dragKey);
  const to = rows.findIndex((row) => row.gameKey === targetKey);
  if (from < 0 || to < 0) return;
  const [moved] = rows.splice(from, 1);
  rows.splice(to, 0, moved);
  rows.forEach((row, index) => {
    row.releaseOrder = index + 1;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  });
  renderAdminFranchiseGames();
}

function renderAdminFranchiseGames() {
  const franchise = state.admin.selectedFranchise?.franchise;
  const rows = state.admin.franchiseEditorRows || [];
  ui.adminFranchiseGames.replaceChildren();
  if (!franchise) {
    if (ui.adminFranchiseMassEditor) ui.adminFranchiseMassEditor.hidden = true;
    return;
  }

  ui.adminFranchiseOpen.href = franchiseRoute(franchise.slug);
  if (ui.adminFranchiseMassEditor) ui.adminFranchiseMassEditor.hidden = false;

  if (!rows.length) {
    ui.adminFranchiseGames.innerHTML = `<div class="timeline-empty">Nessun gioco collegato. Usa la ricerca qui sopra per aggiungere i primi titoli.</div>`;
    updateFranchiseEditorToolbar();
    return;
  }

  const header = document.createElement("div");
  header.className = "franchise-editor-row franchise-editor-header";
  header.setAttribute("role", "row");
  header.innerHTML = `
    <span aria-hidden="true"></span>
    <span>Gioco</span>
    <span>Tipo</span>
    <span>Ordine uscita</span>
    <span>Ordine narrativo</span>
    <span>Nota</span>
    <span>Azioni</span>`;
  ui.adminFranchiseGames.append(header);

  rows.forEach((row, index) => {
    const selected = state.admin.franchiseEditorSelected.has(row.gameKey);
    const dirty = state.admin.franchiseEditorDirty.has(row.gameKey);
    const item = document.createElement("article");
    item.className = "franchise-editor-row";
    item.classList.toggle("is-selected", selected);
    item.classList.toggle("is-dirty", dirty);
    item.dataset.gameKey = row.gameKey;
    item.draggable = true;
    item.setAttribute("role", "row");
    item.innerHTML = `
      <label class="franchise-row-check" title="Seleziona ${escapeAttr(row.title)}">
        <input type="checkbox" data-row-select ${selected ? "checked" : ""}>
      </label>
      <div class="franchise-row-game">
        <img src="${escapeAttr(row.imageUrl || PLACEHOLDER)}" alt="">
        <span><strong>${escapeHtml(row.title)}</strong><small>${escapeHtml([
          row.releaseYear || null,
          row.platforms?.slice(0, 3).join(" · ") || null,
        ].filter(Boolean).join(" · ") || "Dati enciclopedici")}</small></span>
      </div>
      <label class="franchise-row-field"><span>Tipo</span>
        <select data-row-type>
          ${Object.entries(FRANCHISE_RELATION_LABELS).map(([value, label]) => `<option value="${escapeAttr(value)}" ${row.relationType === value ? "selected" : ""}>${escapeHtml(label)}</option>`).join("")}
        </select>
      </label>
      <label class="franchise-row-field"><span>Uscita</span><input data-row-release type="number" min="1" value="${Number(row.releaseOrder || index + 1)}"></label>
      <label class="franchise-row-field"><span>Narrativa</span><input data-row-narrative type="number" min="1" value="${row.narrativeOrder ?? ""}" placeholder="—"></label>
      <label class="franchise-row-field franchise-row-note"><span>Nota</span><textarea data-row-note rows="2" maxlength="1000" placeholder="Facoltativa">${escapeHtml(row.note || "")}</textarea></label>
      <div class="franchise-row-actions">
        <button class="icon-button compact" data-row-up type="button" title="Sposta su" aria-label="Sposta ${escapeAttr(row.title)} su">↑</button>
        <button class="icon-button compact" data-row-down type="button" title="Sposta giù" aria-label="Sposta ${escapeAttr(row.title)} giù">↓</button>
        <button class="icon-button compact danger" data-row-remove type="button" title="Rimuovi" aria-label="Rimuovi ${escapeAttr(row.title)}">×</button>
      </div>`;

    item.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
    item.querySelector("[data-row-select]").onchange = (event) => {
      if (event.currentTarget.checked) state.admin.franchiseEditorSelected.add(row.gameKey);
      else state.admin.franchiseEditorSelected.delete(row.gameKey);
      item.classList.toggle("is-selected", event.currentTarget.checked);
      updateFranchiseEditorToolbar();
    };
    item.querySelector("[data-row-type]").onchange = (event) => {
      updateFranchiseEditorRow(row.gameKey, { relationType: event.currentTarget.value });
      item.classList.add("is-dirty");
    };
    item.querySelector("[data-row-release]").oninput = (event) => {
      updateFranchiseEditorRow(row.gameKey, { releaseOrder: Number(event.currentTarget.value || 0) });
      item.classList.add("is-dirty");
    };
    item.querySelector("[data-row-narrative]").oninput = (event) => {
      updateFranchiseEditorRow(row.gameKey, { narrativeOrder: event.currentTarget.value === "" ? null : Number(event.currentTarget.value) });
      item.classList.add("is-dirty");
    };
    item.querySelector("[data-row-note]").oninput = (event) => {
      updateFranchiseEditorRow(row.gameKey, { note: event.currentTarget.value });
      item.classList.add("is-dirty");
    };
    item.querySelector("[data-row-up]").onclick = () => moveFranchiseEditorRow(row.gameKey, -1);
    item.querySelector("[data-row-down]").onclick = () => moveFranchiseEditorRow(row.gameKey, 1);
    item.querySelector("[data-row-remove]").onclick = async () => {
      if (!confirm(`Rimuovere ${row.title} dal franchise?`)) return;
      try {
        const data = await window.VaultFranchises.removeAdminFranchiseGame(franchise.id, row.gameKey);
        state.admin.selectedFranchise = data;
        syncFranchiseEditorRows(data);
        renderAdminFranchiseGames();
        await loadAdminEditorial({ preserveSelection: false });
        showToast("Gioco rimosso dal franchise.");
      } catch (error) {
        showToast(error.message || "Rimozione fallita.");
      }
    };
    item.ondragstart = () => {
      state.admin.franchiseEditorDragKey = row.gameKey;
      item.classList.add("is-dragging");
    };
    item.ondragend = () => {
      state.admin.franchiseEditorDragKey = null;
      item.classList.remove("is-dragging");
    };
    item.ondragover = (event) => {
      event.preventDefault();
      item.classList.add("is-drag-target");
    };
    item.ondragleave = () => item.classList.remove("is-drag-target");
    item.ondrop = (event) => {
      event.preventDefault();
      item.classList.remove("is-drag-target");
      reorderFranchiseEditorRows(state.admin.franchiseEditorDragKey, row.gameKey);
    };
    ui.adminFranchiseGames.append(item);
  });

  updateFranchiseEditorToolbar();
}

async function saveFranchiseEditorRows(rows, button, successMessage) {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise || !rows.length) return;
  const invalid = rows.find((row) => Number(row.releaseOrder || 0) <= 0
    || (row.narrativeOrder !== null && Number(row.narrativeOrder || 0) <= 0));
  if (invalid) {
    showToast(`Controlla gli ordini di ${invalid.title}.`);
    return;
  }

  setButtonLoading(button, true, "Salvataggio…");
  try {
    const data = await window.VaultFranchises.saveAdminFranchiseGames(
      franchise.id,
      rows.map(franchiseEditorPayload),
    );
    state.admin.selectedFranchise = data;
    syncFranchiseEditorRows(data);
    renderAdminFranchiseGames();
    await loadAdminEditorial({ preserveSelection: false });
    showToast(successMessage);
  } catch (error) {
    showToast(error.message || "Salvataggio massivo fallito.");
  } finally {
    setButtonLoading(button, false);
  }
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
    if (ui.adminFranchiseJsonImport) ui.adminFranchiseJsonImport.value = "";
    setAdminFranchiseJsonMessage("");
    setAdminEditorialMessage(ui.adminFranchiseMessage, "");
    syncFranchiseEditorRows(data);
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
  const existingFranchiseIdentities = currentFranchiseEditorialIdentities();
  const franchiseGroups = kind === "franchise"
    ? normalizeAdminFranchiseCandidateGroups(games)
    : games;
  if (kind === "franchise") state.admin.franchiseSearchResults = franchiseGroups;

  for (const game of franchiseGroups) {
    const key = gameKey(game);
    if (kind === "franchise") {
      const identity = editorialIdentityForGame(game);
      const variants = Array.isArray(game.variants) && game.variants.length ? game.variants : [game];
      const variantKeys = new Set([
        ...(Array.isArray(game.variant_keys) ? game.variant_keys : []),
        ...variants.map((item) => gameKey(item)),
      ].filter(Boolean));
      const alreadyLinked = existingFranchiseIdentities.has(identity)
        || [...variantKeys].some((variantKey) => existingFranchiseKeys.has(variantKey));
      const variantCount = Math.max(Number(game.variant_count || 0), variants.length, 1);

      const group = document.createElement("article");
      group.className = "admin-result-group";

      const row = document.createElement("label");
      row.className = "admin-result-item admin-result-check admin-result-group-main";
      row.dataset.franchiseIdentity = identity;
      row.innerHTML = `
        <input class="admin-result-checkbox" type="checkbox" ${alreadyLinked ? "disabled" : ""}>
        <img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt="">
        <span class="admin-result-copy">
          <strong>${escapeHtml(game.title)}</strong>
          <small>${escapeHtml(gameDisambiguationMarkup(game))}</small>
          <span class="platform-chip-list admin-result-platforms">${platformBadgesMarkup(game.platforms, { limit: 4, compact: true })}</span>
          ${variantCount > 1 ? `<small class="admin-result-variant-summary">${variantCount} varianti catalogo unite in un’opera canonica</small>` : ""}
        </span>
        <b data-selection-label>${alreadyLinked ? "Già presente" : "Seleziona"}</b>`;
      row.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
      const checkbox = row.querySelector(".admin-result-checkbox");
      checkbox.checked = franchiseSelectionHasIdentity(identity);
      row.classList.toggle("is-selected", checkbox.checked);
      checkbox.addEventListener("change", () => {
        setAdminFranchiseGameSelection(game, checkbox.checked);
        updateAdminFranchiseSelectionUI();
      });
      group.append(row);

      if (variantCount > 1) {
        const toggle = document.createElement("button");
        toggle.type = "button";
        toggle.className = "admin-variant-toggle";
        toggle.setAttribute("aria-expanded", "false");
        toggle.innerHTML = `<span>Mostra ${variantCount} varianti</span><b aria-hidden="true">⌄</b>`;

        const details = document.createElement("div");
        details.className = "admin-variant-list";
        details.hidden = true;
        for (const variant of variants) {
          const item = document.createElement("div");
          item.className = "admin-variant-item";
          item.innerHTML = `
            <img src="${escapeAttr(variant.image_url || PLACEHOLDER)}" alt="">
            <span><strong>${escapeHtml(variant.title || game.title)}</strong><small>${escapeHtml(gameDisambiguationMarkup(variant))}</small></span>
            <code>${escapeHtml(variant.match_key || variant.canonical_id || "")}</code>`;
          item.querySelector("img").onerror = (event) => { event.currentTarget.src = PLACEHOLDER; };
          details.append(item);
        }
        toggle.onclick = () => {
          const expanded = toggle.getAttribute("aria-expanded") === "true";
          toggle.setAttribute("aria-expanded", String(!expanded));
          toggle.querySelector("span").textContent = expanded
            ? `Mostra ${variantCount} varianti`
            : `Nascondi ${variantCount} varianti`;
          details.hidden = expanded;
        };
        group.append(toggle, details);
      }

      container.append(group);
      continue;
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "admin-result-item";
    button.innerHTML = `<img src="${escapeAttr(game.image_url || PLACEHOLDER)}" alt"><span><strong>${escapeHtml(game.title)}</strong><small>${escapeHtml(gameDisambiguationMarkup(game))}</small></span><b>Seleziona</b>`;
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
    if (kind === "franchise" && window.VaultFranchises?.searchAdminFranchiseCandidates) {
      const groups = await window.VaultFranchises.searchAdminFranchiseCandidates(query, 50);
      renderAdminEditorialSearchResults(container, Array.isArray(groups) ? groups : [], kind);
    } else {
      const result = await window.VaultCatalog.search({ query, limit: kind === "franchise" ? 100 : 12, offset: 0, force: true });
      renderAdminEditorialSearchResults(container, Array.isArray(result?.items) ? result.items : [], kind);
    }
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
    const limit = 40 * 1024 * 1024 * 1024;
    const ratio = Math.min(100, Math.round((Number(status.database_size_bytes || 0) / limit) * 100));
    const stats = [
      ["Database", `${formatBytes(status.database_size_bytes)} · ${ratio}% della soglia operativa 40 GiB`],
      ["Catalogo", formatBytes(status.catalog_size_bytes)],
      ["Database Master", formatBytes(status.master_size_bytes)],
      ["Giochi nel catalogo", Number(status.catalog_games || 0).toLocaleString("it-IT")],
      ["Schede Master", Number(status.master_games || 0).toLocaleString("it-IT")],
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
    for (const sync of status.master_sync || []) {
      const card = document.createElement("article");
      card.className = "admin-sync-card";
      const provider = String(sync.provider || "Master").toUpperCase();
      const completedLabel = sync.status === "completed"
        ? (sync.completed_at ? formatDate(sync.completed_at, true) : "completato")
        : `cursor ${Number(sync.cursor_id || 0).toLocaleString("it-IT")}`;
      card.innerHTML = `<div><strong>${escapeHtml(provider)} · ENCICLOPEDIA</strong><span>${escapeHtml(sync.status || "unknown")}</span></div><small>${Number(sync.imported_count || 0).toLocaleString("it-IT")} schede elaborate · ${escapeHtml(completedLabel)}</small>${sync.error_message ? `<p>${escapeHtml(sync.error_message)}</p>` : ""}`;
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
  const callbackErrorCode = state.route.query.get("error_code") || state.route.query.get("error") || "";
  const callbackErrorDescription = state.route.query.get("error_description") || "";
  const callbackFlow = state.route.query.get("auth_flow") || "";
  const hasCallbackError = mode === "auth-callback" && Boolean(callbackErrorCode || callbackErrorDescription);
  const isCallbackSuccess = !hasCallbackError && (
    mode === "auth-callback" || state.route.query.get("confirmed") === "1"
  );
  const isCallback = hasCallbackError || isCallbackSuccess;
  const isExpiredCallback = callbackErrorCode === "otp_expired";

  const titles = {
    register: "Registrati",
    "forgot-password": "Recupera password",
    "reset-password": "Nuova password",
  };
  updateDocumentTitle(hasCallbackError ? "Link non valido" : (titles[mode] || "Accedi"));
  ui.authConfigWarning.hidden = Boolean(window.VaultAuth?.configured);
  ui.loginForm.hidden = isRegister || isForgot || isReset || isCallback;
  ui.registerForm.hidden = !isRegister || isCallback;
  ui.forgotPasswordForm.hidden = !isForgot;
  ui.recoveryCodeForm.hidden = !isForgot;
  ui.resetPasswordForm.hidden = !isReset;
  ui.authConfirmation.hidden = !isCallbackSuccess;
  ui.authCallbackError.hidden = !hasCallbackError;

  if (hasCallbackError) {
    const recoveryLikely = callbackFlow === "recovery" || isExpiredCallback;
    const title = isExpiredCallback
      ? "Link scaduto o già utilizzato"
      : "Impossibile completare l’operazione";
    const fallbackMessage = isExpiredCallback
      ? "Il collegamento è monouso e non è più valido. Richiedi un nuovo codice e usa soltanto l’ultima email ricevuta."
      : "Il collegamento di autenticazione non è valido. Riprova partendo dalla pagina di accesso.";

    ui.authEyebrow.textContent = "LINK NON VALIDO";
    ui.authTitle.textContent = title;
    ui.authSubtitle.textContent = fallbackMessage;
    ui.authCallbackErrorTitle.textContent = title;
    ui.authCallbackErrorMessage.textContent = isExpiredCallback
      ? fallbackMessage
      : (callbackErrorDescription || fallbackMessage);
    ui.authCallbackErrorAction.href = recoveryLikely ? "#/forgot-password" : "#/login";
    ui.authCallbackErrorAction.textContent = recoveryLikely ? "Richiedi un nuovo codice" : "Torna all’accesso";
  } else {
    ui.authEyebrow.textContent = isCallbackSuccess ? "EMAIL CONFERMATA" : "ACCOUNT LUDOGRAPH";
    ui.authTitle.textContent = isCallbackSuccess
      ? "Account attivato"
      : isRegister
        ? "Crea il tuo account"
        : isForgot
          ? "Recupera la password"
          : isReset
            ? "Scegli una nuova password"
            : "Bentornato";
    ui.authSubtitle.textContent = isCallbackSuccess
      ? "La conferma è andata a buon fine."
      : isRegister
        ? "Servono solo username, email e password. Il resto si completa dal profilo."
        : isForgot
          ? "Riceverai un codice monouso di 6 cifre, da inserire qui insieme alla tua email."
          : isReset
            ? "Inserisci una password nuova di almeno otto caratteri."
            : "Accedi con email e password per sincronizzare il tuo archivio.";
  }

  if (isForgot) {
    const rememberedEmail = window.sessionStorage.getItem("tfv:recovery-email") || "";
    if (!ui.forgotPasswordEmail.value && rememberedEmail) {
      ui.forgotPasswordEmail.value = rememberedEmail;
    }
    if (!ui.recoveryCodeEmail.value && rememberedEmail) {
      ui.recoveryCodeEmail.value = rememberedEmail;
    }
  }

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

function profileStreakDays(entries = []) {
  const days = new Set(entries.map((entry) => homeLocalDateKey(entry.playedAt || entry.createdAt)).filter(Boolean));
  if (!days.size) return 0;
  const cursor = new Date();
  cursor.setHours(12, 0, 0, 0);
  if (!days.has(homeLocalDateKey(cursor))) cursor.setDate(cursor.getDate() - 1);
  let streak = 0;
  while (days.has(homeLocalDateKey(cursor))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

function profileStats() {
  const entries = libraryEntryRecords();
  const journalEntries = window.VaultJournal?.listEntries() || [];
  const journal = window.VaultJournal?.summarize() || { sessionMinutes: 0, sessions: 0 };
  const completed = entries.filter((entry) => entry.status === "completed").length;
  const played = entries.filter((entry) => ["playing", "paused", "completed", "abandoned", "replay"].includes(entry.status)).length;
  const favorites = entries.filter((entry) => entry.favorite).length;
  const ratings = entries.map((entry) => Number(entry.rating || 0)).filter((rating) => rating > 0);
  const averageRating = ratings.length ? ratings.reduce((sum, rating) => sum + rating, 0) / ratings.length : 0;
  const sessionMinutes = Math.max(0, Number(journal.totalMinutes ?? journal.sessionMinutes ?? 0));
  return {
    library: entries.length,
    completed,
    favorites,
    lists: Object.keys(state.lists).length,
    hours: formatMinutes(sessionMinutes),
    minutes: sessionMinutes,
    sessions: Number(journal.sessions || journalEntries.length || 0),
    streak: profileStreakDays(journalEntries),
    averageRating,
    ratings: ratings.length,
    played,
    playedPercent: entries.length ? Math.round((played / entries.length) * 100) : 0,
    journalEntries,
  };
}

function profileActivityStatus(entry, type) {
  const progress = entry ? entryProgress(entry) : 0;
  if (type === "completed" || entry?.status === "completed") {
    return `<span class="profile-activity-result is-complete"><svg aria-hidden="true"><use href="#icon-trophy"></use></svg><b>100%</b></span>`;
  }
  if (type === "favorite") {
    return `<span class="profile-activity-result is-favorite"><svg aria-hidden="true"><use href="#icon-heart"></use></svg></span>`;
  }
  if (progress > 0) {
    return `<span class="profile-activity-result is-progress"><i><b style="width:${progress}%"></b></i><em>${progress}%</em></span>`;
  }
  return `<span class="profile-activity-result"><svg aria-hidden="true"><use href="#icon-chevron-right"></use></svg></span>`;
}

function renderProfileRecentGames() {
  ui.profileRecentGames.replaceChildren();
  const entries = libraryEntryRecords();
  const diaryEntries = window.VaultJournal?.listEntries({ limit: 12 }) || [];
  const activities = buildHomeActivity(entries, diaryEntries).slice(0, 4);
  if (!activities.length) {
    ui.profileRecentGames.innerHTML = `<div class="timeline-empty">La tua attività comparirà qui quando aggiungerai un gioco o registrerai una sessione.</div>`;
    return;
  }
  const entriesByKey = new Map(entries.map((entry) => [gameKey(entry.game), entry]));
  for (const activity of activities) {
    const game = activity.gameKey ? (resolveGameByKey(activity.gameKey) || journalGame(activity)) : journalGame(activity);
    const entry = entriesByKey.get(gameKey(game));
    const link = document.createElement("a");
    link.className = `profile-activity-row is-${activity.type || "library"}`;
    link.href = gameRoute(game);
    link.innerHTML = `
      <img src="${escapeAttr(activity.gameImageUrl || game.image_url || PLACEHOLDER)}" alt="">
      <span class="profile-activity-copy"><small>${escapeHtml(activity.detail || "Ha aggiornato la libreria")}</small><strong>${escapeHtml(activity.gameTitle || game.title || "Gioco")}</strong><time>${escapeHtml(relativeTime(activity.timestamp))}</time></span>
      ${profileActivityStatus(entry, activity.type)}`;
    ui.profileRecentGames.append(link);
  }
}

function profileGenreIconId(genre) {
  const value = String(genre || "").toLocaleLowerCase("it");
  if (/azione|action|avventura|adventure/.test(value)) return "genre-action";
  if (/gdr|rpg|role/.test(value)) return "genre-rpg";
  if (/open world|mondo aperto/.test(value)) return "genre-open";
  if (/souls|dark fantasy|horror/.test(value)) return "genre-souls";
  if (/strateg|tattic|simul/.test(value)) return "genre-strategy";
  return "genre-other";
}

function renderProfileGenres() {
  if (!ui.profileFavoriteGenres) return;
  const counts = new Map();
  for (const entry of Object.values(state.library)) {
    for (const genre of entry?.game?.genres || []) {
      const label = String(genre || "").trim();
      if (label) counts.set(label, (counts.get(label) || 0) + 1);
    }
  }
  let values = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6);
  if (!values.length) values = [["Azione / Avventura", 0], ["GDR", 0], ["Open World", 0], ["Strategia", 0], ["Indie", 0], ["Altro", 0]];
  const total = Math.max(1, values.reduce((sum, [, count]) => sum + count, 0));
  const percentages = values.map(([, count]) => count ? Math.max(4, Math.round((count / total) * 100)) : 0);
  ui.profileFavoriteGenres.innerHTML = values.map(([genre], index) => {
    const percentage = percentages[index];
    return `<article>
      <span class="profile-genre-icon"><svg aria-hidden="true"><use href="#icon-${profileGenreIconId(genre)}"></use></svg></span>
      <strong>${escapeHtml(genre)}</strong>
      <i><b style="width:${percentage}%"></b></i>
      <em>${percentage ? `${percentage}%` : "—"}</em>
    </article>`;
  }).join("");
}

function profileMemberSince(user, profile) {
  const raw = profile?.created_at || user?.created_at;
  const date = raw ? new Date(raw) : null;
  if (!date || Number.isNaN(date.getTime())) return "Membro Ludograph";
  return `Membro da ${date.toLocaleDateString("it-IT", { month: "short", year: "numeric" }).replace(".", "")}`;
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
  ui.profilePageBio.textContent = profile?.bio || "Raccogli, ricorda e racconta la tua storia di gioco.";
  ui.profilePageEmail.textContent = user.email || "";
  if (ui.profileVisibilityText) ui.profileVisibilityText.textContent = profile?.is_public === false ? "Profilo privato" : "Profilo pubblico";
  ui.profileVisibilityBadge?.classList.toggle("is-private", profile?.is_public === false);
  ui.viewPublicProfile.hidden = !profile?.username || profile?.is_public === false;
  if (profile?.username) ui.viewPublicProfile.href = profileRoute(profile.username);
  ui.profileUsername.value = profile?.username || "";
  ui.profileDisplayName.value = profile?.display_name || profile?.username || "";
  ui.profileBio.value = profile?.bio || "";

  const memberSince = $("#profile-member-since-text");
  const verifiedBadge = $("#profile-verified-badge");
  if (memberSince) memberSince.textContent = profileMemberSince(user, profile);
  if (verifiedBadge) verifiedBadge.hidden = !Boolean(user.email_confirmed_at || user.confirmed_at);

  const stats = profileStats();
  $("#profile-stat-library").textContent = stats.library.toLocaleString("it-IT");
  $("#profile-stat-completed").textContent = stats.completed.toLocaleString("it-IT");
  $("#profile-stat-hours").textContent = stats.hours;
  $("#profile-stat-streak").textContent = stats.streak.toLocaleString("it-IT");
  $("#profile-stat-rating").textContent = stats.averageRating ? stats.averageRating.toFixed(1) : "—";
  $("#profile-stat-played").textContent = `${stats.playedPercent}%`;
  $("#profile-stat-library-meta").textContent = stats.favorites ? `${stats.favorites} preferiti` : "Il tuo archivio";
  $("#profile-stat-completed-meta").textContent = stats.library ? `${Math.round((stats.completed / stats.library) * 100)}% della libreria` : "Nessun completamento";
  $("#profile-stat-hours-meta").textContent = stats.sessions ? `${stats.sessions} session${stats.sessions === 1 ? "e" : "i"} registrat${stats.sessions === 1 ? "a" : "e"}` : "Nessuna sessione";
  $("#profile-stat-streak-meta").textContent = stats.streak ? "Continua così" : "Registra una sessione";
  $("#profile-stat-rating-stars").textContent = stats.averageRating ? `${"★".repeat(Math.round(stats.averageRating))}${"☆".repeat(Math.max(0, 5 - Math.round(stats.averageRating)))}` : "☆☆☆☆☆";
  $("#profile-stat-played-meta").textContent = `${stats.played} di ${stats.library}`;

  $("#profile-hero-hours").textContent = stats.hours;
  $("#profile-hero-library").textContent = stats.library.toLocaleString("it-IT");
  $("#profile-hero-completed").textContent = stats.completed.toLocaleString("it-IT");
  const activeToday = stats.journalEntries.some((entry) => homeLocalDateKey(entry.playedAt || entry.createdAt) === homeLocalDateKey());
  $("#profile-hero-active").textContent = activeToday
    ? "Attivo oggi"
    : (stats.journalEntries.length ? "Attività registrata" : "Nessuna attività registrata");
  $("#profile-hub-library-count").textContent = `${stats.library} gioch${stats.library === 1 ? "o" : "i"}`;
  $("#profile-hub-lists-count").textContent = `${stats.lists} list${stats.lists === 1 ? "a" : "e"}`;
  $("#profile-hub-diary-count").textContent = `${stats.sessions} voc${stats.sessions === 1 ? "e" : "i"}`;

  renderProfileRecentGames();
  renderProfileGenres();
  const profileArtwork = profileBackdropArtwork(libraryEntryRecords(), profile);
  if (ui.profileHeroBackdrop) {
    ui.profileHeroBackdrop.style.backgroundImage = profileArtwork ? `url("${profileArtwork.replaceAll('"', '%22')}")` : "";
    ui.profileHeroBackdrop.classList.toggle("has-art", Boolean(profileArtwork));
  }
}


async function renderSteamConnectionPanel() {
  if (!ui.steamConnectionCard) return;
  const user = state.auth.user;
  ui.steamSyncMessage.hidden = true;

  if (!user || !window.VaultSteam) {
    ui.steamConnectionName.textContent = "Steam non collegato";
    ui.steamConnectionId.textContent = "Accedi a Ludograph per collegare Steam.";
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

function profileHeroChoices() {
  const seen = new Set();
  return libraryEntryRecords()
    .map((entry) => ({
      title: entry.game?.title || "Gioco",
      url: profileWideArtwork(entry.game),
    }))
    .filter((item) => {
      if (!item.url || seen.has(item.url)) return false;
      seen.add(item.url);
      return true;
    });
}

function setProfileHeroPreview(url) {
  if (!ui.settingsHeroPreview) return;
  const artwork = String(url || "").trim() || profileBackdropArtwork();
  ui.settingsHeroPreview.style.backgroundImage = artwork ? `url("${artwork.replaceAll('"', '%22')}")` : "";
  ui.settingsHeroPreview.classList.toggle("has-art", Boolean(artwork));
}

function renderProfileHeroSettings(profile = state.auth.profile) {
  if (!ui.profileHeroGameSelect) return;
  const selectedUrl = String(profile?.hero_image_url || "").trim();
  const choices = profileHeroChoices();
  ui.profileHeroGameSelect.innerHTML = '<option value="">Selezione automatica</option>' + choices
    .map((item) => `<option value="${escapeAttr(item.url)}">${escapeHtml(item.title)}</option>`)
    .join("");
  ui.profileHeroGameSelect.value = choices.some((item) => item.url === selectedUrl) ? selectedUrl : "";
  ui.profileHeroUrl.value = selectedUrl && !choices.some((item) => item.url === selectedUrl) ? selectedUrl : "";
  ui.profileHeroReset.disabled = !selectedUrl;
  setProfileHeroPreview(selectedUrl);
}

function showProfileHeroMessage(message, success = false) {
  if (!ui.profileHeroMessage) return;
  ui.profileHeroMessage.textContent = message;
  ui.profileHeroMessage.classList.toggle("auth-success", success);
  ui.profileHeroMessage.hidden = !message;
}

async function saveProfileHero(url, successMessage) {
  showProfileHeroMessage("");
  try {
    await window.VaultAuth.updateProfileHero(url || null);
    renderProfileHeroSettings(window.VaultAuth.profile);
    renderProfilePage();
    showProfileHeroMessage(successMessage, true);
  } catch (error) {
    showProfileHeroMessage(error.message || "Aggiornamento hero fallito.");
  }
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
  renderProfileHeroSettings(profile);
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
    refreshCurrentPersonalView({ skipAdmin: true });
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

    await window.VaultCloud.push(
      merged.pendingLibrary || {},
      merged.pendingLists || {},
      nextUserId,
    );

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

function refreshCurrentPersonalView(options = {}) {
  const skipAdmin = Boolean(options.skipAdmin);
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
  if (state.route.name === "admin" && !skipAdmin) void renderAdminPage();
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
    if (result?.authError) {
      showToast(result.authError.code === "otp_expired"
        ? "Il link è scaduto o è già stato utilizzato."
        : "Il collegamento di autenticazione non è valido.");
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
    app: "Ludograph",
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
  link.download = `ludograph-backup-${new Date().toISOString().slice(0, 10)}.json`;
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
  setButtonLoading(ui.adminOverrideSubmit, true, "Salvataggio…");
  if (ui.adminClearOverride) ui.adminClearOverride.disabled = true;
  ui.adminOverrideMessage.classList.remove("auth-success");
  ui.adminOverrideMessage.textContent = "Salvataggio override in corso…";
  ui.adminOverrideMessage.hidden = false;
  try {
    const record = await window.VaultAdmin.saveCatalogOverride(matchKey, patch, lockedFields);
    state.admin.selectedCatalog = record;
    populateAdminOverrideForm(record);
    ui.adminCatalogTitle.textContent = record.game.title;
    ui.adminOverrideMessage.textContent = "Override salvato e protetto dai prossimi sync.";
    ui.adminOverrideMessage.classList.add("auth-success");
    window.VaultCatalog?.clearCache();
  } catch (error) {
    ui.adminOverrideMessage.classList.remove("auth-success");
    ui.adminOverrideMessage.textContent = error.message || "Salvataggio override fallito.";
  } finally {
    setButtonLoading(ui.adminOverrideSubmit, false);
    if (ui.adminClearOverride) ui.adminClearOverride.disabled = false;
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
    const order = button.dataset.franchiseOrder;
    state.franchiseOrder = ["release", "narrative", "paths"].includes(order) ? order : "release";
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

ui.adminFranchiseEnrich?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  const gameKeys = (state.admin.selectedFranchise?.games || []).map((game) => gameKey(game));
  if (!franchise || !gameKeys.length) {
    showToast("Il franchise non contiene giochi da aggiornare.");
    return;
  }
  setButtonLoading(ui.adminFranchiseEnrich, true, "Recupero…");
  try {
    const result = await window.VaultFranchises.enrichCatalogGames(gameKeys);
    window.VaultCatalog?.clearCache();
    state.admin.selectedFranchise = await window.VaultFranchises.getAdminFranchise(franchise.id);
    syncFranchiseEditorRows(state.admin.selectedFranchise);
    renderAdminFranchiseGames();
    const steam = Number(result.updated_from_steam || 0);
    const inferred = Number(result.inferred_from_title || 0);
    const unresolved = Number(result.unresolved_year || 0);
    const parts = [`${Number(result.updated || 0)} giochi aggiornati`];
    if (steam) parts.push(`${steam} da Steam`);
    if (inferred) parts.push(`${inferred} dal titolo`);
    if (unresolved) parts.push(`${unresolved} ancora senza anno`);
    showToast(`${parts.join(" · ")}.`);
  } catch (error) {
    showToast(error.message || "Recupero metadati Steam fallito. Verifica che la Edge Function sia distribuita.");
  } finally {
    setButtonLoading(ui.adminFranchiseEnrich, false);
  }
});


ui.adminFranchiseExportJson?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise) return;
  try {
    const payload = await fetchAdminFranchiseEditorialExport(ui.adminFranchiseExportJson);
    downloadJson(franchiseEditorialFilename(franchise), payload);
    setAdminFranchiseJsonMessage("Pacchetto editoriale esportato.", true);
  } catch (error) {
    setAdminFranchiseJsonMessage(error.message || "Esportazione JSON fallita.");
  }
});

ui.adminFranchiseCopyPrompt?.addEventListener("click", async () => {
  try {
    const payload = await fetchAdminFranchiseEditorialExport(ui.adminFranchiseCopyPrompt);
    const prompt = buildFranchiseEditorialPrompt(payload);
    await navigator.clipboard.writeText(prompt);
    setAdminFranchiseJsonMessage("Prompt con JSON copiato negli appunti.", true);
  } catch (error) {
    setAdminFranchiseJsonMessage(error.message || "Copia prompt fallita. Esporta il JSON e allegalo manualmente.");
  }
});

ui.adminFranchiseValidateJson?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise) return;
  setButtonLoading(ui.adminFranchiseValidateJson, true, "Validazione…");
  try {
    const payload = parseAdminFranchiseEditorialJson();
    const result = await window.VaultFranchises.importAdminFranchiseEditorial(franchise.id, payload, true);
    setAdminFranchiseJsonMessage(describeFranchiseImportResult(result), true);
  } catch (error) {
    setAdminFranchiseJsonMessage(error.message || "JSON editoriale non valido.");
  } finally {
    setButtonLoading(ui.adminFranchiseValidateJson, false);
  }
});

ui.adminFranchiseApplyJson?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  if (!franchise) return;
  let payload;
  try {
    payload = parseAdminFranchiseEditorialJson();
  } catch (error) {
    setAdminFranchiseJsonMessage(error.message || "JSON editoriale non valido.");
    return;
  }
  if (!confirm("Applicare questa configurazione editoriale? Percorsi e relazioni esistenti del franchise verranno sostituiti.")) return;
  setButtonLoading(ui.adminFranchiseApplyJson, true, "Applicazione…");
  try {
    const result = await window.VaultFranchises.importAdminFranchiseEditorial(franchise.id, payload, false);
    // The v5.3.8 importer is already transactional and set-based. The JSON
    // workflow edits games already present in the franchise, so a second full
    // canonical consolidation would only duplicate expensive database work.
    // consolidateAdminFranchiseVariants remains available for explicit repair
    // operations, but is intentionally not invoked by the normal JSON flow.
    state.admin.selectedFranchise = await window.VaultFranchises.getAdminFranchise(franchise.id);
    syncFranchiseEditorRows(state.admin.selectedFranchise);
    renderAdminFranchiseGames();
    setAdminFranchiseJsonMessage(describeFranchiseImportResult(result), true);
    showToast("Configurazione editoriale importata.");
  } catch (error) {
    setAdminFranchiseJsonMessage(error.message || "Importazione JSON fallita.");
  } finally {
    setButtonLoading(ui.adminFranchiseApplyJson, false);
  }
});

ui.adminFranchiseGameSearchForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  await searchAdminEditorialGames("franchise");
});

ui.adminFranchiseSelectAll?.addEventListener("click", () => {
  const existing = currentFranchiseEditorialIdentities();
  for (const game of state.admin.franchiseSearchResults || []) {
    if (!existing.has(editorialIdentityForGame(game))) setAdminFranchiseGameSelection(game, true);
  }
  updateAdminFranchiseSelectionUI();
});

ui.adminFranchiseDeselectResults?.addEventListener("click", () => {
  const visibleIdentities = new Set((state.admin.franchiseSearchResults || []).map(editorialIdentityForGame));
  state.admin.franchiseGameSelection = (state.admin.franchiseGameSelection || [])
    .filter((game) => !visibleIdentities.has(editorialIdentityForGame(game)));
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
      let enrichment = null;
      try {
        enrichment = await window.VaultFranchises.enrichCatalogGames(payload.map((game) => game.gameKey));
        window.VaultCatalog?.clearCache();
        if (Number(enrichment?.updated || 0) > 0) {
          state.admin.selectedFranchise = await window.VaultFranchises.getAdminFranchise(franchise.id);
        }
      } catch (error) {
        console.warn("Arricchimento automatico Steam non disponibile", error);
      }
      const enriched = Number(enrichment?.updated || 0);
      showToast(`${payload.length} ${payload.length === 1 ? "gioco collegato" : "giochi collegati"} al franchise${enriched ? ` · ${enriched} metadati aggiornati` : ""}.`);
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
    syncFranchiseEditorRows(state.admin.selectedFranchise);
    renderAdminFranchiseGames();
    await loadAdminEditorial({ preserveSelection: false });
  } catch (error) {
    showToast(error.message || "Collegamento fallito.");
  }
});


ui.adminFranchiseEditorSelectAll?.addEventListener("change", (event) => {
  const rows = state.admin.franchiseEditorRows || [];
  state.admin.franchiseEditorSelected = event.currentTarget.checked
    ? new Set(rows.map((row) => row.gameKey))
    : new Set();
  renderAdminFranchiseGames();
});

ui.adminFranchiseApplyType?.addEventListener("click", () => {
  const relationType = ui.adminFranchiseBulkType.value;
  if (!relationType) {
    showToast("Scegli il tipo da applicare.");
    return;
  }
  const targets = franchiseEditorTargets();
  if (!targets.length) return;
  for (const row of targets) {
    row.relationType = relationType;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  }
  renderAdminFranchiseGames();
  showToast(`Tipo applicato a ${targets.length} giochi.`);
});

function numberFranchiseEditorField(field) {
  const targets = franchiseEditorTargets();
  if (!targets.length) return;
  const start = Math.max(1, Number(ui.adminFranchiseNumberStart.value || 1));
  targets.forEach((row, index) => {
    row[field] = start + index;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  });
  renderAdminFranchiseGames();
}

ui.adminFranchiseNumberRelease?.addEventListener("click", () => numberFranchiseEditorField("releaseOrder"));
ui.adminFranchiseNumberNarrative?.addEventListener("click", () => numberFranchiseEditorField("narrativeOrder"));

ui.adminFranchiseClearNarrative?.addEventListener("click", () => {
  const targets = franchiseEditorTargets();
  if (!targets.length) return;
  for (const row of targets) {
    row.narrativeOrder = null;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  }
  renderAdminFranchiseGames();
});

ui.adminFranchiseSortDate?.addEventListener("click", () => {
  const rows = state.admin.franchiseEditorRows || [];
  rows.sort((a, b) => {
    const first = a.releaseDate ? new Date(a.releaseDate).getTime() : Number.MAX_SAFE_INTEGER;
    const second = b.releaseDate ? new Date(b.releaseDate).getTime() : Number.MAX_SAFE_INTEGER;
    return first - second || (a.releaseYear || 9999) - (b.releaseYear || 9999) || a.title.localeCompare(b.title, "it");
  });
  rows.forEach((row, index) => {
    row.releaseOrder = index + 1;
    state.admin.franchiseEditorDirty.add(row.gameKey);
  });
  renderAdminFranchiseGames();
  showToast("Saga ordinata per data di uscita.");
});

ui.adminFranchiseSaveSelected?.addEventListener("click", async () => {
  const selected = state.admin.franchiseEditorSelected || new Set();
  const rows = (state.admin.franchiseEditorRows || []).filter((row) => selected.has(row.gameKey));
  await saveFranchiseEditorRows(rows, ui.adminFranchiseSaveSelected, `${rows.length} giochi salvati.`);
});

ui.adminFranchiseSaveAll?.addEventListener("click", async () => {
  const rows = state.admin.franchiseEditorRows || [];
  await saveFranchiseEditorRows(rows, ui.adminFranchiseSaveAll, `Saga aggiornata: ${rows.length} giochi salvati.`);
});

ui.adminFranchiseRemoveSelected?.addEventListener("click", async () => {
  const franchise = state.admin.selectedFranchise?.franchise;
  const keys = [...(state.admin.franchiseEditorSelected || new Set())];
  if (!franchise || !keys.length) return;
  if (!confirm(`Rimuovere ${keys.length} ${keys.length === 1 ? "gioco" : "giochi"} dalla saga?`)) return;
  setButtonLoading(ui.adminFranchiseRemoveSelected, true, "Rimozione…");
  try {
    const data = await window.VaultFranchises.removeAdminFranchiseGames(franchise.id, keys);
    state.admin.selectedFranchise = data;
    syncFranchiseEditorRows(data);
    renderAdminFranchiseGames();
    await loadAdminEditorial({ preserveSelection: false });
    showToast(`${keys.length} ${keys.length === 1 ? "gioco rimosso" : "giochi rimossi"}.`);
  } catch (error) {
    showToast(error.message || "Rimozione massiva fallita.");
  } finally {
    setButtonLoading(ui.adminFranchiseRemoveSelected, false);
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
  clearTimeout(catalogSearchTimer);

  if (state.route.name === "catalog") {
    // On the catalog page the same input already refreshes the catalog. Do not
    // launch a second autocomplete RPC for every keystroke.
    hideGlobalSearchResults();
    if (state.globalSearch && state.globalSearch.length < 3) return;
    catalogSearchTimer = setTimeout(() => {
      const query = state.globalSearch;
      const nextHash = query ? `#/catalog?q=${encodeURIComponent(query)}` : "#/catalog";
      window.history.replaceState({}, "", nextHash);
      state.search = query;
      void loadCatalogPage({ reset: true });
    }, 450);
    return;
  }

  if (state.globalSearch.length >= 3) {
    globalSearchTimer = setTimeout(() => { void renderGlobalSearchResults(); }, 320);
  } else {
    hideGlobalSearchResults();
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

ui.catalogViewGrid?.addEventListener("click", () => setCatalogView("grid"));
ui.catalogViewList?.addEventListener("click", () => setCatalogView("list"));
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
ui.heroCarouselPrevious?.addEventListener("click", () => renderHomeHeroSlide(homeHeroIndex - 1));
ui.heroCarouselNext?.addEventListener("click", () => renderHomeHeroSlide(homeHeroIndex + 1));
ui.hero?.addEventListener("mouseenter", stopHomeHeroRotation);
ui.hero?.addEventListener("mouseleave", startHomeHeroRotation);
ui.hero?.addEventListener("focusin", stopHomeHeroRotation);
ui.hero?.addEventListener("focusout", startHomeHeroRotation);
ui.homeEditorialPrevious?.addEventListener("click", () => renderHomeCatalogSlide(homeCatalogIndex - 1));
ui.homeEditorialNext?.addEventListener("click", () => renderHomeCatalogSlide(homeCatalogIndex + 1));
ui.homeEditorialFeature?.addEventListener("mouseenter", stopHomeCatalogRotation);
ui.homeEditorialFeature?.addEventListener("mouseleave", startHomeCatalogRotation);
ui.homeEditorialFeature?.addEventListener("focusin", stopHomeCatalogRotation);
ui.homeEditorialFeature?.addEventListener("focusout", startHomeCatalogRotation);

ui.accountButton.addEventListener("click", (event) => {
  event.stopPropagation();
  toggleAccountMenu();
});
ui.accountMenu?.addEventListener("click", (event) => {
  event.stopPropagation();
  if (event.target.closest("a")) closeAccountMenu();
});
document.addEventListener("click", closeAccountMenu);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    closeAccountMenu();
    ui.accountButton?.focus({ preventScroll: true });
  }
});
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
  setButtonLoading(ui.forgotPasswordSubmit, true, "Invio codice…");
  try {
    const email = ui.forgotPasswordEmail.value.trim().toLowerCase();
    await window.VaultAuth.requestPasswordReset(email);
    window.sessionStorage.setItem("tfv:recovery-email", email);
    ui.recoveryCodeEmail.value = email;
    ui.forgotPasswordSuccess.textContent = "Codice inviato. Controlla la posta e la cartella spam, poi inserisci qui le 6 cifre ricevute.";
    ui.forgotPasswordSuccess.hidden = false;
    ui.recoveryCodeValue.focus();
  } catch (error) {
    ui.forgotPasswordError.textContent = error.message || "Invio del codice fallito.";
    ui.forgotPasswordError.hidden = false;
  } finally {
    setButtonLoading(ui.forgotPasswordSubmit, false);
  }
});

ui.recoveryCodeForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.recoveryCodeError.hidden = true;
  setButtonLoading(ui.recoveryCodeSubmit, true, "Verifica…");
  try {
    const email = ui.recoveryCodeEmail.value.trim().toLowerCase();
    const token = ui.recoveryCodeValue.value.replace(/\D/g, "");
    await window.VaultAuth.verifyRecoveryOtp({ email, token });
    window.sessionStorage.removeItem("tfv:recovery-email");
    ui.recoveryCodeForm.reset();
    showToast("Codice verificato. Ora scegli la nuova password.");
    navigate("#/reset-password");
  } catch (error) {
    const invalidCode = /expired|invalid|token|otp/i.test(error?.message || "");
    ui.recoveryCodeError.textContent = invalidCode
      ? "Codice non valido o scaduto. Richiedi un nuovo codice e usa soltanto l’ultimo ricevuto."
      : (error.message || "Verifica del codice fallita.");
    ui.recoveryCodeError.hidden = false;
  } finally {
    setButtonLoading(ui.recoveryCodeSubmit, false);
  }
});

ui.recoveryCodeValue.addEventListener("input", () => {
  const digits = ui.recoveryCodeValue.value.replace(/\D/g, "").slice(0, 6);
  if (ui.recoveryCodeValue.value !== digits) ui.recoveryCodeValue.value = digits;
});

ui.resetPasswordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  ui.resetPasswordError.hidden = true;
  setButtonLoading(ui.resetPasswordSubmit, true, "Aggiornamento…");
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
  } finally {
    setButtonLoading(ui.resetPasswordSubmit, false);
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

ui.profileHeroGameSelect?.addEventListener("change", () => {
  const selected = ui.profileHeroGameSelect.value;
  setProfileHeroPreview(selected || state.auth.profile?.hero_image_url || "");
});
ui.profileHeroApplyGame?.addEventListener("click", async () => {
  const selected = ui.profileHeroGameSelect.value;
  if (!selected) {
    showProfileHeroMessage("Seleziona prima un gioco con artwork panoramico.");
    return;
  }
  await saveProfileHero(selected, "Hero aggiornata con l’artwork selezionato.");
});
ui.profileHeroUpload?.addEventListener("click", () => ui.profileHeroFile?.click());
ui.profileHeroFile?.addEventListener("change", async () => {
  const file = ui.profileHeroFile.files?.[0];
  if (!file) return;
  ui.profileHeroUpload.disabled = true;
  showProfileHeroMessage("");
  try {
    await window.VaultAuth.uploadProfileHero(file);
    renderProfileHeroSettings(window.VaultAuth.profile);
    renderProfilePage();
    showProfileHeroMessage("Hero caricata.", true);
  } catch (error) {
    showProfileHeroMessage(error.message || "Caricamento hero fallito.");
  } finally {
    ui.profileHeroFile.value = "";
    ui.profileHeroUpload.disabled = false;
  }
});
ui.profileHeroReset?.addEventListener("click", async () => {
  showProfileHeroMessage("");
  try {
    await window.VaultAuth.removeProfileHero();
    renderProfileHeroSettings(window.VaultAuth.profile);
    renderProfilePage();
    showProfileHeroMessage("Selezione automatica ripristinata.", true);
  } catch (error) {
    showProfileHeroMessage(error.message || "Ripristino hero fallito.");
  }
});
ui.profileHeroApplyUrl?.addEventListener("click", async () => {
  const value = ui.profileHeroUrl.value.trim();
  if (!/^https?:\/\//i.test(value)) {
    showProfileHeroMessage("Inserisci un URL HTTPS valido.");
    return;
  }
  await saveProfileHero(value, "Hero aggiornata dall’URL indicato.");
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
  if (!window.confirm("Eliminare definitivamente il tuo account Ludograph?")) return;
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
