import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';

class ChatHistoryStorage {
  const ChatHistoryStorage();

  static const _prefKey = 'leyli_chat_history_sessions_v1';

  Future<List<ChatSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
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

  Future<ChatSession?> getSession(String id) async {
    final all = await loadAll();
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(ChatSession session) async {
    final all = await loadAll();
    final index = all.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      all[index] = session;
    } else {
      all.insert(0, session);
    }
    await _saveAll(all);
  }

  Future<void> deleteSession(String id) async {
    final all = await loadAll();
    all.removeWhere((s) => s.id == id);
    await _saveAll(all);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<void> _saveAll(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_prefKey, raw);
  }
}
