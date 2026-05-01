import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_room_screen.dart';
import 'create_group_screen.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  State<GroupChatsScreen> createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen>
    with SingleTickerProviderStateMixin {
  final Color _bgColor = AppTheme.background;
  final Color _primaryColor = AppTheme.primary;
  final Color _primaryDim = AppTheme.accentGradientEnd;
  final Color _textColor = AppTheme.textMain;
  final Color _textVariantColor = AppTheme.textVariant;
  final Color _surfaceContainer = AppTheme.surfaceContainer;
  final Color _surfaceContainerLowest = AppTheme.surface;
  final Color _outlineVariant = const Color(0xFFA6AAD7);

  late TabController _tabController;
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _allGroups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1) Fetch group IDs this user is a member of
      final memberRows = await Supabase.instance.client
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId);

      final joinedIds = (memberRows as List<dynamic>)
          .map((r) => r['group_id'].toString())
          .toSet();

      // 2) Fetch ALL groups
      final allData = await Supabase.instance.client
          .from('group_chats')
          .select('id, name, sport, description, created_at')
          .order('created_at', ascending: false)
          .limit(100);

      final allList = List<Map<String, dynamic>>.from(allData as List);

      // 3) Split into my groups vs discoverable groups
      final myList = allList
          .where((g) => joinedIds.contains(g['id'].toString()))
          .toList();
      final discoverList = allList
          .where((g) => !joinedIds.contains(g['id'].toString()))
          .toList();

      if (!mounted) return;
      setState(() {
        _myGroups = myList;
        _allGroups = discoverList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching groups: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinGroup(Map<String, dynamic> group) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final groupId = group['id'].toString();

    try {
      await Supabase.instance.client
          .from('group_members')
          .insert({'group_id': groupId, 'user_id': userId});

      NotificationService.addJoinedGroup(groupId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined "${group['name']}" ✓'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchData();
    } catch (e) {
      debugPrint('Join error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _leaveGroup(Map<String, dynamic> group) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final groupId = group['id'].toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Leave Group',
            style: TextStyle(
                fontFamily: 'Lexend', fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to leave "${group['name']}"?',
          style: const TextStyle(fontFamily: 'Manrope'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);

      NotificationService.removeJoinedGroup(groupId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Left "${group['name']}"'),
          backgroundColor: Colors.orange,
        ),
      );
      _fetchData();
    } catch (e) {
      debugPrint('Leave error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to leave: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _getSportIcon(String? sport) {
    switch (sport?.toLowerCase()) {
      case 'soccer':
      case 'football':
        return Icons.sports_soccer;
      case 'cricket':
        return Icons.sports_cricket;
      case 'basketball':
        return Icons.sports_basketball;
      case 'tennis':
      case 'badminton':
        return Icons.sports_tennis;
      case 'volleyball':
        return Icons.sports_volleyball;
      case 'handball':
        return Icons.sports_handball;
      case 'kabaddi':
        return Icons.sports_kabaddi;
      case 'training':
        return Icons.fitness_center;
      default:
        return Icons.sports;
    }
  }

  Color _getSportColor(String? sport) {
    switch (sport?.toLowerCase()) {
      case 'soccer':
      case 'football':
        return const Color(0xFF0052D0);
      case 'cricket':
        return const Color(0xFFA33800);
      case 'basketball':
        return const Color(0xFF8D3A8B);
      case 'tennis':
      case 'badminton':
        return const Color(0xFF00796B);
      case 'volleyball':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: _textVariantColor,
                labelStyle: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'My Groups'),
                  Tab(text: 'Discover'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: My Groups
                  RefreshIndicator(
                    onRefresh: _fetchData,
                    color: _primaryColor,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _myGroups.isEmpty
                            ? _buildEmptyJoined()
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 120),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: _buildHeroSection(context),
                                  ),
                                  const SizedBox(height: 24),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    child: Text(
                                      'Your Groups',
                                      style: TextStyle(
                                        color: _textColor,
                                        fontFamily: 'Lexend',
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._myGroups.map(
                                      (g) => _buildGroupTile(g, joined: true)),
                                ],
                              ),
                  ),

                  // Tab 2: Discover (groups you haven't joined)
                  RefreshIndicator(
                    onRefresh: _fetchData,
                    color: _primaryColor,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _allGroups.isEmpty
                            ? _buildEmptyDiscover()
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                    top: 16, bottom: 120),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 8),
                                    child: Text(
                                      'Groups you can join',
                                      style: TextStyle(
                                        color: _textColor,
                                        fontFamily: 'Lexend',
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ..._allGroups.map(
                                      (g) => _buildGroupTile(g, joined: false)),
                                ],
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateGroupScreen(),
              ),
            );
            _fetchData();
          },
          backgroundColor: _primaryColor,
          shape: const CircleBorder(),
          elevation: 8,
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: _bgColor.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sports Community',
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Lexend',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryColor, _primaryDim],
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connect with Athletes',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Lexend',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a conversation and organize your next match in minutes.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontFamily: 'Manrope',
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateGroupScreen(),
                    ),
                  );
                  _fetchData();
                },
                icon: const Icon(
                  Icons.add_circle,
                  color: Color(0xFF0052D0),
                  size: 20,
                ),
                label: const Text(
                  'Create sports-specific chat groups',
                  style: TextStyle(
                    color: Color(0xFF0052D0),
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  elevation: 4,
                ),
              ),
            ],
          ),
          Positioned(
            right: -40,
            bottom: -40,
            child: Transform.rotate(
              angle: 12 * 3.14159 / 180,
              child: Icon(
                Icons.groups,
                color: Colors.white.withOpacity(0.2),
                size: 150,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyJoined() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.forum_outlined,
                  size: 56, color: _textVariantColor.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text(
                'No groups yet',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a group or check the Discover tab to join one!',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: _textVariantColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.explore),
                label: const Text('Discover Groups'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: BorderSide(color: _primaryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDiscover() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off,
                  size: 56, color: _textVariantColor.withOpacity(0.4)),
              const SizedBox(height: 16),
              Text(
                'No new groups to discover',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve joined all available groups, or no new ones have been created yet.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  color: _textVariantColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group,
      {required bool joined}) {
    final groupId = group['id']?.toString() ?? '';
    final name = group['name'] ?? 'Unnamed Group';
    final sport = group['sport'] ?? '';
    final description = group['description'] ?? '';
    final sportColor = _getSportColor(sport);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: joined
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatRoomScreen(
                      matchId: groupId,
                      matchTitle: name,
                    ),
                  ),
                );
              }
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Sport icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: sportColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_getSportIcon(sport),
                    color: sportColor, size: 28),
              ),
              const SizedBox(width: 16),
              // Group info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: _textColor,
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description.isNotEmpty ? description : sport,
                      style: TextStyle(
                        color: _textVariantColor,
                        fontFamily: 'Manrope',
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: sportColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        sport,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sportColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action button: Join or Leave
              if (joined)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Leave button
                    GestureDetector(
                      onTap: () => _leaveGroup(group),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.exit_to_app,
                            color: Colors.red, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: _outlineVariant),
                  ],
                )
              else
                // Join button
                GestureDetector(
                  onTap: () => _joinGroup(group),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryColor.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Join',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
