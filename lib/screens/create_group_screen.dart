import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_room_screen.dart';

const List<Map<String, dynamic>> _sportOptions = [
  {'icon': Icons.sports_soccer, 'label': 'Soccer'},
  {'icon': Icons.sports_basketball, 'label': 'Basketball'},
  {'icon': Icons.sports_tennis, 'label': 'Tennis'},
  {'icon': Icons.fitness_center, 'label': 'Training'},
  {'icon': Icons.sports_cricket, 'label': 'Cricket'},
  {'icon': Icons.sports_volleyball, 'label': 'Volleyball'},
  {'icon': Icons.sports_handball, 'label': 'Handball'},
  {'icon': Icons.sports_kabaddi, 'label': 'Kabaddi'},
];

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  // Colors
  final Color _bgColor = const Color(0xFFF8F5FF);
  final Color _primaryColor = const Color(0xFF0052D0);
  final Color _secondaryContainer = const Color(0xFFFFC4AF);
  final Color _onSecondaryContainer = const Color(0xFF812B00);
  final Color _surfaceContainerLowest = const Color(0xFFFFFFFF);
  final Color _surfaceContainerHighest = const Color(0xFFD8DAFF);
  final Color _onSurface = const Color(0xFF272B51);
  final Color _onSurfaceVariant = const Color(0xFF545881);
  final Color _outline = const Color(0xFF70749E);
  final Color _outlineVariant = const Color(0xFFA6AAD7);

  // State
  Uint8List? _iconBytes;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  String _selectedSport = 'Soccer';
  final Set<String> _selectedMemberIds = {};
  bool _isCreating = false;

  // Real users from Supabase
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, username, avatar_url')
          .limit(50);

      if (!mounted) return;
      final users = List<Map<String, dynamic>>.from(data as List)
          .where((u) => u['id'] != currentUserId)
          .toList();

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoadingUsers = false;
      });
    } catch (e) {
      debugPrint('Error fetching users: $e');
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers
            .where((u) => (u['username'] ?? '')
                .toString()
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _pickIcon() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null && mounted) {
      final bytes = await img.readAsBytes();
      setState(() => _iconBytes = bytes);
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name.'), backgroundColor: Colors.red),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Create the group record in Supabase
      final response = await Supabase.instance.client.from('group_chats').insert({
        'name': name,
        'sport': _selectedSport,
        'description': _descriptionController.text.trim(),
        'created_by': user.id,
      }).select('id, name').single();

      final groupId = response['id']?.toString() ?? '';

      if (groupId.isEmpty) throw Exception('Failed to get group ID');

      // Add members to group_members table
      final List<Map<String, dynamic>> membersToInsert = [
        {'group_id': groupId, 'user_id': user.id}, // Add the creator
        ..._selectedMemberIds.map((uid) => {'group_id': groupId, 'user_id': uid}),
      ];

      await Supabase.instance.client.from('group_members').insert(membersToInsert);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group created with members! ✓'), backgroundColor: Colors.green),
      );

      // Navigate to the new chat room
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(matchId: groupId, matchTitle: name),
        ),
      );
    } catch (e) {
      debugPrint('Create group error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create group: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}…' : e}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor.withOpacity(0.7),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Create Group', style: TextStyle(color: _onSurface, fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Icon
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickIcon,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            color: _surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(color: _surfaceContainerLowest, width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                            image: _iconBytes != null
                                ? DecorationImage(image: MemoryImage(_iconBytes!), fit: BoxFit.cover)
                                : null,
                          ),
                          child: _iconBytes == null
                              ? Center(child: Icon(Icons.groups, size: 48, color: _onSurfaceVariant))
                              : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: _bgColor, width: 4),
                            ),
                            child: const Icon(Icons.photo_camera, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Tap to add group icon', style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w500, fontSize: 13, color: _onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Group Name
            _label('Group Name'),
            const SizedBox(height: 8),
            _textField(_nameController, 'e.g., Saturday Strikers'),
            const SizedBox(height: 16),

            // Description
            _label('Description (optional)'),
            const SizedBox(height: 8),
            _textField(_descriptionController, 'What is this group about?', maxLines: 2),
            const SizedBox(height: 24),

            // Select Sport
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Select Sport'),
                Text('Required', style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w600, fontSize: 12, color: _primaryColor)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _sportOptions.map((s) {
                final label = s['label'] as String;
                final isSelected = _selectedSport == label;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSport = label),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? _secondaryContainer : _surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isSelected ? _onSecondaryContainer.withOpacity(0.2) : _outlineVariant.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(s['icon'] as IconData, color: isSelected ? _onSecondaryContainer : _onSurfaceVariant, size: 18),
                        const SizedBox(width: 6),
                        Text(label, style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? _onSecondaryContainer : _onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),

            // Add Members
            _label('Add Members'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: _surfaceContainerLowest, borderRadius: BorderRadius.circular(8)),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: _outline),
                  hintText: 'Search athletes...',
                  hintStyle: TextStyle(fontFamily: 'Manrope', color: _outline),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                style: TextStyle(fontFamily: 'Manrope', color: _onSurface),
              ),
            ),
            const SizedBox(height: 12),

            // User list
            if (_isLoadingUsers)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredUsers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    _searchController.text.isEmpty
                        ? 'No users found in your community yet.'
                        : 'No results for "${_searchController.text}"',
                    style: TextStyle(fontFamily: 'Manrope', color: _onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._filteredUsers.map((u) {
                final uid = u['id'] as String;
                final isSelected = _selectedMemberIds.contains(uid);
                final username = u['username'] ?? 'Athlete';
                final avatarUrl = u['avatar_url'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryColor.withOpacity(0.05) : _surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected ? Border.all(color: _primaryColor.withOpacity(0.3), width: 1.5) : null,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _surfaceContainerHighest,
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? Text(
                                username.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.bold,
                                  color: _primaryColor,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(username, style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w600, color: _onSurface, fontSize: 16)),
                            Text(uid.substring(0, 8), style: TextStyle(fontFamily: 'Manrope', color: _onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          if (isSelected) {
                            _selectedMemberIds.remove(uid);
                          } else {
                            _selectedMemberIds.add(uid);
                          }
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: isSelected ? _primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: isSelected ? null : Border.all(color: _primaryColor, width: 2),
                          ),
                          child: Icon(isSelected ? Icons.check : Icons.add, color: isSelected ? Colors.white : _primaryColor, size: 20),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: _bgColor.withOpacity(0.9),
          border: Border(top: BorderSide(color: _outlineVariant.withOpacity(0.2))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isCreating ? null : _createGroup,
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 4),
            child: _isCreating
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    'Create Group${_selectedMemberIds.isNotEmpty ? ' (${_selectedMemberIds.length} selected)' : ''}',
                    style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500, fontSize: 14, color: _onSurfaceVariant));

  Widget _textField(TextEditingController c, String hint, {int maxLines = 1}) => Container(
    decoration: BoxDecoration(color: _surfaceContainerLowest, borderRadius: BorderRadius.circular(8)),
    child: TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Manrope', color: _outline),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: TextStyle(fontFamily: 'Manrope', color: _onSurface),
    ),
  );
}
