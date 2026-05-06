import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/review_service.dart';

class PeerReviewScreen extends StatefulWidget {
  final String? matchId;
  final String revieweeId;
  final String revieweeName;

  const PeerReviewScreen({
    super.key,
    this.matchId,
    required this.revieweeId,
    required this.revieweeName,
  });

  @override
  State<PeerReviewScreen> createState() => _PeerReviewScreenState();
}

class _PeerReviewScreenState extends State<PeerReviewScreen> {
  int _skillRating = 3;
  int _staminaRating = 3;
  int _safetyRating = 5;
  int _sportsmanshipRating = 4;
  bool _isSubmitting = false;

  Future<void> _submitReview() async {
    setState(() => _isSubmitting = true);
    try {
      await ReviewService.submitReview(
        matchId: widget.matchId,
        revieweeId: widget.revieweeId,
        skillRating: _skillRating,
        staminaRating: _staminaRating,
        safetyRating: _safetyRating,
        sportsmanshipRating: _sportsmanshipRating,
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review submitted successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit review: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildRatingSlider(String title, String description, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(fontFamily: 'Manrope', fontSize: 12, color: AppTheme.textVariant),
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          activeColor: AppTheme.primary,
          inactiveColor: AppTheme.outline.withOpacity(0.3),
          onChanged: (double newValue) => onChanged(newValue.toInt()),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textMain),
        title: const Text('Peer Review', style: TextStyle(color: AppTheme.textMain, fontFamily: 'Lexend')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate ${widget.revieweeName}',
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your feedback helps maintain a safe and competitive environment.',
              style: TextStyle(fontFamily: 'Manrope', color: AppTheme.textVariant),
            ),
            const SizedBox(height: 32),
            
            _buildRatingSlider(
              'Skill Level',
              'How would you rate their overall gameplay and technical ability?',
              _skillRating,
              (v) => setState(() => _skillRating = v),
            ),
            _buildRatingSlider(
              'Stamina & Fitness',
              'Did they keep up with the physical demands of the match?',
              _staminaRating,
              (v) => setState(() => _staminaRating = v),
            ),
            _buildRatingSlider(
              'Safety & Care',
              'Did they play safely and avoid dangerous tackles/moves?',
              _safetyRating,
              (v) => setState(() => _safetyRating = v),
            ),
            _buildRatingSlider(
              'Sportsmanship',
              'Were they respectful, fair, and a good team player?',
              _sportsmanshipRating,
              (v) => setState(() => _sportsmanshipRating = v),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _submitReview,
                child: _isSubmitting 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Submit Review', style: TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
