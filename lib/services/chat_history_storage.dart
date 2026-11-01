import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import 'supabase_config.dart';
import 'user_auth_service.dart';

/// Stores chat history in Supabase per authenticated user, with a local-only
/// fallback for builds that do not configure Supabase.
class ChatHistoryStorage {
  final String? userId;

  const ChatHistoryStorage({this.userId});

  static const _baseKey = 'leyli_chat_history_sessions_v1';
  static const _table = 'chat_sessions';

  String _getPrefKey([String? explicitUserId]) {
    final effectiveId =
        explicitUserId ?? userId ?? UserAuthService.instance.currentUserId;
    if (effectiveId != null && effectiveId.isNotEmpty) {
      return '${_baseKey}_$effectiveId';
    }
    return _baseKey;
  }

  Future<List<ChatSession>> loadAll({String? forUserId}) async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      final authUser = client.auth.currentUser;
      if (authUser == null) return [];
      final targetUserId = forUserId ?? userId ?? authUser.id;

      var rows = await _loadRemoteRows(targetUserId);
      // Only import the signed-in student's own cache. In particular, an
      // admin viewing another account must never upload this device's data as
      // that student.
      if (targetUserId == authUser.id) {
        final migrated = await _migrateOwnLocalHistory(authUser.id);
        if (migrated) rows = await _loadRemoteRows(targetUserId);
      }
      return _decodeRemoteRows(rows);
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _getPrefKey(forUserId);
    var raw = prefs.getString(key);

    // Keep the legacy default-key migration only for local-only builds.
    if ((raw == null || raw.isEmpty) && key != _baseKey) {
      final legacy = prefs.getString(_baseKey);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await prefs.setString(key, legacy);
      }
    }
    return _decodeLocal(raw);
  }

  Future<ChatSession?> getSession(String id, {String? forUserId}) async {
    final all = await loadAll(forUserId: forUserId);
    try {
      return all.firstWhere((session) => session.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(ChatSession session, {String? forUserId}) async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      final authUser = client.auth.currentUser;
      if (authUser == null) throw StateError('Waa inaad gashaa akoonkaaga.');
      final targetUserId = forUserId ?? userId ?? authUser.id;
      if (targetUserId != authUser.id) {
        throw StateError('Ardaygu wuxuu kaydin karaa taariikhdiisa oo keliya.');
      }
      await _upsertRemote(session, targetUserId);
      return;
    }

    final all = await loadAll(forUserId: forUserId);
    final index = all.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      all[index] = session;
    } else {
      all.insert(0, session);
    }
    await _saveLocal(all, forUserId: forUserId);
  }

  Future<void> deleteSession(String id, {String? forUserId}) async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      final authUser = client.auth.currentUser;
      if (authUser == null) throw StateError('Waa inaad gashaa akoonkaaga.');
      final targetUserId = forUserId ?? userId ?? authUser.id;
      await client
          .from(_table)
          .delete()
          .eq('user_id', targetUserId)
          .eq('session_id', id);
      if (targetUserId == authUser.id) {
        final prefs = await SharedPreferences.getInstance();
        final key = _getPrefKey(authUser.id);
        final local = _decodeLocal(prefs.getString(key))
          ..removeWhere((session) => session.id == id);
        if (local.isEmpty) {
          await prefs.remove(key);
        } else {
          await _saveLocal(local, forUserId: authUser.id);
        }
      }
      return;
    }

    final all = await loadAll(forUserId: forUserId);
    all.removeWhere((session) => session.id == id);
    await _saveLocal(all, forUserId: forUserId);
  }

  Future<void> clearAll({String? forUserId}) async {
    if (SupabaseConfig.isInitialized) {
      final client = SupabaseConfig.client;
      final authUser = client.auth.currentUser;
      if (authUser == null) throw StateError('Waa inaad gashaa akoonkaaga.');
      final targetUserId = forUserId ?? userId ?? authUser.id;
      await client.from(_table).delete().eq('user_id', targetUserId);
      if (targetUserId == authUser.id) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_getPrefKey(authUser.id));
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getPrefKey(forUserId));
  }

  Future<List<Map<String, dynamic>>> _loadRemoteRows(
    String targetUserId,
  ) async {
    final rows = await SupabaseConfig.client
        .from(_table)
        .select('session_data')
        .eq('user_id', targetUserId)
        .order('updated_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  List<ChatSession> _decodeRemoteRows(List<Map<String, dynamic>> rows) {
    final sessions = <ChatSession>[];
    for (final row in rows) {
      try {
        final raw = row['session_data'];
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is Map) {
          sessions.add(
            ChatSession.fromJson(
              data.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      } catch (_) {
        // Ignore an invalid old record without losing the rest of the history.
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  List<ChatSession> _decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final sessions = list
          .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return [];
    }
  }

  Future<bool> _migrateOwnLocalHistory(String authUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getPrefKey(authUserId);
    final local = _decodeLocal(prefs.getString(key));
    if (local.isEmpty) return false;

    for (final session in local) {
      await _upsertRemote(session, authUserId);
    }
    // Remove the device cache only after every remote upsert succeeded.
    await prefs.remove(key);
    return true;
  }

  Future<void> _upsertRemote(ChatSession session, String targetUserId) async {
    await SupabaseConfig.client.from(_table).upsert({
      'user_id': targetUserId,
      'session_id': session.id,
      'title': session.title,
      'book_id': session.bookId,
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'session_data': _cloudSafeSessionJson(session),
    }, onConflict: 'user_id,session_id');
  }

  Map<String, dynamic> _cloudSafeSessionJson(ChatSession session) {
    final data = session.toJson();
    final messages = data['messages'] as List<dynamic>? ?? const [];
    data['messages'] = messages.map((message) {
      if (message is! Map) return message;
      final safeMessage = message.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final visuals = safeMessage['visuals'];
      if (visuals is List) {
        safeMessage['visuals'] = visuals.map((visual) {
          if (visual is! Map) return visual;
          final safeVisual = visual.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          safeVisual.remove('thumbnailPath');
          return safeVisual;
        }).toList();
      }
      return safeMessage;
    }).toList();
    return data;
  }

  Future<void> _saveLocal(
    List<ChatSession> sessions, {
    String? forUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      sessions.map((session) => session.toJson()).toList(),
    );
    await prefs.setString(_getPrefKey(forUserId), raw);
  }
}
