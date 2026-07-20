/// In-memory TTL cache — port of iOS `AppDataCache`.
///
/// Pure memory, no disk. 5-minute staleness for every key, cleared entirely
/// on logout. Only the dashboards use it (same keys as iOS).
class MemoryCache {
  MemoryCache({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, ({Object data, DateTime at})> _store = {};

  static const Duration staleDuration = Duration(minutes: 5);

  T? get<T extends Object>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (_clock().difference(entry.at) > staleDuration) {
      _store.remove(key);
      return null;
    }
    final data = entry.data;
    if (data is T) return data;
    return null;
  }

  void set<T extends Object>(String key, T value) {
    _store[key] = (data: value, at: _clock());
  }

  void invalidate(String key) => _store.remove(key);

  void invalidateAll() => _store.clear();
}

/// Cache keys (parity with iOS).
class CacheKeys {
  CacheKeys._();
  static const dashboardWorkouts = 'dashboard.workouts';
  static const dashboardNutrition = 'dashboard.nutrition';
  static const dashboardConversations = 'dashboard.conversations';
  static const dashboardSummary = 'dashboard.summary';
  static const dashboardLayout = 'dashboard.layout';
  static const dashboardCatalog = 'dashboard.catalog';
  static const coachDashboard = 'coach.dashboard';
  static const coachDashboardLayout = 'coach.dashboard.layout';
  static const coachDashboardCatalog = 'coach.dashboard.catalog';
}
