import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/match_result.dart';

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

  /// Uploads the reference image to a temporary path, then invokes the
  /// Supabase Edge Function `match-image` which performs pgvector similarity
  /// search and returns scored results.
  ///
  /// Replace the body of this method with a real vector-search call once your
  /// Edge Function is deployed. The stub below queries the found_items table
  /// directly and returns all rows so the UI is fully functional during dev.
  Future<List<MatchResult>> searchByImage(File imageFile) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    // Upload reference image to a temporary search path.
    final ext = imageFile.path.split('.').last;
    final refPath =
        'search_refs/${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('found-items').upload(refPath, imageFile);

    // ── Replace below with your Edge Function call ──────────────────────────
    // final response = await _client.functions.invoke(
    //   'match-image',
    //   body: {'ref_path': refPath},
    // );
    // final rows = List<Map<String, dynamic>>.from(response.data['matches']);
    // ────────────────────────────────────────────────────────────────────────

    // Dev stub: fetch all rows and attach a simulated confidence score.
    final rows = await _client
        .from('found_items')
        .select()
        .order('created_at', ascending: false)
        .limit(20);

    return (rows as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      // Simulate a confidence score until real AI scoring is wired up.
      map['confidence_score'] =
          60.0 + (map['id'].hashCode.abs() % 40);
      return MatchResult.fromMap(map);
    }).toList();
  }
}
