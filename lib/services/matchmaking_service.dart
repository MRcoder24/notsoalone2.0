import 'dart:math' as math;

class MatchmakingService {
  /// Sorts a list of athletes based on their multi-dimensional proximity to the current user.
  /// The dimensions used are: [latitude, longitude, skill_level, stamina_level].
  /// Location is normalized to prevent it from dominating the skill/stamina dimensions.
  static List<dynamic> sortAthletesByKNN({
    required Map<String, dynamic> currentUser,
    required List<dynamic> athletes,
  }) {
    if (athletes.isEmpty) return athletes;

    final double myLat = _extractDouble(currentUser['latitude']) ?? _extractDouble(currentUser['lat']) ?? 0.0;
    final double myLng = _extractDouble(currentUser['longitude']) ?? _extractDouble(currentUser['lng']) ?? 0.0;
    final double mySkill = _extractDouble(currentUser['skill_level']) ?? 5.0;
    final double myStamina = _extractDouble(currentUser['stamina_level']) ?? 5.0;

    // Normalization factors
    // Lat/Lng can vary roughly by 0.01 per km (approximate). Let's say max diff we care about is 10km (0.1 degrees).
    // Skill and stamina vary from 1 to 10 (max diff 9).
    // So we normalize location diffs by a scaling factor to keep them comparable to skill diffs.
    const double locationScale = 100.0; // 0.1 degree diff becomes 10 (comparable to skill diff)
    const double skillScale = 1.0;
    const double staminaScale = 1.0;

    List<Map<String, dynamic>> scoredAthletes = [];

    for (var athlete in athletes) {
      final double lat = _extractDouble(athlete['latitude']) ?? _extractDouble(athlete['lat']) ?? 0.0;
      final double lng = _extractDouble(athlete['longitude']) ?? _extractDouble(athlete['lng']) ?? 0.0;
      final double skill = _extractDouble(athlete['skill_level']) ?? 5.0;
      final double stamina = _extractDouble(athlete['stamina_level']) ?? 5.0;

      // If location is exactly 0,0, they probably don't have location data, but we still compute
      
      final double latDiff = (lat - myLat) * locationScale;
      final double lngDiff = (lng - myLng) * locationScale;
      final double skillDiff = (skill - mySkill) * skillScale;
      final double staminaDiff = (stamina - myStamina) * staminaScale;

      // Euclidean distance in 4D space
      final double distance = math.sqrt(
          math.pow(latDiff, 2) +
          math.pow(lngDiff, 2) +
          math.pow(skillDiff, 2) +
          math.pow(staminaDiff, 2)
      );

      scoredAthletes.add({
        'athlete': athlete,
        'knn_distance': distance,
      });
    }

    // Sort by smallest distance
    scoredAthletes.sort((a, b) => (a['knn_distance'] as double).compareTo(b['knn_distance'] as double));

    return scoredAthletes.map((e) => e['athlete']).toList();
  }

  static double? _extractDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
