import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/item_report.dart';
import '../models/match_result.dart';

/// Base URL of the Python FastAPI AI matching backend (Module 3).
///   • Android emulator → 10.0.2.2 maps to the host machine's localhost
///   • Real device      → replace with your PC's LAN IP (e.g. 192.168.1.x:8000)
const String aiBackendBaseUrl = 'http://10.0.2.2:8000';

class ApiService {
  final _client = Supabase.instance.client;

  Future<void> reportFoundItem({
    required File image,
    required String category,
    required String locationFound,
    required String description,
    required List<String> tags,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final ext = image.path.split('.').last;
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from('found-items').upload(fileName, image);

    final imageUrl =
        _client.storage.from('found-items').getPublicUrl(fileName);

    await _client.from('found_items').insert({
      'user_id': userId,
      'category': category,
      'location_found': locationFound,
      'description': description,
      'tags': tags,
      'image_url': imageUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Reports an item the user has LOST. The image is optional because a user
  /// may not always have a photo of their missing belonging.
  Future<void> reportLostItem({
    File? image,
    required String category,
    required String locationLost,
    required String description,
    required List<String> tags,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    String? imageUrl;
    if (image != null) {
      final ext = image.path.split('.').last;
      final fileName =
          'lost/${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('found-items').upload(fileName, image);
      imageUrl = _client.storage.from('found-items').getPublicUrl(fileName);
    }

    await _client.from('lost_items').insert({
      'user_id': userId,
      'category': category,
      'location_found': locationLost,
      'description': description,
      'tags': tags,
      'image_url': imageUrl,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Deletes one of the current user's own reports. RLS ensures a user can
  /// only delete rows they own.
  Future<void> deleteReport({
    required String id,
    required bool isLost,
  }) async {
    final table = isLost ? 'lost_items' : 'found_items';
    await _client.from(table).delete().eq('id', id);
  }

  Future<List<ItemReport>> getMyLostReports() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final rows = await _client
        .from('lost_items')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => ItemReport.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<ItemReport>> getMyFoundReports() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final rows = await _client
        .from('found_items')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => ItemReport.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<AppNotification>> getNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final rows = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) =>
            AppNotification.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<List<ItemReport>> browseFoundItems({String? category}) async {
    final baseQuery = _client.from('found_items').select();

    final rows = (category != null && category != 'All')
        ? await baseQuery
            .eq('category', category)
            .order('created_at', ascending: false)
        : await baseQuery.order('created_at', ascending: false);

    return (rows as List)
        .map((r) => ItemReport.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Sends the reference image to the FastAPI MobileNetV2 backend, which
  /// extracts a 1280-dim feature vector, runs cosine similarity against every
  /// found item, and returns matches scoring at or above the 50% threshold,
  /// ranked highest-first (FR 3.1–3.5).
  Future<List<MatchResult>> searchByImage(
    File imageFile, {
    String? category,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final uri = Uri.parse('$aiBackendBaseUrl/search');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    if (category != null && category.isNotEmpty) {
      request.fields['category'] = category;
    }

    http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      throw Exception(
          'Could not reach the AI server. Make sure the backend is running.');
    }

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
          'AI search failed (${response.statusCode}). Please try again.');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final matches = (decoded['matches'] as List? ?? [])
        .map((m) => MatchResult.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
    return matches;
  }
}
