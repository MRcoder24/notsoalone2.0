import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'all_sports_screen.dart';
import 'group_chats_screen.dart';
import 'venue_details_screen.dart';
import 'edit_profile_screen.dart';
import 'create_event_screen.dart';
import 'medical_id_screen.dart';

import '../services/supabase_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/radar_map.dart';
import '../widgets/location_search.dart';
import 'package:latlong2/latlong.dart';
import '../services/upi_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final Color _bgColor = AppTheme.background;
  final Color _primaryColor = AppTheme.primary;
  final Color _textColor = AppTheme.textMain;
  final Color _textVariantColor = AppTheme.textVariant;
  final Color _surfaceContainer = AppTheme.surfaceContainer;
  final Color _surfaceContainerLowest = AppTheme.surface;
  final Color _surfaceContainerHigh = AppTheme.primaryLight;
  final Color _outlineColor = AppTheme.outline;

  late TabController _tabController;
  bool _showFab = true;

  // User profile state
  String _userName = '';
  String? _userAvatarUrl;
  String _userLocation = 'Loading...';

  // Radar state
  List<dynamic> _nearbyUsers = [];
  bool _radarLoading = true;
  String? _radarError;

  // Joined matches state
  Set<String> _joinedMatchIds = {};
  Map<String, dynamic>? _rawProfileData;
  final ValueNotifier<LatLng?> _locationFocusNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _showFab = _tabController.index == 0;
      });
    });
    LocationService.syncCurrentLocation();
    NotificationService.init();
    NotificationService.startListening();
    NotificationService.startGroupChatListener();
    _fetchNearbyAthletes();
    _fetchJoinedMatches();
    _loadUserProfile();
    _loadCurrentLocation();
  }

  Future<void> _fetchJoinedMatches() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final response = await Supabase.instance.client
          .from('match_participants')
          .select('match_id')
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          _joinedMatchIds = (response as List)
              .map((item) => item['match_id'].toString())
              .toSet();
        });
      }
    } catch (e) {
      debugPrint('Error fetching joined matches: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchNearbyAthletes() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _radarError = 'Location services are disabled.';
          _radarLoading = false;
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _radarError = 'Location permission denied.';
            _radarLoading = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _radarError = 'Location permission permanently denied.';
          _radarLoading = false;
        });
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final response = await Supabase.instance.client.rpc(
        'get_nearby_users',
        params: {
          'user_lat': pos.latitude,
          'user_lng': pos.longitude,
          'radius_meters': 15000,
        },
      );
      setState(() {
        _nearbyUsers = response as List<dynamic>;
        _radarLoading = false;
      });
    } catch (e) {
      debugPrint('Radar fetch error: $e');
      setState(() {
        _radarError = 'Could not load nearby athletes.';
        _radarLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          title: _buildHeader(),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: _primaryColor,
            labelColor: _primaryColor,
            unselectedLabelColor: _textVariantColor,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Manrope',
            ),
            tabs: const [
              Tab(text: 'Live Matches'),
              Tab(text: 'Local Radar'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // ── Tab 1: Live Matches ──
            _buildMatchFeedTab(),
            // ── Tab 2: Local Radar ──
            _buildRadarTab(),
          ],
        ),
        floatingActionButton: _showFab
            ? Container(
                margin: const EdgeInsets.only(bottom: 80),
                child: FloatingActionButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateEventScreen(),
                      ),
                    );
                  },
                  backgroundColor: AppTheme.primary,
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.add, color: Colors.white, size: 32),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildMatchFeedTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildGreeting(),
                const SizedBox(height: 16),
                _buildSearchBar(),
                const SizedBox(height: 16),
                RadarMapWidget(locationFocusNotifier: _locationFocusNotifier),
                const SizedBox(height: 16),
              ],
            ),
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('matches')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF0052D0)),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No matches happening right now. Hit the + button to host one!',
                      ),
                    ),
                  );
                }
                final matches = snapshot.data!;
                return SliverPadding(
                  padding: const EdgeInsets.only(bottom: 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final match = matches[index];
                    final title = match['title'] ?? 'Untitled';
                    final sport = match['sport'] ?? 'Unknown Sport';
                    final location = match['location'] ?? 'Unknown Location';
                    final int maxPlayers = match['max_players'] ?? 100;
                    final int joinedPlayers = match['joined_players'] ?? 0;
                    final bool isFull = joinedPlayers >= maxPlayers;
                    final String? imageUrl = match['image_url'] as String?;

                    // ── Parse extra info from description JSON ──
                    bool isPaid = false;
                    String entryAmount = '0';
                    String description = '';
                    String orgName = '';
                    String orgPhone = '';
                    String orgEmail = '';
                    String playgroundOwner = '';
                    DateTime? endTime;

                    try {
                      final rawDesc = match['description'];
                      if (rawDesc != null && rawDesc.toString().isNotEmpty) {
                        final desc = jsonDecode(rawDesc.toString()) as Map<String, dynamic>;
                        description = (desc['text'] ?? '').toString();
                        isPaid = desc['is_paid'] == true;
                        entryAmount = (desc['amount'] ?? '0').toString();
                        orgName = (desc['org_name'] ?? '').toString();
                        orgPhone = (desc['org_phone'] ?? '').toString();
                        orgEmail = (desc['org_email'] ?? '').toString();
                        playgroundOwner = (desc['owner'] ?? '').toString();
                        if (desc['end_time'] != null) {
                          endTime = DateTime.parse(desc['end_time'].toString());
                        }
                      }
                    } catch (_) {}

                    // ── Status Logic (Live Today / Live Now) ──
                    final DateTime now = DateTime.now();
                    DateTime? eventDate;
                    try {
                      if (match['event_date'] != null) {
                        eventDate = DateTime.parse(match['event_date'].toString());
                      }
                    } catch (_) {}

                    bool isToday = false;
                    bool isLiveNow = false;
                    if (eventDate != null) {
                      isToday = eventDate.year == now.year && eventDate.month == now.month && eventDate.day == now.day;
                      if (endTime != null) {
                        isLiveNow = now.isAfter(eventDate) && now.isBefore(endTime);
                      } else {
                        // Fallback: Live if within 2 hours of start
                        isLiveNow = now.isAfter(eventDate) && now.isBefore(eventDate.add(const Duration(hours: 2)));
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: _surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppTheme.dropShadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Image header ──
                          Stack(
                            children: [
                              if (imageUrl != null && imageUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                  child: Image.network(
                                    imageUrl,
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        height: 180,
                                        color: Colors.grey[200],
                                        child: const Center(child: CircularProgressIndicator(color: Color(0xFF0052D0))),
                                      );
                                    },
                                    errorBuilder: (_, _, _) => Container(height: 180, color: Colors.grey[200], child: const Icon(Icons.broken_image, color: Colors.grey)),
                                  ),
                                )
                              else
                                Container(height: 120, decoration: BoxDecoration(gradient: LinearGradient(colors: [_primaryColor.withOpacity(0.1), _primaryColor.withOpacity(0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                              
                              // Live / Today Badge
                              if (isLiveNow)
                                Positioned(top: 16, right: 16, child: _buildLiveBadge(isLive: true))
                              else if (isToday)
                                Positioned(top: 16, right: 16, child: _buildLiveBadge(isLive: false)),
                            ],
                          ),
                          
                          // ── Text content ──
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title row + sport badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          color: _textColor,
                                          fontFamily: 'Lexend',
                                        ),
                                      ),
                                    ),
                                    _buildSportBadge(sport, isPaid, entryAmount),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // Location row
                                Row(
                                  children: [
                                    Icon(Icons.location_on, size: 16, color: _primaryColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: TextStyle(color: _textVariantColor, fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    if (eventDate != null)
                                      Text(
                                        "${eventDate.hour}:${eventDate.minute.toString().padLeft(2, '0')} ${eventDate.hour >= 12 ? 'PM' : 'AM'}",
                                        style: TextStyle(color: _primaryColor, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                                
                                // ── Match Description ──
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    description,
                                    style: TextStyle(color: _textColor.withOpacity(0.85), fontSize: 13, height: 1.4),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                
                                const Divider(height: 32, thickness: 1),
                                
                                // ── Organizer & Playground Details ──
                                if (orgName.isNotEmpty || playgroundOwner.isNotEmpty) ...[
                                  Text('ORGANIZER DETAILS', style: TextStyle(color: _textVariantColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  const SizedBox(height: 12),
                                  if (orgName.isNotEmpty)
                                    _buildDetailRow(Icons.person, orgName, label: 'Organizer'),
                                  if (playgroundOwner.isNotEmpty)
                                    _buildDetailRow(Icons.business, playgroundOwner, label: 'Playground Manager'),
                                  
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (orgPhone.isNotEmpty)
                                        Expanded(child: _buildContactButton(Icons.phone, 'Call', () => _launchURL('tel:$orgPhone'))),
                                      if (orgPhone.isNotEmpty && orgEmail.isNotEmpty)
                                        const SizedBox(width: 8),
                                      if (orgEmail.isNotEmpty)
                                        Expanded(child: _buildContactButton(Icons.email, 'Email', () => _launchURL('mailto:$orgEmail'))),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // ── Join button with inline player count ──
                                Builder(
                                  builder: (context) {
                                    final matchId = match['id'].toString();
                                    final isJoined = _joinedMatchIds.contains(matchId);
                                    final bool isClosed = eventDate != null && now.isAfter(eventDate) && !isLiveNow;

                                    // Formatted player string based on maxPlayers
                                    final playersStr = (maxPlayers <= 0 || maxPlayers == 100) 
                                        ? '$joinedPlayers joined' 
                                        : '$joinedPlayers/$maxPlayers';
                                    
                                    // Determine button color
                                    final Color btnColor = isClosed
                                        ? Colors.grey.shade600
                                        : isFull
                                            ? Colors.grey.shade400
                                            : isJoined
                                                ? Colors.green.shade500
                                                : _primaryColor;
                                            
                                    // Determine button label
                                    final String btnLabel = isClosed
                                        ? 'Event Closed'
                                        : isFull
                                            ? 'Match Full'
                                            : isJoined
                                                ? '✓ Joined • $playersStr'
                                                : isPaid
                                                    ? 'Pay & Join • $playersStr'
                                                    : 'Join Match • $playersStr';

                                    return SizedBox(
                                      width: double.infinity,
                                      height: 56,
                                      child: ElevatedButton(
                                        onPressed: (isJoined || isFull || isClosed)
                                            ? null
                                            : () async {
                                                if (isPaid && entryAmount != '0' && entryAmount.isNotEmpty) {
                                                  await UpiService.launchUPI(context, entryAmount);
                                                }
                                                // Call joinMatch logic
                                                try {
                                                  await SupabaseService().joinMatch(matchId);
                                                  _fetchJoinedMatches();
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Join failed: $e'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: btnColor,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: btnColor.withOpacity(0.6),
                                          disabledForegroundColor: Colors.white70,
                                          elevation: (isJoined || isFull || isClosed) ? 0 : 2,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          btnLabel,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                        ],
                      ),
                    );
                  },
                  childCount: matches.length,
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

  Widget _buildRadarTab() {
    if (_radarLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0052D0)),
      );
    }
    if (_radarError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, color: _textVariantColor, size: 48),
              const SizedBox(height: 16),
              Text(
                _radarError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: _textVariantColor, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _radarLoading = true;
                    _radarError = null;
                  });
                  _fetchNearbyAthletes();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_nearbyUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, color: _textVariantColor, size: 64),
              const SizedBox(height: 16),
              Text(
                'No athletes found within 15km of your location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textVariantColor,
                  fontSize: 16,
                  fontFamily: 'Manrope',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: () async {
        setState(() {
          _radarLoading = true;
          _nearbyUsers = [];
        });
        await _fetchNearbyAthletes();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _nearbyUsers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.notifications_active, color: AppTheme.primary),
                title: const Text(
                  'Test Notification ⚡',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Tap to fire a local alert'),
                onTap: () {
                  NotificationService.showNotification(
                    'Victory Alert! 🏆',
                    'The notification engine is now online and active.',
                  );
                },
              ),
            ),
          );
          }
          final user = _nearbyUsers[index - 1];
          final String username = user['username'] ?? 'Unknown Athlete';
          final String sport = user['preferred_sport'] ?? 'Any Sport';
          final double distanceKm = (user['distance_meters'] as num) / 1000;
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.softShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person, color: _primaryColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE1F5FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            sport,
                            style: const TextStyle(
                              color: Color(0xFF01579B),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: _textVariantColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${distanceKm.toStringAsFixed(1)} km away',
                        style: TextStyle(
                          color: _textVariantColor,
                          fontSize: 13,
                          fontFamily: 'Manrope',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final displayName = _userName.isNotEmpty ? _userName : 'Player';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              GestureDetector(
                onTap: _showSosDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      fontFamily: 'Lexend',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hey $displayName!',
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Icon(Icons.location_on, color: _primaryColor, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _userLocation,
                            style: TextStyle(
                              color: _textVariantColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.notifications_outlined, color: _textColor, size: 28),
          ],
        ),
      ],
    );
  }

  void _showSosDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 10),
            Text('EMERGENCY SOS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Who should we call?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            _buildSosAction(
              icon: Icons.medical_information_rounded,
              label: 'Medical ID',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _showMedicalIdDialog();
              },
            ),
            const SizedBox(height: 12),
            _buildSosAction(
              icon: Icons.local_hospital_rounded,
              label: 'Call Ambulance (102)',
              color: Colors.red,
              onTap: () => _launchCaller('102'),
            ),
            const SizedBox(height: 12),
            _buildSosAction(
              icon: Icons.local_police_rounded,
              label: 'Call Police (100)',
              color: Colors.blue,
              onTap: () => _launchCaller('100'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _showMedicalIdDialog() {
    final medical = _rawProfileData?['medical_data'] as Map<String, dynamic>? ?? {};
    final fullName = _userName.isNotEmpty ? _userName : 'Athlete';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.health_and_safety, color: Colors.white, size: 40),
                    SizedBox(height: 8),
                    Text('EMERGENCY MEDICAL ID', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildMedicalRow('Full Name', fullName, Icons.person),
                      _buildMedicalRow('Blood Group', medical['blood_group'] ?? 'Not Set', Icons.bloodtype, isAlert: true),
                      _buildMedicalRow('Emergency SOS', medical['emergency_contact'] ?? 'Not Set', Icons.phone, isEmergency: true),
                      _buildMedicalRow('Conditions', medical['medical_conditions'] ?? 'None Reported', Icons.medical_information),
                      _buildMedicalRow('Address', medical['address'] ?? 'Not Available', Icons.location_on),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MedicalIdScreen()),
                          ).then((refreshed) {
                            if (refreshed == true) _loadUserProfile();
                          });
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.redAccent),
                        label: const Text(
                          'Edit Medical ID',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedicalRow(String label, String value, IconData icon, {bool isAlert = false, bool isEmergency = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: isAlert || isEmergency ? Colors.redAccent : Colors.grey[400], size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w800)),
                Text(value.isEmpty ? 'Not Set' : value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isEmergency ? Colors.redAccent : Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosAction({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _launchCaller(String number) async {
    final Uri url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  // ── Load user profile from Supabase ──
  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _userName = (data['full_name'] ?? data['username'] ?? '').toString();
          _userAvatarUrl = data.containsKey('avatar_url') ? data['avatar_url'] : null;
          _rawProfileData = data;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  // ── Load real-time GPS location ──
  Future<void> _loadCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _userLocation = 'Location off');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _userLocation = 'Permission denied');
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          final locality = p.subLocality?.isNotEmpty == true ? p.subLocality : p.locality;
          setState(() => _userLocation = locality ?? '${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)}');
        }
      } catch (e) {
        if (mounted) setState(() => _userLocation = '${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)}');
      }
    } catch (e) {
      if (mounted) setState(() => _userLocation = 'Unavailable');
    }
  }

  // ── Show upcoming scheduled events ──
  void _showScheduledEvents() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Upcoming Events', style: TextStyle(fontFamily: 'Lexend', fontSize: 20, fontWeight: FontWeight.bold, color: _textColor)),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder(
                future: _fetchUserEvents(),
                builder: (context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy, size: 64, color: _textVariantColor),
                          const SizedBox(height: 16),
                          Text('No upcoming events', style: TextStyle(color: _textVariantColor, fontSize: 16)),
                        ],
                      ),
                    );
                  }
                  final events = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.sports, color: _primaryColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(event['title'] ?? 'Event', style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
                                  const SizedBox(height: 4),
                                  Text(event['location'] ?? '', style: TextStyle(color: _textVariantColor, fontSize: 12)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                              child: Text(event['sport'] ?? '', style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchUserEvents() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return [];
      final response = await Supabase.instance.client
          .from('match_participants')
          .select('match_id, matches(title, sport, location, created_at)')
          .eq('user_id', user.id);
      return List<Map<String, dynamic>>.from(
        (response as List).map((item) => item['matches'] ?? item),
      );
    } catch (e) {
      debugPrint('Error fetching user events: $e');
      return [];
    }
  }

  ImageProvider _getAvatarProvider(String? url) {
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
    return const NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuAU_g7AZTKk4C0YUpsYbU0e2jhfQN7SWIWh1L2Ofa2YMvnNsTQiMlq0uPUNdFYc59UZhmWXFHtcIkB_5fE5Hfw8MUUZsUkWKhjFFlZs6HQHJCrf1aCxeG8o0IFIcN7UlVmnp99LETsACPSxumAhh9pC_h6w7krNFuYrB_-URamZkglH-ucsDQdsrnPkfJ82MDXa2YoMAfe13kK9mA2vYcqbUsFVFavBr2j3ALPZqCiwo3qJwp3_zLA2oMVywW0YOC1JTuCBwU9CmrU');
  }

  Widget _buildGreeting() {
    final displayName = _userName.isNotEmpty ? _userName : 'Champ';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _primaryColor, width: 2),
                      image: DecorationImage(
                        image: _getAvatarProvider(_userAvatarUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: _bgColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hey $displayName!',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, color: _textVariantColor, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _userLocation,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _textVariantColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                // Navigate to Chats tab
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupChatsScreen()));
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: _primaryColor,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showScheduledEvents,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.calendar_today_outlined,
                  color: _primaryColor,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return LocationSearchWidget(
      onLocationSelected: (lat, lng) {
        _locationFocusNotifier.value = LatLng(lat, lng);
      },
    );
  }

  Widget _buildMapWidget() {
    return Container(
      height: 256,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: NetworkImage(
            'https://lh3.googleusercontent.com/aida-public/AB6AXuCcrEd5q3EMJMrF287pE6m8BmWnxlpPQ4cw9iSyxXXgADItnfo6BG6iXziwTz-gm-v9KesdZuOfJAm9XHwx_vPMdEJ_AmiCCA7xTV9Ol92Ed4XBdoxqF4FfRWYYdd5DKsckqepQzSaEPBmv6ZhGbg5TJJJbc2G5FZYjNAbqCKKm5iWJpCLUiRfK2yN6wtfBwb58xo8LBDQU17HMLR0LeQ92YL1yR9-GZmktneO-CzwJOD9CVqQIlkbnloXluVVf3QLSZJUa1iKXLJw',
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [_textColor.withOpacity(0.4), Colors.transparent],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Current location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: Icon(Icons.filter_list, size: 18, color: _textColor),
              label: Text('Filter', style: TextStyle(color: _textColor)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          Positioned(
            top: 128,
            left: 100,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFA33800), // secondary
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Icon(
                Icons.sports_soccer,
                color: Color(0xFFFFEFEB),
                size: 16,
              ),
            ),
          ),
          Positioned(
            top: 64,
            right: 64,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF8D3A8B), // tertiary
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Icon(
                Icons.sports_tennis,
                color: Color(0xFFFFEEF8),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportsList() {
    final sports = [
      {'name': 'Cricket', 'icon': Icons.sports_cricket, 'active': false},
      {'name': 'Basketball', 'icon': Icons.sports_basketball, 'active': true},
      {'name': 'Football', 'icon': Icons.sports_soccer, 'active': false},
      {'name': 'Tennis', 'icon': Icons.sports_tennis, 'active': false},
      {'name': 'Gym', 'icon': Icons.fitness_center, 'active': false},
      {'name': 'Swimming', 'icon': Icons.pool, 'active': false},
      {'name': 'Kabaddi', 'icon': Icons.sports_kabaddi, 'active': false},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Games by Sports',
              style: TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'See All',
              style: TextStyle(
                color: _primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: sports.map((sport) {
              final active = sport['active'] as bool;
              return Padding(
                padding: const EdgeInsets.only(right: 24.0),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFFFC4AF)
                            : _surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        sport['icon'] as IconData,
                        color: active
                            ? const Color(0xFF812B00)
                            : const Color(0xFF0047B7),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sport['name'] as String,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildVenuesList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Go-To Venues',
          style: TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildVenueCard(
                context,
                name: 'Greenfield Arena',
                location: 'Boring Road, Patna',
                rating: '4.8',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuBAn6SqsJ3Mcc2d5zuwIW7SFEGCb4iN4ly3A4wHETsPNezkNCRxXBT6I9kAUbUOfheLmcayTmmOS7wW-_pPoWU0ZPGnXbKem1pJAss0SbM792Dk0mCNEd7t9Ccoojj2nmrOab638Ivw-ru4rXrK8v0uN0ClSFZzpUByhcNHDG4uLUbyRvCGRVmZ669mNkzYS6cDrsscpvpCfj6Fo8il6wbZmo1MnAqE63yJWxi43xTFqAPMqBUlkgWrzLJ7ozlzMwzRezp6My2sLkQ',
              ),
              const SizedBox(width: 16),
              _buildVenueCard(
                context,
                name: 'The Smash Club',
                location: 'Kankarbagh, Patna',
                rating: '4.5',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuAT_2LHat7EsHEgiC18Ze48IN6o07KBiN1JTRXTjn3z35FnB0GGOCnjby8MahRyVgMca5iieaF9Wa4mnnRDEfjGNHu7nbkIMMEawn8ODemJmeGVMF1ftlZKbR1Xt60UB1gPRI6yfB7m5fn6l-5c2_zI6Pfam_E3l1r9QrM8ijzflcTNv_aGNZ8KXmL2ON9jfMAUNGDrOH0tnKr3CcO2HTgi4MvGzobZhzMKaMDjsessw88mWNQB2LpqbgDV2n-gqJDW-5lAbHNncY',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVenueCard(
    BuildContext context, {
    required String name,
    required String location,
    required String rating,
    required String imageUrl,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const VenueDetailsScreen()),
        );
      },
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: _surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _surfaceContainerLowest.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star,
                            color: Color(0xFFA33800),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating,
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: _textVariantColor,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        location,
                        style: TextStyle(
                          color: _textVariantColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Events',
          style: TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: SupabaseService().getMatches(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }

            final matches = snapshot.data ?? [];
            if (matches.isEmpty) {
              return const Text('No upcoming events found.');
            }

            // For now, let's just show the first match
            final match = matches.first;
            final sport = match['sport'] ?? 'Unknown Sport';
            final time = match['time'] ?? 'TBD';
            final title = match['title'] ?? '$sport Match';
            final location = match['location'] ?? 'TBD';

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(
                        Icons.sports_basketball,
                        color: Colors.white70,
                        size: 40,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          time
                              .toString()
                              .toUpperCase(), // Or use a Date formatting logic
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 32,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildAvatar(
                              'https://lh3.googleusercontent.com/aida-public/AB6AXuAPY6nyz6g8RN2yvIPsNNcrWHZj-hJiHix_lJimXfR8hV2Tpq7s7sBJUdRCnE7KEXZ-PBx_zroyaTtCrTg_tqGln0FZ0no0RbzGe5OZ8nehw4pI_lWJ9YtAYyGKAvrJOX2BroeMuuxitg7NK--B93Mz0bkesLXiPaPwggLBQvh0iXj3sX85v52adWv0OQie3WSpyHMs5BmR3Nc18Yhls9UzxL6UEDkAC8KN_ZD95I1z0IPR1uCNuF8vxJKv6on1jagbsf1cR9A_Yy8',
                              0,
                            ),
                            _buildAvatar(
                              'https://lh3.googleusercontent.com/aida-public/AB6AXuCmT9dCvS6nvVMwu_pjWYd8gmfeNOYWTGi9ipMjwvoPvv6m2aJ5uClQ3mql-u1AtZZOKDEzErBnYLl8RfGihJCQsn7iu-ewEzUzsSugthHh_O06vFdoZi1408z0UJjmILuV9pP1v4G9BK2NrWHcYlBMch9Jt4NMwMT6BvX6YHXpgpbLjz5HKJIj3jOJ_sVQsiF0eEE8l-mWc4c8jTQUZeCep8S7oHY0_-TjQyhFA3fW-tgn3_QQQUDKryuaBSopiaOjUkoHaa3PmLA',
                              20,
                            ),
                            _buildAvatar(
                              'https://lh3.googleusercontent.com/aida-public/AB6AXuCi6RUEru2BVPI94aR18oQVWugcjIe435AQtQKE-dc2Sue3fksXf8hEAqT_R2DeGBRFd8K8oH5AsJPtkIQSfXk_kgGghyCFf_9dF1Vy_kggTAu4PxO-Wpu5hWylXriY4lrbLQLYTWzQu3AqlBohvOaNiaH-bsQKGEkF63-Xsco1EvMCJWW2iuCecOitcuopoe3xWNwVw4nF4DoU-XJ9snUfrVDmHOaS7-miqE4fs76b891D7pTRxpXI_mLMNvW4gjTUpnTMmQOI7ro',
                              40,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Join match',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAvatar(String url, double leftMargin) {
    return Positioned(
      left: leftMargin,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _primaryColor, width: 2),
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      ),
    );
  }



  Widget _buildLiveBadge({required bool isLive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLive ? Colors.red : Colors.orange,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isLive ? Colors.red : Colors.orange).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            const Padding(
              padding: EdgeInsets.only(right: 6.0),
              child: Icon(Icons.circle, size: 8, color: Colors.white),
            ),
          Text(
            isLive ? 'LIVE NOW' : 'LIVE TODAY',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportBadge(String sport, bool isPaid, String entryAmount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPaid) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_rupee, size: 14, color: Colors.orange),
                Text(
                  entryAmount,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            sport.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String value, {required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: _primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: TextStyle(color: _textVariantColor, fontSize: 9, fontWeight: FontWeight.bold)),
                Text(
                  value,
                  style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _primaryColor.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: _primaryColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: _primaryColor, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      debugPrint('Could not launch \$urlString');
    }
  }
}
