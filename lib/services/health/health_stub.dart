import 'health_types.dart';

class _NoHealth implements HealthSource {
  @override
  bool get available => false;

  @override
  String get displayName => '';

  @override
  String get sourceId => '';

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<List<DayCount>> readDays(int days) async => const [];
}

/// In a browser there is no step sensor to read.
HealthSource createHealthSource(String? Function() userId) => _NoHealth();
