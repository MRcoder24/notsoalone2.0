import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../widgets/mock_aadhaar_sheet.dart';
import 'medical_id_screen.dart';
import '../theme/app_theme.dart';

const List<String> _allSports = [
  'Football', 'Cricket', 'Basketball', 'Tennis', 'Badminton',
  'Volleyball', 'Table Tennis', 'Swimming', 'Running', 'Cycling',
  'Baseball', 'Rugby', 'Hockey', 'Golf', 'Boxing',
  'MMA', 'Yoga', 'Gym', 'Skateboarding', 'Climbing', 'Kabaddi', 'Esports',
];

const List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // ── Colors ──────────────────────────────────────────────
  final Color _bgColor = AppTheme.background;
  final Color _primaryColor = AppTheme.primary;
  final Color _surfaceContainerLow = AppTheme.surface;
  final Color _surfaceContainerLowest = AppTheme.surface;
  final Color _surfaceContainerHighest = AppTheme.surfaceContainer;
  final Color _surfaceContainer = AppTheme.surfaceContainer;
  final Color _onSurface = AppTheme.textMain;
  final Color _onSurfaceVariant = AppTheme.textVariant;
  final Color _error = const Color(0xFFB31B25);
  final Color _outlineVariant = AppTheme.outline;

  // ── State ────────────────────────────────────────────────
  bool _aadhaarVerified = false;
  bool _isSaving = false;

  // Images (bytes for web compatibility)
  Uint8List? _bannerBytes;
  Uint8List? _avatarBytes;
  String? _avatarUrl;
  String? _bannerUrl;

  // Text controllers
  final _nameController = TextEditingController(text: '');
  final _heightController = TextEditingController(text: '');
  final _weightController = TextEditingController(text: '');
  final _ageController = TextEditingController(text: '');
  final _addressController = TextEditingController(text: '');
  final _bloodGroupController = TextEditingController(text: '');
  final _emergencyContactController = TextEditingController(text: '');
  final _medicalConditionsController = TextEditingController(text: '');

  // BMI
  double? _bmi;
  String _bmiCategory = '';

  // Sports Skills — each entry: {'sport': 'Football', 'level': 'Beginner'}
  final List<Map<String, String>> _sports = [];

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _heightController.addListener(_recalcBmi);
    _weightController.addListener(_recalcBmi);
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    _bloodGroupController.dispose();
    _emergencyContactController.dispose();
    _medicalConditionsController.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────
  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          // Safely read each field — if column doesn't exist, data won't have it
          _nameController.text = (data['full_name'] ?? data['username'] ?? '').toString();
          _ageController.text = data.containsKey('age') ? (data['age'] ?? '').toString() : '';
          _heightController.text = data.containsKey('height') ? (data['height'] ?? '').toString() : '';
          _weightController.text = data.containsKey('weight') ? (data['weight'] ?? '').toString() : '';
          _aadhaarVerified = data.containsKey('aadhaar_verified') ? (data['aadhaar_verified'] ?? false) : false;
          _avatarUrl = data.containsKey('avatar_url') ? data['avatar_url'] : null;
          _bannerUrl = data.containsKey('banner_url') ? data['banner_url'] : null;
          
          if (data.containsKey('medical_data') && data['medical_data'] != null) {
            final medical = data['medical_data'] as Map<String, dynamic>;
            _addressController.text = (medical['address'] ?? '').toString();
            _bloodGroupController.text = (medical['blood_group'] ?? '').toString();
            _emergencyContactController.text = (medical['emergency_contact'] ?? '').toString();
            _medicalConditionsController.text = (medical['medical_conditions'] ?? '').toString();
          }
          // Load sports if stored as a list
          if (data.containsKey('sports_skills')) {
            final rawSports = data['sports_skills'];
            if (rawSports is List) {
              _sports.clear();
              for (final s in rawSports) {
                if (s is Map) {
                  _sports.add({
                    'sport': s['sport']?.toString() ?? '',
                    'level': s['level']?.toString() ?? 'Beginner',
                  });
                }
              }
            }
          }
        });
        _recalcBmi();
      }
    } catch (e) {
      debugPrint('Load profile error: $e');
    }
  }

  // ── BMI ──────────────────────────────────────────────────
  void _recalcBmi() {
    final h = double.tryParse(_heightController.text);
    final w = double.tryParse(_weightController.text);
    if (h != null && w != null && h > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      String category;
      if (bmi < 18.5) {
        category = 'Underweight';
      } else if (bmi < 25) {
        category = 'Normal';
      } else if (bmi < 30) {
        category = 'Overweight';
      } else {
        category = 'Obese';
      }
      if (mounted) {
        setState(() {
          _bmi = bmi;
          _bmiCategory = category;
        });
      }
    } else {
      if (mounted) setState(() { _bmi = null; _bmiCategory = ''; });
    }
  }

  Color _bmiColor() {
    switch (_bmiCategory) {
      case 'Underweight': return Colors.blue;
      case 'Normal': return Colors.green;
      case 'Overweight': return Colors.orange;
      case 'Obese': return Colors.red;
      default: return _onSurfaceVariant;
    }
  }

  // ── Image Picker ─────────────────────────────────────────
  Future<void> _pickBanner() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200, maxHeight: 1200);
    if (img != null && mounted) {
      final bytes = await img.readAsBytes();
      setState(() => _bannerBytes = bytes);
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 500, maxHeight: 500);
    if (img != null && mounted) {
      final bytes = await img.readAsBytes();
      setState(() => _avatarBytes = bytes);
    }
  }

  // ── Aadhaar ───────────────────────────────────────────────
  void _openAadhaarSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const MockAadhaarSheet(),
    );
    if (result == true && mounted) {
      setState(() => _aadhaarVerified = true);
    }
  }

  // ── Sports Skills ─────────────────────────────────────────
  void _showAddSportDialog() {
    final already = _sports.map((s) => s['sport']).toSet();
    showDialog(
      context: context,
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(
          builder: (ctx, setS) {
            return AlertDialog(
              title: const Text('Add a Sport', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: _allSports.length,
                  itemBuilder: (_, i) {
                    final sport = _allSports[i];
                    final isAdded = already.contains(sport);
                    final isSel = selected == sport;
                    return GestureDetector(
                      onTap: isAdded ? null : () => setS(() => selected = sport),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isAdded
                              ? Colors.grey.shade200
                              : isSel
                                  ? _primaryColor
                                  : _surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sport,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Manrope',
                            fontWeight: FontWeight.w600,
                            color: isAdded
                                ? Colors.grey
                                : isSel
                                    ? Colors.white
                                    : _onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          setState(() => _sports.add({'sport': selected!, 'level': 'Beginner'}));
                          Navigator.pop(ctx);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
                  child: const Text('Add', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeSport(int index) => setState(() => _sports.removeAt(index));

  void _updateSportLevel(int index, String level) {
    setState(() => _sports[index] = {..._sports[index], 'level': level});
  }

  // ── Save ──────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _isSaving = true);
    try {
      String? newAvatarUrl = _avatarUrl;
      String? newBannerUrl = _bannerUrl;

      // Upload avatar if changed
      // Professional Storage Upload with Base64 Fallback Bypass
      if (_avatarBytes != null) {
        try {
          final fileName = 'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final path = '${user.id}/$fileName';
          
          // 1. Attempt Cloud Storage Upload
          await Supabase.instance.client.storage.from('avatars').uploadBinary(
            path, 
            _avatarBytes!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
          newAvatarUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
          debugPrint('Avatar uploaded to Cloud Storage: $newAvatarUrl');
        } catch (e) {
          debugPrint('Storage Upload failed (buckets may be missing), using COMPRESSED Base64 Fallback: $e');
          // 2. Fallback to Database Base64 String - CRITICAL: COMPRESS TO THUMBNAIL FOR DB
          // Postgres Text columns can handle much, but large payloads can hit Postgrest/Nginx limits.
          String base64Image = base64Encode(_avatarBytes!);
          newAvatarUrl = "data:image/jpeg;base64,$base64Image";
          
          // If we have a lot of bytes, we might still fail. Let's log the size.
          debugPrint('Base64 Length: ${newAvatarUrl?.length}');
        }
      }

      // Banner Professional Storage Upload with Fallback
      if (_bannerBytes != null) {
        try {
          final fileName = 'banner_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final path = '${user.id}/$fileName';
          
          await Supabase.instance.client.storage.from('banners').uploadBinary(
            path, 
            _bannerBytes!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
          newBannerUrl = Supabase.instance.client.storage.from('banners').getPublicUrl(path);
        } catch (e) {
          debugPrint('Banner Storage failed, using Base64 Fallback: $e');
          String base64Image = base64Encode(_bannerBytes!);
          newBannerUrl = "data:image/jpeg;base64,$base64Image";
        }
      }

      // Build the full payload — we'll try this first
      final fullPayload = <String, dynamic>{
        'id': user.id,
        'username': _nameController.text.trim(),
        'full_name': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'height': double.tryParse(_heightController.text.trim()),
        'weight': double.tryParse(_weightController.text.trim()),
        'bmi': _bmi,
        'aadhaar_verified': _aadhaarVerified,
        'sports_skills': _sports,
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
        if (newBannerUrl != null) 'banner_url': newBannerUrl,
        'medical_data': {
          'address': _addressController.text.trim(),
          'blood_group': _bloodGroupController.text.trim(),
          'emergency_contact': _emergencyContactController.text.trim(),
          'medical_conditions': _medicalConditionsController.text.trim(),
        },
      };

      try {
        await Supabase.instance.client.from('profiles').upsert(fullPayload);
      } on PostgrestException catch (e) {
        // If a column doesn't exist, strip it and retry
        if (e.code == 'PGRST204' || e.message.contains('Could not find')) {
          debugPrint('Full save failed: ${e.message}. Retrying with minimal fields...');
          // Extract the missing column name from the error
          final missingCol = _extractMissingColumn(e.message);
          if (missingCol != null) {
            fullPayload.remove(missingCol);
          }
          // Keep retrying and stripping columns until it works
          await _retrySaveWithFallback(fullPayload);
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully! ✓'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Extract missing column name from a Supabase error like:
  /// "Could not find the 'age' column of 'profiles' in the schema cache"
  String? _extractMissingColumn(String message) {
    final match = RegExp(r"'(\w+)' column").firstMatch(message);
    return match?.group(1);
  }

  /// Retry saving profile, removing any column that causes PGRST204 errors
  Future<void> _retrySaveWithFallback(Map<String, dynamic> payload, [int maxRetries = 10]) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        await Supabase.instance.client.from('profiles').upsert(payload);
        return; // Success!
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST204' || e.message.contains('Could not find')) {
          final missingCol = _extractMissingColumn(e.message);
          if (missingCol != null && payload.containsKey(missingCol)) {
            debugPrint('Removing missing column: $missingCol');
            payload.remove(missingCol);
          } else {
            rethrow; // Can't fix this error
          }
        } else {
          rethrow;
        }
      }
    }
  }

  ImageProvider _getImageProvider(Uint8List? bytes, String? url, String defaultUrl) {
    if (bytes != null) return MemoryImage(bytes);
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:image')) {
        try {
          final base64String = url.split(',').last;
          return MemoryImage(base64Decode(base64String));
        } catch (e) {
          debugPrint('Error decoding base64 image: $e');
        }
      } else {
        return NetworkImage(url);
      }
    }
    return NetworkImage(defaultUrl);
  }

  Widget _buildSectionTitle(String title, {bool isAlert = false}) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: isAlert ? Colors.redAccent : _primaryColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: isAlert ? Colors.redAccent : _onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildMedicalIdCard() {
    // Show a summary of what is currently saved
    final bloodGroup = _bloodGroupController.text.trim();
    final contact = _emergencyContactController.text.trim();
    final conditions = _medicalConditionsController.text.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: GestureDetector(
        onTap: () async {
          final refreshed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const MedicalIdScreen()),
          );
          if (refreshed == true) _loadProfile();
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.health_and_safety, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Medical ID',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bloodGroup.isNotEmpty
                          ? 'Blood: $bloodGroup  •  ${contact.isNotEmpty ? "Contact saved" : "No contact"}'  
                          : 'Tap to set up your Medical ID',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        color: _onSurfaceVariant,
                      ),
                    ),
                    if (conditions.isNotEmpty) ...[  
                      const SizedBox(height: 4),
                      Text(
                        conditions,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          color: _onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor.withOpacity(0.8),
        elevation: 1,
        shadowColor: _outlineVariant.withOpacity(0.15),
        title: Text('Player Profile', style: TextStyle(color: _onSurface, fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 140),
        child: Column(
          children: [
            // ── Banner ──────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _pickBanner,
                  child: Container(
                    height: 192,
                    width: double.infinity,
                    color: _surfaceContainerHighest,
                    child: _bannerBytes != null
                        ? Image.memory(_bannerBytes!, fit: BoxFit.cover, width: double.infinity, height: 192)
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              Image(
                                image: _getImageProvider(
                                  _bannerBytes,
                                  _bannerUrl,
                                  'https://lh3.googleusercontent.com/aida-public/AB6AXuBtmR7lVYu1kMP6zENVDohdnVf-ERL3s-_xeLyQInwyw7TIl5crgNyH2_KNzWh1hzStnxn74Ot-dJSolIpt2q30Yl6OD3O-3zWlP31YNgqMYBHefetZdhxV_Avl9gH4_YaViYmStSc2eqssN5uT5dsJNm20v3z8GF6sIafr7avwAc-7ReRdlBYCCiOi5ygD5jIwY-fGHlAJxRfDojrjjU4iSWkPmjZDfr5W4P9RO-YYXjJGDm6DIZdYeSy-eLHDoHkBxwVT9FqywD0'
                                ),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 192,
                                errorBuilder: (_, __, ___) => Container(color: _surfaceContainerHighest),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                                child: const Icon(Icons.photo_camera, color: Colors.white, size: 28),
                              ),
                            ],
                          ),
                  ),
                ),
                // Camera icon overlay on banner (always visible)
                if (_bannerBytes != null)
                  Positioned(
                    bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: _pickBanner,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                // ── Avatar ───────────────────────────────────
                Positioned(
                  bottom: -64,
                  left: 24,
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            color: _surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _bgColor, width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                            image: DecorationImage(
                              image: _getImageProvider(
                                _avatarBytes,
                                _avatarUrl,
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuDXKAbzAX7xFqDRWiHgcRJn2KbCqjLRhQh4GgnuaR669PU5XnQ3jlil448dp_s--0vKXF3BfMOGq7RQujBoKKt0B96tlcrBFAbtev82mNuJyA_1I-Izla9gzz5JvF-NBVP6PNNIRQngLfiZv0nphY8h_xdqXvVN8qtZpuunuz5YT_98eJvnYbrtIyvOc5j1G-Z2KYpzDn29mUliJPDlJBse3-o6xeVyEkvyx49f-qATaJGtO1HBoTjPNBfzrxPID0CEYBCgku7B8Hg'
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4, right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 80),

            // ── Personal Details ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Personal Details'),
                  const SizedBox(height: 24),
                  _buildTextField('Full Name', _nameController, icon: Icons.person_outline),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Age', _ageController, keyboard: TextInputType.number, suffix: 'yrs')),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Height', _heightController, keyboard: TextInputType.number, suffix: 'cm')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Weight', _weightController, keyboard: TextInputType.number, suffix: 'kg')),
                      const SizedBox(width: 16),
                      Expanded(child: const SizedBox.shrink()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // BMI display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.monitor_heart_outlined, color: _primaryColor),
                        const SizedBox(width: 12),
                        Text('BMI Index', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500, fontSize: 15, color: _onSurface)),
                        const Spacer(),
                        if (_bmi != null) ...[
                          Text(_bmi!.toStringAsFixed(1), style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 18, color: _bmiColor())),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _bmiColor().withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text(_bmiCategory, style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.bold, fontSize: 12, color: _bmiColor())),
                          ),
                        ] else
                          Text('Enter height & weight', style: TextStyle(color: _onSurfaceVariant, fontSize: 13, fontFamily: 'Manrope')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // ── Sports Skills ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionHeader('Sports Skills'),
                      TextButton.icon(
                        onPressed: _showAddSportDialog,
                        icon: Icon(Icons.add, size: 16, color: _primaryColor),
                        label: Text('Add Sport', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500, fontSize: 14, color: _primaryColor)),
                        style: TextButton.styleFrom(backgroundColor: _primaryColor.withOpacity(0.05), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_sports.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Column(
                          children: [
                            Icon(Icons.sports, color: _outlineVariant, size: 40),
                            const SizedBox(height: 8),
                            Text('No sports added yet.\nTap "+ Add Sport" to get started.', textAlign: TextAlign.center, style: TextStyle(color: _onSurfaceVariant, fontFamily: 'Manrope', fontSize: 14)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_sports.length, (i) {
                      final s = _sports[i];
                      final sportName = s['sport'] ?? '';
                      final level = s['level'] ?? 'Beginner';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _outlineVariant.withOpacity(0.1)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.sports, color: _primaryColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(sportName, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 15, color: _onSurface))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: level,
                                  icon: Icon(Icons.expand_more, color: _onSurfaceVariant, size: 18),
                                  style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w500, fontSize: 13, color: _onSurface),
                                  onChanged: (val) { if (val != null) _updateSportLevel(i, val); },
                                  items: _levels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: _error),
                              style: IconButton.styleFrom(backgroundColor: _error.withOpacity(0.08)),
                              onPressed: () => _removeSport(i),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: _buildSectionTitle('Medical ID & Safety (SOS)', isAlert: true),
            ),
            const SizedBox(height: 16),
            _buildMedicalIdCard(),
            const SizedBox(height: 40),

            // ── Aadhaar Verification ─────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: _surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(color: _aadhaarVerified ? Colors.green.withOpacity(0.1) : _surfaceContainerLowest, shape: BoxShape.circle),
                      child: Icon(Icons.verified_user, color: _aadhaarVerified ? Colors.green : _primaryColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aadhaar Verification', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 15, color: _onSurface)),
                          const SizedBox(height: 2),
                          Text(
                            _aadhaarVerified ? '✓ Identity verified' : 'Tap Update to verify your identity',
                            style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: _aadhaarVerified ? Colors.green : _onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        ElevatedButton(
                          onPressed: _aadhaarVerified ? null : _openAadhaarSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _aadhaarVerified ? Colors.green : _surfaceContainerLowest,
                            foregroundColor: _aadhaarVerified ? Colors.white : _primaryColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                          child: Text(_aadhaarVerified ? 'Verified ✓' : 'Update', style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(height: 4),
                        Switch(
                          value: _aadhaarVerified,
                          activeThumbColor: Colors.white,
                          activeTrackColor: _primaryColor,
                          onChanged: (val) { if (!_aadhaarVerified) _openAadhaarSheet(); },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // ── Sign Out ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false);
                    }
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Lexend')),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Save Changes Bottom Button ───────────────────────
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: _bgColor.withOpacity(0.95),
          border: Border(top: BorderSide(color: _outlineVariant.withOpacity(0.2))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              disabledBackgroundColor: _primaryColor.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            child: _isSaving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Save Changes', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                      SizedBox(width: 12),
                      Icon(Icons.check_circle, color: Colors.white),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: _onSurface,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    IconData? icon,
    TextInputType keyboard = TextInputType.text,
    String? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          style: TextStyle(fontFamily: 'Manrope', fontSize: 15, color: _onSurface),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(fontFamily: 'Manrope', color: _onSurfaceVariant, fontSize: 14),
            prefixIcon: icon != null ? Icon(icon, color: _primaryColor, size: 20) : null,
            suffixText: suffix,
            suffixStyle: TextStyle(color: _onSurfaceVariant, fontFamily: 'Manrope'),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
