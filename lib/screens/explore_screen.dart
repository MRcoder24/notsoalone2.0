import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'main_screen.dart';
import 'group_chats_screen.dart';
import 'edit_profile_screen.dart';
import 'chat_room_screen.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../services/matchmaking_service.dart';

class ExploreScreen extends StatefulWidget {
  final bool isEmbedded;
  const ExploreScreen({super.key, this.isEmbedded = false});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<dynamic> nearbyUsers = [];
  bool isLoading = true;
  String? errorMessage;
  String _searchQuery = '';
  String _selectedSportFilter = 'All';

  // Map state
  final MapController _mapController = MapController();
  LatLng _mapCenter = const LatLng(20.5937, 78.9629); // India center default
  bool _mapReady = false;

  // Colors mapped to AppTheme
  final Color _bgColor = AppTheme.background;
  final Color _primaryColor = AppTheme.primary;
  final Color _textColor = AppTheme.textMain;
  final Color _textVariantColor = AppTheme.textVariant;
  final Color _outlineColor = AppTheme.outline;
  final Color _surfaceContainerLowest = AppTheme.surface;

  static const List<String> _sportFilters = [
    'All',
    'Football',
    'Cricket',
    'Basketball',
    'Tennis',
    'Swimming',
  ];

  @override
  void initState() {
    super.initState();
    _fetchAthletes();
  }

  /// Fetches athletes from Supabase.
  Future<void> _fetchAthletes() async {
    setState(() {
      isLoading = true;
      nearbyUsers = [];
      errorMessage = null;
    });

    Map<String, dynamic> currentUserData = {};
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
         final userData = await Supabase.instance.client.from('profiles').select('skill_level, stamina_level').eq('id', user.id).maybeSingle();
         if (userData != null) {
            currentUserData = userData;
         }
      }
    } catch (e) {
      debugPrint('Explore: error fetching current user profile $e');
    }

    if (kIsWeb) {
      await _fetchAllAthletes(currentUserData);
      return;
    }

    try {
      final geolocator = await _tryGetPosition();
      if (geolocator != null) {
        final lat = geolocator['lat'] as double;
        final lng = geolocator['lng'] as double;
        _mapCenter = LatLng(lat, lng);
        currentUserData['latitude'] = lat;
        currentUserData['longitude'] = lng;
        await _fetchNearbyViaRpc(lat, lng, currentUserData);
      } else {
        await _fetchAllAthletes(currentUserData);
      }
    } catch (e) {
      debugPrint('Explore: location error $e');
      await _fetchAllAthletes(currentUserData);
    }
  }

  Future<Map<String, double>?> _tryGetPosition() async {
    try {
      if (kIsWeb) return null;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return {'lat': pos.latitude, 'lng': pos.longitude};
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchNearbyViaRpc(double lat, double lng, Map<String, dynamic> currentUserData) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_nearby_users',
        params: {'user_lat': lat, 'user_lng': lng, 'radius_meters': 15000},
      );
      
      List<dynamic> fetchedUsers = response as List<dynamic>;
      
      if (fetchedUsers.isNotEmpty) {
        try {
          final userIds = fetchedUsers.map((u) => u['id']).toList();
          final scoresResponse = await Supabase.instance.client
              .from('profiles')
              .select('id, composite_score')
              .inFilter('id', userIds);
              
          final Map<String, dynamic> scoresMap = {
            for (var item in scoresResponse) item['id'].toString(): item['composite_score']
          };
          
          fetchedUsers = fetchedUsers.map((u) {
            final mappedUser = Map<String, dynamic>.from(u);
            mappedUser['composite_score'] = scoresMap[u['id'].toString()];
            return mappedUser;
          }).toList();
        } catch (e) {
          debugPrint('Error fetching composite scores: $e');
        }
      }

      fetchedUsers = MatchmakingService.sortAthletesByKNN(
        currentUser: currentUserData,
        athletes: fetchedUsers,
      );

      if (mounted) {
        setState(() {
          nearbyUsers = fetchedUsers;
          isLoading = false;
        });
      }
      _recenterMap();
    } catch (e) {
      debugPrint('RPC error: $e');
      await _fetchAllAthletes(currentUserData);
    }
  }

  Future<void> _fetchAllAthletes(Map<String, dynamic> currentUserData) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          // explicitly grab only valid columns
          .select('id, username, preferred_sport, avatar_url, skill_level, stamina_level, composite_score, lat, lng')
          .not('username', 'is', null)
          .limit(50);
          
      List<dynamic> fetchedUsers = (data as List<dynamic>)
          .map(
            (u) => {...u as Map<String, dynamic>, 'distance_meters': null},
          )
          .toList();

      fetchedUsers = MatchmakingService.sortAthletesByKNN(
        currentUser: currentUserData,
        athletes: fetchedUsers,
      );

      if (mounted) {
        setState(() {
          nearbyUsers = fetchedUsers;
          isLoading = false;
        });
      }
      _recenterMap();
    } catch (e) {
      debugPrint('Fetch all athletes error: $e');
      if (mounted)
        setState(() {
          errorMessage = 'Could not load athletes. Please try again.';
          isLoading = false;
        });
    }
  }

  void _recenterMap() {
    if (!mounted || !_mapReady) return;
    if (_filteredUsers.isNotEmpty) {
      for (var u in _filteredUsers) {
        final lat = _extractLat(u);
        final lng = _extractLng(u);
        if (lat != null && lng != null) {
          try {
            _mapController.move(LatLng(lat, lng), 11.0);
            return; // Center on first user found with location
          } catch (_) {}
        }
      }
    }
  }

  double? _extractLat(dynamic u) {
    if (u['lat'] != null) return double.tryParse(u['lat'].toString());
    if (u['latitude'] != null) return double.tryParse(u['latitude'].toString());
    return null;
  }

  double? _extractLng(dynamic u) {
    if (u['lng'] != null) return double.tryParse(u['lng'].toString());
    if (u['longitude'] != null)
      return double.tryParse(u['longitude'].toString());
    if (u['lon'] != null) return double.tryParse(u['lon'].toString());
    return null;
  }

  List<dynamic> get _filteredUsers {
    return nearbyUsers.where((u) {
      final name = (u['username'] ?? '').toString().toLowerCase();
      final sport = (u['preferred_sport'] ?? '').toString();
      final matchesSearch =
          _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchesSport =
          _selectedSportFilter == 'All' || sport == _selectedSportFilter;
      return matchesSearch && matchesSport;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;

    final Widget bodyContent = Stack(
      children: [
        // ── Map Background ──
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 14.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              onMapReady: () {
                setState(() => _mapReady = true);
                _recenterMap();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.notsoalone.app',
                maxZoom: 18,
              ),
              MarkerLayer(
                markers: users
                    .where((u) => _extractLat(u) != null && _extractLng(u) != null)
                    .map((u) {
                  final lat = _extractLat(u)!;
                  final lng = _extractLng(u)!;
                  final name = u['username']?.toString() ?? 'Athlete';
                  return Marker(
                    point: LatLng(lat, lng),
                    width: 60,
                    height: 60,
                    child: Tooltip(
                      message: name,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Tapped on $name')),
                          );
                          _mapController.move(LatLng(lat, lng), 15.0);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                              child: const Icon(Icons.person, color: Colors.white, size: 16),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                name.split(' ').first,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        // ── Floating UI (Search & Filters) Top ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surfaceContainerLowest.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                        _recenterMap();
                      },
                      decoration: InputDecoration(
                        hintText: 'Search athletes...',
                        hintStyle: TextStyle(
                          fontFamily: 'Manrope',
                          color: _outlineColor.withOpacity(0.6),
                        ),
                        prefixIcon: Icon(Icons.search, color: _outlineColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _sportFilters.length,
                    itemBuilder: (_, i) {
                      final f = _sportFilters[i];
                      final isSel = _selectedSportFilter == f;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedSportFilter = f);
                          _recenterMap();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel ? _primaryColor : _surfaceContainerLowest.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: isSel ? _primaryColor.withOpacity(0.3) : Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isSel ? Colors.white : _textVariantColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (kIsWeb)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Showing all athletes. Map shows users with location data.',
                            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Floating Recenter Map Button ──
        Positioned(
          right: 16,
          top: kIsWeb ? 180 : 130,
          child: FloatingActionButton.small(
            heroTag: 'recenter_map',
            backgroundColor: _surfaceContainerLowest,
            elevation: 4,
            onPressed: _recenterMap,
            child: Icon(Icons.my_location, color: _primaryColor),
          ),
        ),

        // ── Draggable Bottom Sheet for the List ──
        DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.15,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: _bgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2, offset: Offset(0, -2)),
                ],
              ),
              child: Column(
                children: [
                  // Drag indicator
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _outlineColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Nearby Athletes',
                          style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 18, color: _textColor),
                        ),
                        Text(
                          '${users.length} found',
                          style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: _textVariantColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildBody(users, scrollController)),
                ],
              ),
            );
          },
        ),
      ],
    );

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: _bgColor,
      // Hide AppBar as we are making Map Full Screen
      // appBar: AppBar( ... ), 
      body: bodyContent,
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildBody(List<dynamic> users, ScrollController scrollController) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: _primaryColor));
    }
    if (errorMessage != null) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, color: _textVariantColor, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _textVariantColor, fontSize: 16, fontFamily: 'Manrope'),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAthletes,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (users.isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, color: _textVariantColor, size: 64),
              const SizedBox(height: 16),
              Text(
                'No athletes found.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textVariantColor, fontSize: 16, fontFamily: 'Manrope'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: _fetchAthletes,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          final String username = user['username']?.toString() ?? 'Athlete';
          final String sport = user['preferred_sport']?.toString() ?? 'Any Sport';
          final dynamic distMeters = user['distance_meters'];
          final String distText = distMeters != null ? '${((distMeters as num) / 1000).toStringAsFixed(1)} km away' : '';
          final String? avatarUrl = user['avatar_url']?.toString();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.softShadow,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  final lat = _extractLat(user);
                  final lng = _extractLng(user);
                  if (lat != null && lng != null && _mapReady) {
                    _mapController.move(LatLng(lat, lng), 15.0);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _primaryColor.withOpacity(0.1),
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null ? Icon(Icons.person, color: _primaryColor, size: 28) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    username,
                                    style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 16, color: _textColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user['composite_score'] != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded, color: Colors.amber.shade700, size: 14),
                                        const SizedBox(width: 2),
                                        Text(
                                          (user['composite_score'] as num).toStringAsFixed(1),
                                          style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Manrope'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFE1F5FE), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                sport,
                                style: const TextStyle(color: Color(0xFF01579B), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (distText.isNotEmpty)
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: AppTheme.textVariant),
                                const SizedBox(width: 4),
                                Text(
                                  distText,
                                  style: const TextStyle(color: AppTheme.textVariant, fontSize: 13, fontFamily: 'Manrope'),
                                ),
                              ],
                            ),
                          if (distText.isNotEmpty) const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomScreen(
                                  matchId: user['id']?.toString() ?? username,
                                  matchTitle: username,
                                ),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: const Text(
                                'Message',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Manrope', fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgColor.withOpacity(0.9),
        border: Border(
          top: BorderSide(color: _outlineColor.withOpacity(0.1), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _primaryColor,
        unselectedItemColor: _textVariantColor,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Manrope',
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Manrope',
        ),
        currentIndex: 1,
        onTap: (index) {
          if (index == 0)
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const MainScreen(initialIndex: 0),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          else if (index == 2)
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const GroupChatsScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          else if (index == 3)
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const EditProfileScreen(),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
