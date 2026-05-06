import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'antigravity_alerts';
  static const String _channelName = 'Match Alerts';
  static const String _channelDesc = 'Notifications for new matches and activity';

  static const String _chatChannelId = 'group_chat_messages';
  static const String _chatChannelName = 'Group Chat Messages';
  static const String _chatChannelDesc = 'Notifications for new messages in your groups';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // 1. Initialize Local Notifications (For foreground display)
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();

        const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
          _channelId, _channelName, description: _channelDesc,
          importance: Importance.max, playSound: true, enableVibration: true,
        );
        await androidPlugin.createNotificationChannel(alertChannel);

        const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
          _chatChannelId, _chatChannelName, description: _chatChannelDesc,
          importance: Importance.high, playSound: true, enableVibration: true,
        );
        await androidPlugin.createNotificationChannel(chatChannel);
      }

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(settings: initSettings);

      // 2. Initialize Firebase Messaging
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      debugPrint('FCM Authorization status: ${settings.authorizationStatus}');

      // 3. Get FCM Token & save to Supabase
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        await _saveTokenToSupabase(token);
      }

      // Listen to token refreshes
      messaging.onTokenRefresh.listen(_saveTokenToSupabase);

      // 4. Handle Foreground Messages via FCM
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        
        if (message.notification != null) {
          final isChat = message.data['type'] == 'chat';
          showNotification(
            message.notification!.title ?? 'New Alert',
            message.notification!.body ?? '',
            channelId: isChat ? _chatChannelId : _channelId,
            channelName: isChat ? _chatChannelName : _channelName,
            channelDesc: isChat ? _chatChannelDesc : _channelDesc,
          );
        }
      });

      _initialized = true;
      debugPrint('NotificationService initialized successfully.');
    } catch (e, st) {
      debugPrint('NotificationService init error: $e');
    }
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      await Supabase.instance.client.from('fcm_tokens').upsert({
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('FCM Token saved to Supabase');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  static Future<void> showNotification(String title, String body,
      {String channelId = _channelId,
      String channelName = _channelName,
      String channelDesc = _channelDesc}) async {
    if (!_initialized) await init();

    try {
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
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
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  // Deprecated listeners - replaced by FCM backend logic
  static void startListening() {
    debugPrint('startListening is deprecated. Using FCM.');
  }

  static Future<void> startGroupChatListener() async {
    debugPrint('startGroupChatListener is deprecated. Using FCM.');
  }

  static void addJoinedGroup(String groupId) {}
  static void removeJoinedGroup(String groupId) {}
}
