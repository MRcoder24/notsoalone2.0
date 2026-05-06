import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewService {
  static final _supabase = Supabase.instance.client;

  /// Submits a peer review and updates the reviewee's composite score.
  static Future<void> submitReview({
    String? matchId,
    required String revieweeId,
    required int skillRating,
    required int staminaRating,
    required int safetyRating,
    required int sportsmanshipRating,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('Error: No authenticated user.');
      return;
    }

    try {
      // 1. Insert the review
      final payload = {
        'reviewer_id': user.id,
        'reviewee_id': revieweeId,
        'skill_rating': skillRating,
        'stamina_rating': staminaRating,
        'safety_rating': safetyRating,
        'sportsmanship_rating': sportsmanshipRating,
      };
      
      if (matchId != null) {
        payload['match_id'] = matchId;
      }

      await _supabase.from('match_reviews').insert(payload);

      // 2. The database trigger 'on_review_submitted' will automatically
      // recalculate and update the user's composite_score in the profiles table.
    } catch (e) {
      debugPrint('Error submitting review: $e');
      rethrow;
    }
  }
}
