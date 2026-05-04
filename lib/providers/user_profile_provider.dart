import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';

class UserProfileProvider extends ChangeNotifier {
  final _storage = StorageService();

  bool _hasCompletedOnboarding = false;
  int? _userAge;

  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  int? get userAge => _userAge;

  // Age-gated topic keys. Must match the 'topic' values used in DiscoverScreen.
  static const _childTopics = ['fiction', 'adventure'];
  static const _teenTopics = ['fiction', 'love', 'mystery', 'adventure', 'poetry'];
  static const _adultTopics = [
    'fiction',
    'love',
    'mystery',
    'philosophy',
    'poetry',
    'adventure',
  ];

  List<String> get allowedTopics {
    final age = _userAge;
    if (age == null) return _adultTopics;
    if (age < 13) return _childTopics;
    if (age < 18) return _teenTopics;
    return _adultTopics;
  }

  Future<void> init() async {
    _hasCompletedOnboarding = await _storage.getOnboardingDone();
    _userAge = await _storage.getUserAge();
  }

  Future<void> completeOnboarding(int age) async {
    _userAge = age;
    _hasCompletedOnboarding = true;
    await Future.wait([
      _storage.saveUserAge(age),
      _storage.saveOnboardingDone(true),
    ]);
    notifyListeners();
  }
}
