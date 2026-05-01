import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'group_chats_screen.dart';
import 'create_event_screen.dart';
import 'edit_profile_screen.dart';
import '../theme/app_theme.dart';
import 'explore_screen.dart';

// ────────────────────────────────────────────────────────────────────────────
// Sport data
// ────────────────────────────────────────────────────────────────────────────
const List<Map<String, dynamic>> _sportData = [
  {'icon': Icons.sports_soccer, 'label': 'Football', 'color': Color(0xFF4CAF50)},
  {'icon': Icons.sports_cricket, 'label': 'Cricket', 'color': Color(0xFF8BC34A)},
  {'icon': Icons.sports_tennis, 'label': 'Badminton', 'color': Color(0xFFFF9800)},
  {'icon': Icons.sports_basketball, 'label': 'Basketball', 'color': Color(0xFFFF5722)},
  {'icon': Icons.sports_tennis, 'label': 'Tennis', 'color': Color(0xFF9C27B0)},
  {'icon': Icons.sports_volleyball, 'label': 'Volleyball', 'color': Color(0xFF2196F3)},
  {'icon': Icons.sports_tennis, 'label': 'Table Tennis', 'color': Color(0xFF00BCD4)},
  {'icon': Icons.pool, 'label': 'Swimming', 'color': Color(0xFF03A9F4)},
  {'icon': Icons.directions_run, 'label': 'Running', 'color': Color(0xFF3F51B5)},
  {'icon': Icons.directions_bike, 'label': 'Cycling', 'color': Color(0xFF607D8B)},
  {'icon': Icons.sports_baseball, 'label': 'Baseball', 'color': Color(0xFF795548)},
  {'icon': Icons.sports_rugby, 'label': 'Rugby', 'color': Color(0xFF9E9E9E)},
  {'icon': Icons.sports_hockey, 'label': 'Hockey', 'color': Color(0xFF000000)},
  {'icon': Icons.sports_golf, 'label': 'Golf', 'color': Color(0xFF388E3C)},
  {'icon': Icons.sports_mma, 'label': 'Boxing', 'color': Color(0xFFF44336)},
  {'icon': Icons.sports_martial_arts, 'label': 'MMA', 'color': Color(0xFFE91E63)},
  {'icon': Icons.self_improvement, 'label': 'Yoga', 'color': Color(0xFF8E24AA)},
  {'icon': Icons.fitness_center, 'label': 'Gym', 'color': Color(0xFF1976D2)},
  {'icon': Icons.skateboarding, 'label': 'Skateboarding', 'color': Color(0xFFFF6F00)},
  {'icon': Icons.hiking, 'label': 'Climbing', 'color': Color(0xFF6D4C41)},
  {'icon': Icons.sports_esports, 'label': 'Esports', 'color': Color(0xFF0052D0)},
];

// ────────────────────────────────────────────────────────────────────────────
// Recommendations per sport (shown in Personalized Recommendation card)
// ────────────────────────────────────────────────────────────────────────────
const Map<String, Map<String, String>> _recommendations = {
  'Football': {
    'tag': 'NEW FOR YOU',
    'title': 'Dominate the Pitch\nwith Football',
    'desc': 'Find local football matches and train with professional coaches near you.',
    'cta': 'Explore Football',
  },
  'Cricket': {
    'tag': 'TRENDING',
    'title': 'Sharpen Your\nCricket Skills',
    'desc': 'Join local cricket clubs and compete in weekend tournaments.',
    'cta': 'Explore Cricket',
  },
  'Basketball': {
    'tag': 'NEW FOR YOU',
    'title': 'Elevate Your\nPerformance in\nBasketball',
    'desc': 'Join the local elite community and start your high-intensity training with professional coaches nearby.',
    'cta': 'Explore Basketball',
  },
  'Swimming': {
    'tag': 'HOT',
    'title': 'Dive Into\nSwimming',
    'desc': 'Connect with swimmers at your local pool and join training sessions.',
    'cta': 'Explore Swimming',
  },
};

Map<String, String> _getRecommendation(String sport) {
  return _recommendations[sport] ?? {
    'tag': 'FOR YOU',
    'title': 'Master\n$sport Today',
    'desc': 'Find nearby $sport events, players, and venues to boost your game.',
    'cta': 'Explore $sport',
  };
}

// ────────────────────────────────────────────────────────────────────────────
// Widget
// ────────────────────────────────────────────────────────────────────────────
class AllSportsScreen extends StatefulWidget {
  const AllSportsScreen({super.key});
  @override
  State<AllSportsScreen> createState() => _AllSportsScreenState();
}

class _AllSportsScreenState extends State<AllSportsScreen> {
  // Colors mapped to AppTheme
  final Color _bgColor = AppTheme.background;
  final Color _primaryColor = AppTheme.primary;
  final Color _primaryContainer = AppTheme.primaryLight;
  final Color _onPrimaryContainer = AppTheme.primary;
  final Color _surfaceContainerHigh = AppTheme.surfaceContainer;
  final Color _surfaceContainerLowest = AppTheme.surface;
  final Color _onSurface = AppTheme.textMain;
  final Color _onSurfaceVariant = AppTheme.textVariant;
  final Color _outline = AppTheme.outline;

  // State
  String _searchQuery = '';
  String _selectedSport = 'Basketball';
  int _selectedIndex = 1; // explore tab

  // Upcoming events for selected sport from Supabase
  List<dynamic> _events = [];
  bool _loadingEvents = false;

  @override
  void initState() {
    super.initState();
    _loadEventsForSport(_selectedSport);
  }

  Future<void> _loadEventsForSport(String sport) async {
    setState(() { _loadingEvents = true; _events = []; });
    try {
      final data = await Supabase.instance.client
          .from('matches')
          .select()
          .eq('sport', sport)
          .limit(5);
      if (mounted) setState(() { _events = data as List<dynamic>; _loadingEvents = false; });
    } catch (e) {
      debugPrint('Load events error: $e');
      if (mounted) setState(() { _loadingEvents = false; });
    }
  }

  void _onSportTap(String sport) {
    setState(() => _selectedSport = sport);
    _loadEventsForSport(sport);
    // Scroll smoothly is implicit as state rebuilds
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Showing events for $sport'),
        backgroundColor: _primaryColor,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredSports {
    if (_searchQuery.isEmpty) return _sportData;
    return _sportData.where((s) => (s['label'] as String).toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rec = _getRecommendation(_selectedSport);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor.withOpacity(0.7),
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text('Explore', style: TextStyle(color: _onSurface, fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 20)),
          centerTitle: true,
          bottom: TabBar(
            indicatorColor: _primaryColor,
            labelColor: _primaryColor,
            unselectedLabelColor: _onSurfaceVariant,
            labelStyle: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Categories'),
              Tab(text: 'Nearby Athletes'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // ── Title ──────────────────────────────────────
            Text('All Sports', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w800, fontSize: 32, color: _onSurface)),
            const SizedBox(height: 24),

            // ── Search ─────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: _surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.dropShadow,
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search your favorite sport...',
                  hintStyle: TextStyle(fontFamily: 'Manrope', color: _outline.withOpacity(0.6)),
                  prefixIcon: Icon(Icons.search, color: _outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // ── Sport Grid ─────────────────────────────────
            _filteredSports.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text('No sports found', style: TextStyle(color: _onSurfaceVariant, fontFamily: 'Manrope')),
                  ))
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _filteredSports.length,
                    itemBuilder: (context, index) => Align(
                      alignment: Alignment.topCenter,
                      child: _buildSportItem(_filteredSports[index]),
                    ),
                  ),
            const SizedBox(height: 40),

            // ── Personalized Recommendation ────────────────
            Text('Personalized Recommendation', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 20, color: _onSurface)),
            const SizedBox(height: 12),
            Text('Tap any sport above to get tailored recommendations', style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: _onSurfaceVariant)),
            const SizedBox(height: 16),

            // Recommendation Card
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(_selectedSport),
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.dropShadow,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: _primaryContainer, borderRadius: BorderRadius.circular(24)),
                          child: Text(rec['tag']!, style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.bold, fontSize: 10, color: _onPrimaryContainer)),
                        ),
                        const SizedBox(height: 16),
                        Text(rec['title']!, style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w800, fontSize: 24, color: Colors.white, height: 1.2)),
                        const SizedBox(height: 12),
                        Text(rec['desc']!, style: const TextStyle(fontFamily: 'Manrope', color: Color(0xFF638EFF), fontSize: 14)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen()));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _surfaceContainerLowest,
                            foregroundColor: _primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: Text(rec['cta']!, style: const TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Positioned(
                      right: -20, top: 20,
                      child: Icon(
                        _sportData.firstWhere((s) => s['label'] == _selectedSport, orElse: () => _sportData.last)['icon'] as IconData,
                        size: 140,
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Upcoming Events for Selected Sport ─────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Upcoming Events in $_selectedSport',
                    style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 18, color: _onSurface),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen()));
                  },
                  child: Text('+ Create', style: TextStyle(color: _primaryColor, fontFamily: 'Manrope', fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingEvents)
              Center(child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: _primaryColor),
              ))
            else if (_events.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: _surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Icon(Icons.event_busy, color: _outline, size: 40),
                    const SizedBox(height: 12),
                    Text('No upcoming events for $_selectedSport yet.', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Manrope', color: _onSurfaceVariant)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Be the first to create one!', style: TextStyle(fontFamily: 'Manrope', fontSize: 13)),
                      style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    ),
                  ],
                ),
              )
            else
              ...(_events.map((e) => _buildEventCard(e)).toList()),
            const SizedBox(height: 80),
          ],
        ),
      ),
      const ExploreScreen(isEmbedded: true),
    ],
  ),
  floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen())),
          backgroundColor: _primaryColor,
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    ));
  }

  Widget _buildSportItem(Map<String, dynamic> sport) {
    final label = sport['label'] as String;
    final icon = sport['icon'] as IconData;
    final color = sport['color'] as Color;
    final isSelected = _selectedSport == label;

    return GestureDetector(
      onTap: () => _onSportTap(label),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : _surfaceContainerHigh,
                shape: BoxShape.circle,
                border: isSelected ? Border.all(color: color, width: 2.5) : null,
                boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8)] : null,
              ),
              child: Icon(icon, size: 28, color: isSelected ? color : _onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? _primaryColor : _onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(dynamic event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.event, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title']?.toString() ?? 'Untitled', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 14, color: _onSurface)),
                const SizedBox(height: 2),
                Text(event['location']?.toString() ?? 'Location TBD', style: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: _onSurfaceVariant)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('${event['max_players'] ?? '?'} players', style: TextStyle(fontSize: 11, color: _primaryColor, fontFamily: 'Manrope', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }


}
