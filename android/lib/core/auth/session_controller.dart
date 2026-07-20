import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme.dart';
import '../api/athlete_api.dart';
import '../models/models.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import '../utils/haptics.dart';

/// Root phase of either app: cold-open splash → login → main shell.
enum AppPhase { splash, login, app }

/// Session/auth state — port of iOS `AppState`.
@immutable
class SessionState {
  const SessionState({
    this.phase = AppPhase.splash,
    this.user,
    this.me,
    this.avatarUrl,
    this.loginError,
    this.isAuthenticating = false,
    this.needsTermsConsent = false,
    this.showChiron = false,
    this.showReview = false,
    this.bootstrapRetryable = false,
    this.tabBarHidden = false,
    this.chironHidden = false,
    this.themeVersion = 0,
  });

  final AppPhase phase;
  final AuthUser? user;
  final MeResponse? me;
  final String? avatarUrl;
  final String? loginError;
  final bool isAuthenticating;

  /// Blocking legal gate (full-screen, not dismissible).
  final bool needsTermsConsent;

  /// First-login Chiron tutorial (athlete) / profile wizard trigger (coach).
  final bool showChiron;

  /// Post-tutorial store-review prompt.
  final bool showReview;

  /// Bootstrap failed for a reason other than 401 (offline/5xx): keep the
  /// token, show a retry on the splash instead of kicking the user out.
  final bool bootstrapRetryable;

  /// Slides the floating tab bar off-screen (chat, active session, forms).
  final bool tabBarHidden;

  /// Hides the coach Chiron FAB (chat screens).
  final bool chironHidden;

  /// Bumped when brand colors change → root remounts (iOS `.id()` trick).
  final int themeVersion;

  String get greetingName {
    final first = user?.firstName ?? '';
    return first.isNotEmpty ? first : 'Atleta';
  }

  SessionState copyWith({
    AppPhase? phase,
    AuthUser? user,
    MeResponse? me,
    String? avatarUrl,
    bool avatarUrlNull = false,
    String? loginError,
    bool loginErrorNull = false,
    bool? isAuthenticating,
    bool? needsTermsConsent,
    bool? showChiron,
    bool? showReview,
    bool? bootstrapRetryable,
    bool? tabBarHidden,
    bool? chironHidden,
    int? themeVersion,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      user: user ?? this.user,
      me: me ?? this.me,
      avatarUrl: avatarUrlNull ? null : (avatarUrl ?? this.avatarUrl),
      loginError: loginErrorNull ? null : (loginError ?? this.loginError),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      needsTermsConsent: needsTermsConsent ?? this.needsTermsConsent,
      showChiron: showChiron ?? this.showChiron,
      showReview: showReview ?? this.showReview,
      bootstrapRetryable: bootstrapRetryable ?? this.bootstrapRetryable,
      tabBarHidden: tabBarHidden ?? this.tabBarHidden,
      chironHidden: chironHidden ?? this.chironHidden,
      themeVersion: themeVersion ?? this.themeVersion,
    );
  }
}

/// Prefs keys (parity with iOS UserDefaults keys).
class PrefsKeys {
  PrefsKeys._();
  static const onboarded = 'athlynk.onboarded';
  static const coachOnboarded = 'athlynk.coach.onboarded';
  static const coachChironDone = 'athlynk.coach.chiron.done';
  static const reviewDone = 'athlynk.reviewDone';
  static const brandPrimary = BrandTheme.prefsPrimaryKey;
  static const brandAccent = BrandTheme.prefsAccentKey;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Brand colors load before any fetch so the app opens in the right colors.
    final prefs = ref.read(prefsProvider);
    BrandTheme.load(
      prefs.getString(PrefsKeys.brandPrimary),
      prefs.getString(PrefsKeys.brandAccent),
    );
    return const SessionState();
  }

  /// Cold boot: token in secure storage → `/me`; 401 clears the token and
  /// drops to login; any other failure keeps it and offers retry.
  Future<void> bootstrap() async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(tokenStorageProvider);
    final flavor = ref.read(flavorProvider);

    state = state.copyWith(bootstrapRetryable: false);
    final token = await storage.read();
    if (token == null || token.isEmpty) {
      state = state.copyWith(phase: AppPhase.login);
      return;
    }
    api.token = token;
    try {
      final me = await api.me();
      _applySession(me, flavor);
    } on ApiHttpException catch (e) {
      if (e.statusCode == 401) {
        api.token = null;
        await storage.clear();
        state = state.copyWith(phase: AppPhase.login);
      } else {
        state = state.copyWith(bootstrapRetryable: true);
      }
    } on ApiException {
      state = state.copyWith(bootstrapRetryable: true);
    }
  }

  Future<void> login(String email, String password) async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(tokenStorageProvider);
    final flavor = ref.read(flavorProvider);

    state = state.copyWith(isAuthenticating: true, loginErrorNull: true);
    try {
      final res = await api.login(email.trim(), password, flavor.role);
      api.token = res.token;
      await storage.write(res.token);
      final me = await api.me();
      Haptics.success();
      _applySession(me, flavor);
    } on ApiException catch (e) {
      Haptics.error();
      state = state.copyWith(loginError: e.userMessage);
    } finally {
      state = state.copyWith(isAuthenticating: false);
    }
  }

  void _applySession(MeResponse me, AppFlavor flavor) {
    final prefs = ref.read(prefsProvider);
    final user = me.user;

    // Server-driven brand colors (white-label per coach).
    final p = me.profile;
    if (p?.brandPrimary != null || p?.brandAccent != null) {
      _persistBrand(p?.brandPrimary, p?.brandAccent, bump: false);
    }

    final chironPending = flavor == AppFlavor.athlete
        ? user.needsChironIntro
        : !(prefs.getBool(PrefsKeys.coachChironDone) ?? false);

    state = state.copyWith(
      user: user,
      me: me,
      avatarUrl: p?.profileImageUrl,
      needsTermsConsent: user.needsTermsConsent,
      showChiron: !user.needsTermsConsent && chironPending,
      phase: AppPhase.app,
      bootstrapRetryable: false,
    );
  }

  Future<bool> acceptTerms() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.acceptTerms();
      final user = state.user;
      state = state.copyWith(
        needsTermsConsent: false,
        // Terms gate cleared → Chiron intro may now fire.
        showChiron: user != null && _chironPendingAfterTerms(),
      );
      return true;
    } on ApiException {
      Haptics.error();
      return false;
    }
  }

  bool _chironPendingAfterTerms() {
    final flavor = ref.read(flavorProvider);
    final prefs = ref.read(prefsProvider);
    return flavor == AppFlavor.athlete
        ? (state.user?.needsChironIntro ?? false)
        : !(prefs.getBool(PrefsKeys.coachChironDone) ?? false);
  }

  /// Persists tutorial completion; 0.5 s later triggers the review prompt
  /// (once ever), same sequencing as iOS `finishChiron`.
  Future<void> finishChiron() async {
    final api = ref.read(apiClientProvider);
    final prefs = ref.read(prefsProvider);
    final flavor = ref.read(flavorProvider);

    state = state.copyWith(showChiron: false);
    if (flavor == AppFlavor.athlete) {
      try {
        await api.completeTutorial();
      } on ApiException {/* best-effort */}
    } else {
      await prefs.setBool(PrefsKeys.coachChironDone, true);
    }
    if (!(prefs.getBool(PrefsKeys.reviewDone) ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(showReview: true);
    }
  }

  Future<void> dismissReview() async {
    final prefs = ref.read(prefsProvider);
    await prefs.setBool(PrefsKeys.reviewDone, true);
    state = state.copyWith(showReview: false);
  }

  Future<void> logout() async {
    final api = ref.read(apiClientProvider);
    final storage = ref.read(tokenStorageProvider);
    ref.read(memoryCacheProvider).invalidateAll();
    api.token = null;
    await storage.clear();
    state = const SessionState(phase: AppPhase.login);
  }

  Future<bool> deleteAccount() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.deleteAccount();
      await logout();
      return true;
    } on ApiException {
      Haptics.error();
      return false;
    }
  }

  /// "Aspetto": persists + applies the brand colors, then remounts the tree
  /// after a short delay so the settings sheet finishes its own dismiss
  /// animation first (parity with iOS `applyBrand`).
  Future<void> applyBrand({String? primaryHex, String? accentHex}) async {
    _persistBrand(primaryHex, accentHex, bump: false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    state = state.copyWith(themeVersion: state.themeVersion + 1);
  }

  void _persistBrand(String? primaryHex, String? accentHex,
      {required bool bump}) {
    final prefs = ref.read(prefsProvider);
    if (primaryHex == null || colorFromHexString(primaryHex) == null) {
      prefs.remove(PrefsKeys.brandPrimary);
    } else {
      prefs.setString(PrefsKeys.brandPrimary, primaryHex);
    }
    if (accentHex == null || colorFromHexString(accentHex) == null) {
      prefs.remove(PrefsKeys.brandAccent);
    } else {
      prefs.setString(PrefsKeys.brandAccent, accentHex);
    }
    BrandTheme.load(prefs.getString(PrefsKeys.brandPrimary),
        prefs.getString(PrefsKeys.brandAccent));
    if (bump) {
      state = state.copyWith(themeVersion: state.themeVersion + 1);
    }
  }

  void setAvatarUrl(String? url) =>
      state = state.copyWith(avatarUrl: url, avatarUrlNull: url == null);

  void setTabBarHidden(bool hidden) {
    if (state.tabBarHidden != hidden) {
      state = state.copyWith(tabBarHidden: hidden);
    }
  }

  void setChironHidden(bool hidden) {
    if (state.chironHidden != hidden) {
      state = state.copyWith(chironHidden: hidden);
    }
  }
}
