import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// The single channel used for all alerts.
  static const String _channelId = 'antigravity_alerts';
  static const String _channelName = 'Match Alerts';
  static const String _channelDesc =
      'Notifications for new matches and activity';

  /// Separate channel for group chat messages.
  static const String _chatChannelId = 'group_chat_messages';
  static const String _chatChannelName = 'Group Chat Messages';
  static const String _chatChannelDesc =
      'Notifications for new messages in your groups';

  static bool _initialized = false;

  /// IDs of groups the current user has joined – populated by startGroupChatListener.
  static Set<String> _joinedGroupIds = {};

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // 1️⃣  Request POST_NOTIFICATIONS permission (Android 13+/16)
        final bool? granted =
            await androidPlugin.requestNotificationsPermission();
        debugPrint('NotificationService: permission granted = $granted');

        // 2️⃣  Explicitly create notification channels BEFORE init
        const AndroidNotificationChannel alertChannel =
            AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await androidPlugin.createNotificationChannel(alertChannel);

        const AndroidNotificationChannel chatChannel =
            AndroidNotificationChannel(
          _chatChannelId,
          _chatChannelName,
          description: _chatChannelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        await androidPlugin.createNotificationChannel(chatChannel);
        debugPrint('NotificationService: channels created.');
      }

      // 3️⃣  Initialize the plugin
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);

      final bool? initResult =
          await _notificationsPlugin.initialize(settings: initSettings);
      debugPrint('NotificationService: initialize result = $initResult');

      _initialized = true;
      debugPrint('NotificationService initialized successfully.');
    } catch (e, st) {
      debugPrint('NotificationService init error: $e');
      debugPrint('$st');
    }
  }

  /// Display a local notification immediately.
  static Future<void> showNotification(String title, String body,
      {String channelId = _channelId,
      String channelName = _channelName,
      String channelDesc = _channelDesc}) async {
    if (!_initialized) {
      debugPrint('NotificationService: not initialized yet – calling init()');
      await init();
    }

    try {
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );

      await _notificationsPlugin.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: androidDetails),
      );
      debugPrint('Notification shown successfully: $title');
    } catch (e, st) {
      debugPrint('Error showing notification: $e');
      debugPrint('$st');
    }
  }

  /// Subscribe to Supabase Realtime and fire a local notification
  /// whenever a new row is inserted into the `notifications` table
  /// that targets the current user.
  static void startListening() {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    Supabase.instance.client
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord['user_id'] == currentUserId) {
              showNotification(
                newRecord['title'] ?? 'New Notification',
                newRecord['body'] ?? '',
              );
            }
          },
        )
        .subscribe();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Group-chat message notifications
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch the groups the current user has joined and start listening
  /// for new messages in the `messages` table.  When a message arrives
  /// from a joined group (and it's not sent by this user), fire a
  /// local notification.
  static Future<void> startGroupChatListener() async {
    final currentUserId =
        Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Fetch joined group IDs
    try {
      final rows = await Supabase.instance.client
          .from('group_members')
          .select('group_id')
          .eq('user_id', currentUserId);

      _joinedGroupIds = (rows as List<dynamic>)
          .map((r) => r['group_id'].toString())
          .toSet();

      debugPrint(
          'NotificationService: listening for ${_joinedGroupIds.length} groups');
    } catch (e) {
      debugPrint('NotificationService: could not fetch joined groups: $e');
      return;
    }

    // Subscribe to new messages via Realtime
    Supabase.instance.client
        .channel('group_chat_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final newMsg = payload.newRecord;
            final matchId = newMsg['match_id']?.toString() ?? '';
            final senderId = newMsg['user_id']?.toString() ?? '';

            // Only notify if it's a group we joined AND not our own message
            if (_joinedGroupIds.contains(matchId) &&
                senderId != currentUserId) {
              // Try to resolve sender name
              String senderName = 'Someone';
              try {
                final profile = await Supabase.instance.client
                    .from('profiles')
                    .select('username')
                    .eq('id', senderId)
                    .maybeSingle();
                if (profile != null) {
                  senderName =
                      profile['username']?.toString() ?? 'Someone';
                }
              } catch (_) {}

              // Try to resolve group name
              String groupName = 'a group';
              try {
                final group = await Supabase.instance.client
                    .from('group_chats')
                    .select('name')
                    .eq('id', matchId)
                    .maybeSingle();
                if (group != null) {
                  groupName =
                      group['name']?.toString() ?? 'a group';
                }
              } catch (_) {}

              final content =
                  newMsg['content']?.toString() ?? 'sent a message';

              showNotification(
                '$senderName in $groupName',
                content,
                channelId: _chatChannelId,
                channelName: _chatChannelName,
                channelDesc: _chatChannelDesc,
              );
            }
          },
        )
        .subscribe();
  }

  /// Call this whenever a user joins or leaves a group to keep the
  /// notification filter up-to-date without restarting the listener.
  static void addJoinedGroup(String groupId) => _joinedGroupIds.add(groupId);
  static void removeJoinedGroup(String groupId) =>
      _joinedGroupIds.remove(groupId);
}
