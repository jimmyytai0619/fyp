import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import '../models/claim.dart';
import '../models/claim_message.dart';
import '../models/item_report.dart';
import '../models/match_result.dart';

/// Base URL of the Python FastAPI AI matching backend (Module 3).
/// Defaults to the Android emulator's host alias. For a physical phone, build
/// with `--dart-define=AI_BACKEND_URL=http://<PC-LAN-IP>:8000`.
const String aiBackendBaseUrl = String.fromEnvironment(
  'AI_BACKEND_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ApiService {
  final _client = Supabase.instance.client;

  /// Reports a found item and returns the new row's id.
  /// Optionally sets a Zero-Trust ownership question (FR 5.2): the question is
  /// public, but the answer is stored in the locked-down item_secrets table.
  Future<String> reportFoundItem({
    required File image,
    required String category,
    required String locationFound,
    required String description,
    required List<String> tags,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated.');

    final ext = image.path.split('.').last;
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from('found-items').upload(fileName, image);

    final imageUrl = _client.storage.from('found-items').getPublicUrl(fileName);

    final inserted = await _client.from('found_items').insert({
      'user_id': userId,
      'category': category,
      'location_found': locationFound,
      'description': description,
      'tags': tags,
      'image_url': imageUrl,
      'security_question': securityQuestion,
      'created_at': DateTime.now().toIso8601String(),
    }).select('id').single();

    final id = inserted['id'] as String;

    if (securityAnswer != null && securityAnswer.trim().isNotEmpty) {
      try {
        await _client.from('item_secrets').insert({
          'item_id': id,
          'answer': securityAnswer.trim(),
        });
      } catch (e) {
        // Roll back the just-created found item so a failed answer insert can't
        // leave an orphaned/duplicate row behind. Then surface the error.
        await _client.from('found_items').delete().eq('id', id);
        rethrow;
      }
    }

    return id;
  }

  // ── Secure Claim & Handover (Module 5) ──────────────────────────────────────

  /// True when the currently logged-in user is the finder who posted this item.
  Future<bool> isMyFoundItem(String itemId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _client
        .from('found_items')
        .select('user_id')
        .eq('id', itemId)
        .maybeSingle();
    return row != null && row['user_id'] == uid;
  }

  /// Reads the public ownership question for a found item (null if none set).
  Future<String?> getSecurityQuestion(String itemId) async {
    final row = await _client
        .from('found_items')
        .select('security_question')
        .eq('id', itemId)
        .maybeSingle();
    return row?['security_question'] as String?;
  }

  /// FR 5.1 / 5.2 — Submits a claim by answering the ownership quiz. The answer
  /// is verified server-side. Returns a status code:
  /// PASSED, WRONG, LOCKED, ALREADY, REJECTED, OWN_ITEM, NO_QUESTION.
  Future<String> submitClaim({
    required String itemId,
    required String answer,
  }) async {
    final res = await _client.rpc(
      'submit_claim',
      params: {'p_item_id': itemId, 'p_answer': answer},
    );
    return res as String;
  }

  /// Claims the current user has made (as the claimant).
  Future<List<Claim>> getMyClaims() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('User not authenticated.');
    final rows = await _client
        .from('claims')
        .select('*, found_items(*)')
        .eq('claimant_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Claim.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Claim requests on items the current user found (as the finder).
  /// Excludes in-progress quiz attempts that haven't passed yet.
  Future<List<Claim>> getClaimRequests() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('User not authenticated.');
    final rows = await _client
        .from('claims')
        .select('*, found_items(*)')
        .eq('finder_id', uid)
        .neq('status', 'Quiz')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Claim.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// FR 5.3 / 5.5 — Finder approves/rejects, or either party marks Returned.
  Future<void> updateClaimStatus(String claimId, String status) async {
    await _client.from('claims').update({'status': status}).eq('id', claimId);
  }

  /// FR 5.3 — Finder approves ('Verified') or rejects ('Rejected') a claim.
  /// Runs server-side so the claimant is notified of the decision (a cross-user
  /// notification the client can't write directly under RLS). Returns the RPC
  /// status: OK, NOT_FINDER, NOT_FOUND, BAD_DECISION, NOT_AUTHENTICATED.
  Future<String> decideClaim(String claimId, String decision) async {
    final res = await _client.rpc(
      'decide_claim',
      params: {'p_claim_id': claimId, 'p_decision': decision},
    );
    return res as String;
  }

  /// Flags a found item as returned so it counts toward the finder's
  /// "Items Returned" contribution stat. Best-effort.
  Future<void> markFoundItemReturned(String foundItemId) async {
    await _client
        .from('found_items')
        .update({'is_returned': true})
        .eq('id', foundItemId);
  }

  /// Uploads a handover-proof photo to storage and returns its public URL.
  /// Used as evidence when the finder marks an item returned (FoodPanda-style).
  Future<String> uploadReturnEvidence(File image, String claimId) async {
    final ext = image.path.split('.').last;
    final fileName =
        'returns/${claimId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('found-items').upload(fileName, image);
    return _client.storage.from('found-items').getPublicUrl(fileName);
  }

  /// FR 5.5 — Marks a claim's handover complete. Runs server-side so it also
  /// flags the found item returned, stores the proof photo, AND notifies the
  /// other party (a cross-user notification the client can't write under RLS).
  /// Returns the RPC status: OK, NOT_PARTY, NOT_FOUND, NOT_AUTHENTICATED.
  Future<String> markReturnedClaim(
    String claimId, {
    String? evidenceUrl,
  }) async {
    final res = await _client.rpc(
      'mark_returned',
      params: {'p_claim_id': claimId, 'p_evidence_url': evidenceUrl},
    );
    return res as String;
  }

  /// FR 5.5 — Claimant confirms (or denies) they received the item. A "yes"
  /// finalises the return; a "no" flags it back to the finder.
  /// Returns OK / DISPUTED / NOT_CLAIMANT / NOT_FOUND / NOT_AUTHENTICATED.
  Future<String> confirmReturn(String claimId, bool received) async {
    final res = await _client.rpc('confirm_return', params: {
      'p_claim_id': claimId,
      'p_received': received,
    });
    return res as String;
  }

  /// FR 5.6 — Finder generates the one-time handover code for a verified claim.
  /// Returns the 6-digit code, or a status (NOT_FINDER, NOT_VERIFIED, NOT_FOUND).
  Future<String> startHandover(String claimId) async {
    final res = await _client.rpc(
      'start_handover',
      params: {'p_claim_id': claimId},
    );
    return res as String;
  }

  /// FR 5.6 — Claimant presents the handover code (scanned or typed) to confirm
  /// the two matched parties are together. Returns OK / BAD_CODE / NO_CODE / …
  Future<String> verifyHandover(String claimId, String code) async {
    final res = await _client.rpc(
      'verify_handover',
      params: {'p_claim_id': claimId, 'p_code': code},
    );
    return res as String;
  }

  /// FR 5.6 — Records the chosen campus safe zone for the handover.
  Future<void> setClaimSafeZone(String claimId, String zone) async {
    await _client.from('claims').update({'safe_zone': zone}).eq('id', claimId);
  }

  /// FR 5.4 — Masked chat history for a verified claim.
  Future<List<ClaimMessage>> getMessages(String claimId) async {
    final rows = await _client
        .from('claim_messages')
        .select()
        .eq('claim_id', claimId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => ClaimMessage.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> sendMessage(String claimId, String body) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('User not authenticated.');
    await _client.from('claim_messages').insert({
      'claim_id': claimId,
      'sender_id': uid,
      'body': body.trim(),
    });
  }

  /// FR 4.3 — Asks the backend background agent to match a newly reported
  /// found item against all active lost reports and notify owners.
  /// Best-effort: failures here must not break the reporting flow.
  Future<void> ingestFoundItem(String itemId) async {
    final uri = Uri.parse('$aiBackendBaseUrl/ingest-found');
    final request = http.MultipartRequest('POST', uri)
      ..fields['item_id'] = itemId;
    await request.send().timeout(const Duration(seconds: 60));
  }

  /// FR 4.1 — Smart text search: keyword filter over found items when no
  /// reference photo is available (matches description or category).
  Future<List<ItemReport>> searchFoundItemsByText(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final rows = await _client
        .from('found_items')
        .select()
        .or('description.ilike.%$q%,category.ilike.%$q%')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => ItemReport.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Reports an item the user has LOST and returns the new row's id. The image
  /// is optional, but a photo is what lets the background agent match it.
  Future<String> reportLostItem({
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

    final inserted = await _client
        .from('lost_items')
        .insert({
          'user_id': userId,
          'category': category,
          'location_found': locationLost,
          'description': description,
          'tags': tags,
          'image_url': imageUrl,
          'created_at': DateTime.now().toIso8601String(),
        })
        .select('id')
        .single();

    return inserted['id'] as String;
  }

  /// FR 4.3 (reverse direction) — Asks the backend to match a newly reported
  /// LOST item against items that were ALREADY found, so the loser is alerted
  /// even when the finder posted first. Best-effort.
  Future<void> ingestLostItem(String itemId) async {
    final uri = Uri.parse('$aiBackendBaseUrl/ingest-lost');
    final request = http.MultipartRequest('POST', uri)
      ..fields['item_id'] = itemId;
    await request.send().timeout(const Duration(seconds: 60));
  }

  /// Updates one of the user's own reports (category, location, description).
  Future<void> updateReport({
    required String id,
    required bool isLost,
    required String category,
    required String location,
    required String description,
  }) async {
    final table = isLost ? 'lost_items' : 'found_items';
    await _client
        .from(table)
        .update({
          'category': category,
          'location_found': location,
          'description': description,
        })
        .eq('id', id);
  }

  /// Returns a map of found_item_id → the most-advanced claim status, for the
  /// current user's found items (so Manage My Records can show claim activity).
  Future<Map<String, String>> getMyFoundClaimStatuses() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _client
        .from('claims')
        .select('found_item_id, status')
        .eq('finder_id', uid)
        .neq('status', 'Quiz');

    const rank = {'Returned': 4, 'Verified': 3, 'Pending': 2, 'Rejected': 1};
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final fid = r['found_item_id'] as String?;
      final st = r['status'] as String?;
      if (fid == null || st == null) continue;
      final existing = map[fid];
      if (existing == null || (rank[st] ?? 0) > (rank[existing] ?? 0)) {
        map[fid] = st;
      }
    }
    return map;
  }

  /// Deletes one of the current user's own reports. RLS ensures a user can
  /// only delete rows they own.
  Future<void> deleteReport({required String id, required bool isLost}) async {
    final table = isLost ? 'lost_items' : 'found_items';
    await _client.from(table).delete().eq('id', id);
  }

  /// Closes one of the user's own reports so it stops matching / alerting:
  /// a lost report is marked resolved, a found item is marked returned.
  /// Pass [reopen] true to re-activate it.
  Future<void> resolveReport({
    required String id,
    required bool isLost,
    bool reopen = false,
  }) async {
    final table = isLost ? 'lost_items' : 'found_items';
    final column = isLost ? 'is_resolved' : 'is_returned';
    await _client.from(table).update({column: !reopen}).eq('id', id);
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
        .map(
          (r) => AppNotification.fromMap(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Marks every one of the current user's notifications as read.
  Future<void> markAllNotificationsRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  /// Deletes all of the current user's notifications.
  Future<void> clearNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('notifications').delete().eq('user_id', userId);
  }

  /// Fetches a single found item by id (used to open a match notification).
  Future<ItemReport?> getFoundItemById(String itemId) async {
    final row = await _client
        .from('found_items')
        .select()
        .eq('id', itemId)
        .maybeSingle();
    if (row == null) return null;
    return ItemReport.fromMap(Map<String, dynamic>.from(row));
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
  /// found item, and returns matches scoring at or above 50/100,
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
        'Could not reach the AI server. Make sure the backend is running.',
      );
    }

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
        'AI search failed (${response.statusCode}). Please try again.',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final matches = (decoded['matches'] as List? ?? [])
        .map((m) => MatchResult.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
    return matches;
  }
}
