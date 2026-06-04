import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

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
}
