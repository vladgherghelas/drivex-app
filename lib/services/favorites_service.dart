import 'package:flutter/foundation.dart';
import '../supabase_config.dart';

/// Global singleton that tracks which cars the user has saved.
/// All card widgets listen to this and rebuild when it changes.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  final Set<String> _savedIds = {};
  bool _initialized = false;

  bool isSaved(String carId) => _savedIds.contains(carId);
  Set<String> get savedIds => Set.unmodifiable(_savedIds);

  /// Load saved car IDs from Supabase (call once on app start / sign-in).
  Future<void> init() async {
    final user = supabase.auth.currentUser;
    if (user == null) { _savedIds.clear(); _initialized = false; notifyListeners(); return; }
    try {
      final data = await supabase
          .from('saved_cars')
          .select('car_id')
          .eq('user_id', user.id);
      _savedIds.clear();
      for (final row in (data as List)) {
        _savedIds.add(row['car_id'] as String);
      }
      _initialized = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Toggle save/unsave — updates UI immediately (optimistic) then hits Supabase.
  Future<void> toggle(String carId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (_savedIds.contains(carId)) {
      _savedIds.remove(carId);
      notifyListeners();
      await supabase.from('saved_cars')
          .delete()
          .eq('user_id', user.id)
          .eq('car_id', carId);
    } else {
      _savedIds.add(carId);
      notifyListeners();
      await supabase.from('saved_cars')
          .insert({'user_id': user.id, 'car_id': carId});
    }
  }

  void reset() {
    _savedIds.clear();
    _initialized = false;
    notifyListeners();
  }
}
