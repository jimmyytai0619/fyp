import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/claim_message.dart';
import '../services/api_service.dart';

class ChatViewModel extends ChangeNotifier {
  final String claimId;

  ChatViewModel(this.claimId, {String? initialSafeZone})
      : _safeZone = initialSafeZone;

  final String? currentUserId =
      Supabase.instance.client.auth.currentUser?.id;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<ClaimMessage> _messages = [];
  List<ClaimMessage> get messages => List.unmodifiable(_messages);

  String? _safeZone;
  String? get safeZone => _safeZone;

  RealtimeChannel? _channel;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      _messages = await ApiService().getMessages(claimId);
    } catch (e) {
      debugPrint('[ChatViewModel] load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    _subscribe();
  }

  void _subscribe() {
    _channel = Supabase.instance.client
        .channel('claim_messages_$claimId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'claim_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'claim_id',
            value: claimId,
          ),
          callback: (payload) {
            final msg = ClaimMessage.fromMap(
                Map<String, dynamic>.from(payload.newRecord));
            if (_messages.any((m) => m.id == msg.id)) return;
            _messages = [..._messages, msg];
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> send(String body) async {
    if (body.trim().isEmpty) return;
    try {
      await ApiService().sendMessage(claimId, body);
    } catch (e) {
      debugPrint('[ChatViewModel] send error: $e');
    }
  }

  Future<void> setSafeZone(String zone) async {
    try {
      await ApiService().setClaimSafeZone(claimId, zone);
      _safeZone = zone;
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatViewModel] safe zone error: $e');
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }
}
