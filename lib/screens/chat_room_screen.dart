import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import 'peer_review_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String matchId;
  final String matchTitle;

  const ChatRoomScreen({
    super.key,
    required this.matchId,
    required this.matchTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final Map<String, Map<String, String?>> _senderProfileCache = {};
  bool _showScrollToBottom = false;
  bool _isSending = false;
  bool _showEmoji = false;

  // Common emojis grid
  static const List<String> _emojis = [
    '😀', '😂', '🤣', '😍', '🥰', '😎', '🤩', '😇',
    '🙂', '😉', '😋', '🤔', '🤗', '😅', '😆', '😁',
    '👍', '👎', '👏', '🙌', '🤝', '💪', '✌️', '🤞',
    '❤️', '🔥', '⭐', '🎉', '🎊', '🏆', '⚽', '🏏',
    '🏀', '🎾', '🏐', '🏸', '💯', '✅', '🙏', '👋',
    '😢', '😤', '😠', '🥺', '😱', '🤯', '😴', '🤮',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmoji) {
        setState(() => _showEmoji = false);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollToBottom == atBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<Map<String, String?>> _getSenderProfile(String userId) async {
    if (_senderProfileCache.containsKey(userId)) {
      return _senderProfileCache[userId]!;
    }
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', userId)
          .single();
      final profile = {
        'name': data['username']?.toString() ?? 'Athlete',
        'avatar_url': data['avatar_url']?.toString(),
      };
      _senderProfileCache[userId] = profile;
      return profile;
    } catch (e) {
      final profile = {'name': 'Athlete', 'avatar_url': null};
      _senderProfileCache[userId] = profile;
      return profile;
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('messages').insert({
        'match_id': widget.matchId,
        'user_id': userId,
        'content': text,
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      debugPrint('Send error: $e');
      _messageController.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: Colors.red.shade400,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _sendMessage,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected: ${img.name}\n(File sharing coming soon!)'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  String _formatTimestamp(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat.jm().format(dt);
      } else {
        return DateFormat('MMM d, h:mm a').format(dt);
      }
    } catch (e) {
      return '';
    }
  }

  bool _shouldShowDateSeparator(List<Map<String, dynamic>> messages, int index) {
    if (index == 0) return true;
    final current = DateTime.tryParse(messages[index]['created_at'] ?? '')?.toLocal();
    final previous = DateTime.tryParse(messages[index - 1]['created_at'] ?? '')?.toLocal();
    if (current == null || previous == null) return false;
    return current.day != previous.day ||
        current.month != previous.month ||
        current.year != previous.year;
  }

  String _formatDateSeparator(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(dt.year, dt.month, dt.day);
      if (messageDate == today) return 'Today';
      if (messageDate == yesterday) return 'Yesterday';
      return DateFormat('MMMM d, yyyy').format(dt);
    } catch (e) {
      return '';
    }
  }

  Future<Map<String, dynamic>> _fetchGroupInfo() async {
    // Avoid selecting created_by from group_chats -- it has a FK to
    // auth.users (cross-schema) which causes PGRST200 errors.

    Map<String, dynamic> group;
    try {
      group = await Supabase.instance.client
          .from('group_chats')
          .select('id, name, sport, description, created_at')
          .eq('id', widget.matchId)
          .single();
    } catch (e) {
      debugPrint('Error fetching group: $e');
      group = {
        'id': widget.matchId,
        'name': widget.matchTitle,
        'sport': '',
        'description': '',
        'created_at': '',
      };
    }

    // Fetch members without joining profiles to avoid PGRST200 on cross-schema FK
    List<dynamic> members = [];
    try {
      final rawMembers = await Supabase.instance.client
          .from('group_members')
          .select('user_id')
          .eq('group_id', widget.matchId);
          
      // Fetch profiles manually
      if (rawMembers.isNotEmpty) {
        final userIds = rawMembers.map((m) => m['user_id']).toList();
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id, username, avatar_url')
            .inFilter('id', userIds.cast<Object>());
            
        // Construct the expected structure: { 'user_id': id, 'profiles': { 'username': ..., 'avatar_url': ... } }
        for (var member in rawMembers) {
          final profile = profiles.firstWhere(
            (p) => p['id'] == member['user_id'], 
            orElse: () => <String, dynamic>{}
          );
          members.add({
            'user_id': member['user_id'],
            'profiles': profile.isNotEmpty ? profile : null,
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
    }

    // The first member added is typically the creator
    String? createdByUserId;
    if (members.isNotEmpty) {
      createdByUserId = members[0]['user_id']?.toString();
    }
    group['created_by'] = createdByUserId;

    // Fetch creator display name
    String creatorName = 'Unknown';
    if (createdByUserId != null && createdByUserId.isNotEmpty) {
      try {
        final creatorProfile = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('id', createdByUserId)
            .maybeSingle();
        if (creatorProfile != null) {
          creatorName = creatorProfile['username']?.toString() ?? 'Unknown';
        }
      } catch (_) {}
    }

    return {
      'group': group,
      'members': members,
      'creatorName': creatorName,
    };
  }


  Future<void> _showGroupInfo() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: FutureBuilder(
            future: _fetchGroupInfo(),
            builder: (context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(fontFamily: 'Manrope')));
              }

              final groupData = snapshot.data!['group'];
              final membersData = snapshot.data!['members'] as List<dynamic>;
              final creatorName = snapshot.data!['creatorName'] as String;

              return Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.outline.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              widget.matchTitle.isNotEmpty ? widget.matchTitle[0].toUpperCase() : 'G',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Lexend'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.matchTitle,
                                style: const TextStyle(fontFamily: 'Lexend', fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                              ),
                              Text(
                                groupData['sport'] ?? 'Sport Group',
                                style: TextStyle(fontFamily: 'Manrope', fontSize: 14, color: AppTheme.primary.withOpacity(0.8), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (groupData['description'] != null && groupData['description'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Description', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textVariant)),
                            const SizedBox(height: 4),
                            Text(groupData['description'], style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, color: AppTheme.textMain)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Icon(Icons.stars, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Created by ',
                          style: TextStyle(fontFamily: 'Manrope', fontSize: 14, color: AppTheme.textVariant),
                        ),
                        Text(
                          creatorName,
                          style: const TextStyle(fontFamily: 'Manrope', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Members', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textMain)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${membersData.length} total',
                            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: membersData.length,
                      itemBuilder: (context, index) {
                        final member = membersData[index]['profiles'];
                        final name = member?['username'] ?? 'Athlete';
                        final avatar = member?['avatar_url'];
                        final bool isCreator = membersData[index]['user_id'] == groupData['created_by'];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.surfaceContainer,
                                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                                child: avatar == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)) : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontFamily: 'Manrope', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textMain),
                                ),
                              ),
                              if (isCreator)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.amber.shade700, width: 1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Admin',
                                    style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Lexend'),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppTheme.textMain),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.matchTitle.isNotEmpty
                            ? widget.matchTitle[0].toUpperCase()
                            : 'G',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showGroupInfo,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.matchTitle,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: AppTheme.textMain,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'tap here for group info',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 12,
                              color: AppTheme.textVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded, color: AppTheme.primary),
                    onPressed: () {},
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textMain),
                    onSelected: (value) {
                      if (value == 'review') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PeerReviewScreen(
                              matchId: null,
                              revieweeId: widget.matchId,
                              revieweeName: widget.matchTitle,
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (BuildContext context) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'review',
                          child: Row(
                            children: [
                              Icon(Icons.star_rate_rounded, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Text('Review Player', style: TextStyle(fontFamily: 'Manrope')),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Messages
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: Supabase.instance.client
                      .from('messages')
                      .stream(primaryKey: ['id'])
                      .eq('match_id', widget.matchId)
                      .order('created_at', ascending: true),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      );
                    }

                    if (snapshot.hasError) {
                      debugPrint('Chat error: ${snapshot.error}');
                      final errStr = snapshot.error.toString();
                      final isOffline = errStr.contains('SocketException') || errStr.contains('Failed host lookup');
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isOffline ? Icons.wifi_off : Icons.error_outline, size: 48, color: Colors.red.shade300),
                              const SizedBox(height: 16),
                              Text(
                                isOffline ? 'No Internet Connection' : 'Could not load messages',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isOffline ? 'Please check your connection and try again.' : '$errStr',
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  fontSize: 12,
                                  color: AppTheme.textVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final messages = snapshot.data;
                    if (messages == null || messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chat_bubble_outline, size: 36, color: AppTheme.primary),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No messages yet',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppTheme.textMain,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Be the first to say hi! 👋',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 14,
                                color: AppTheme.textVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!_showScrollToBottom) {
                        _scrollToBottom(animated: false);
                      }
                    });

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isMe = message['user_id'] == currentUserId;
                        final content = message['content'] ?? message['text'] ?? '';
                        final timestamp = _formatTimestamp(message['created_at']);
                        final bool showSenderName = !isMe &&
                            (index == 0 || messages[index - 1]['user_id'] != message['user_id']);
                        final bool showDateSep = _shouldShowDateSeparator(messages, index);

                        return Column(
                          children: [
                            if (showDateSep)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceContainer.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _formatDateSeparator(message['created_at']),
                                    style: const TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textVariant,
                                    ),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: showSenderName ? 8 : 2,
                                  bottom: 2,
                                  left: isMe ? 60 : 0,
                                  right: isMe ? 0 : 60,
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (showSenderName)
                                      FutureBuilder<Map<String, String?>>(
                                        future: _getSenderProfile(message['user_id']),
                                        builder: (context, snap) {
                                          final profile = snap.data;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 4, left: 12),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (profile?['avatar_url'] != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 6),
                                                    child: Builder(
                                                      builder: (context) {
                                                        try {
                                                          return CircleAvatar(
                                                            radius: 10,
                                                            backgroundImage: profile!['avatar_url']!.startsWith('data:image')
                                                                ? MemoryImage(base64Decode(profile['avatar_url']!.split(',').last)) as ImageProvider
                                                                : NetworkImage(profile['avatar_url']!),
                                                          );
                                                        } catch (e) {
                                                          return const CircleAvatar(radius: 10, child: Icon(Icons.person, size: 12));
                                                        }
                                                      }
                                                    ),
                                                  ),
                                                Text(
                                                  profile?['name'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.primary.withOpacity(0.8),
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: 'Manrope',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        gradient: isMe ? AppTheme.primaryGradient : null,
                                        color: isMe ? null : AppTheme.surface,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(18),
                                          topRight: const Radius.circular(18),
                                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 18),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.04),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            content,
                                            style: TextStyle(
                                              color: isMe ? Colors.white : AppTheme.textMain,
                                              fontFamily: 'Manrope',
                                              fontSize: 15,
                                              height: 1.4,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                timestamp,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isMe
                                                      ? Colors.white.withOpacity(0.7)
                                                      : AppTheme.textVariant.withOpacity(0.5),
                                                  fontFamily: 'Manrope',
                                                ),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.done_all,
                                                  size: 14,
                                                  color: Colors.white.withOpacity(0.7),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              // Message input bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          // Emoji toggle
                          IconButton(
                            icon: Icon(
                              _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                              color: _showEmoji ? AppTheme.primary : AppTheme.textVariant.withOpacity(0.6),
                            ),
                            onPressed: () {
                              if (_showEmoji) {
                                _focusNode.requestFocus();
                              } else {
                                _focusNode.unfocus();
                              }
                              setState(() => _showEmoji = !_showEmoji);
                            },
                          ),
                          // Text field
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                textCapitalization: TextCapitalization.sentences,
                                maxLines: 4,
                                minLines: 1,
                                style: const TextStyle(
                                  fontFamily: 'Manrope',
                                  color: AppTheme.textMain,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: TextStyle(
                                    color: AppTheme.outline.withOpacity(0.5),
                                    fontFamily: 'Manrope',
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Attachment (image picker)
                          IconButton(
                            icon: Icon(
                              Icons.attach_file_rounded,
                              color: AppTheme.textVariant.withOpacity(0.6),
                            ),
                            onPressed: _pickImage,
                          ),
                          // Send button
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                              onPressed: _isSending ? null : _sendMessage,
                            ),
                          ),
                        ],
                      ),
                      // Emoji panel
                      if (_showEmoji)
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: _emojis.length,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () {
                                  _messageController.text += _emojis[index];
                                  _messageController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _messageController.text.length),
                                  );
                                },
                                child: Center(
                                  child: Text(
                                    _emojis[index],
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Scroll to bottom FAB
          if (_showScrollToBottom)
            Positioned(
              right: 16,
              bottom: 90,
              child: GestureDetector(
                onTap: () => _scrollToBottom(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.keyboard_arrow_down, color: AppTheme.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
