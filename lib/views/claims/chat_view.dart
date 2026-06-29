import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/claim.dart';
import '../../viewmodels/chat_viewmodel.dart';

/// FR 5.4 / 5.6 — Masked in-app chat between finder and claimant (no phone
/// numbers exposed) plus the campus safe-zone handover selector.
class ChatView extends StatelessWidget {
  final Claim claim;
  final bool isFinder;

  const ChatView({super.key, required this.claim, required this.isFinder});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          ChatViewModel(claim.id, initialSafeZone: claim.safeZone)..init(),
      child: _ChatScaffold(claim: claim, isFinder: isFinder),
    );
  }
}

class _ChatScaffold extends StatefulWidget {
  final Claim claim;
  final bool isFinder;

  const _ChatScaffold({required this.claim, required this.isFinder});

  @override
  State<_ChatScaffold> createState() => _ChatScaffoldState();
}

class _ChatScaffoldState extends State<_ChatScaffold> {
  final _msgCtrl = TextEditingController();
  static const _primaryBlue = Color(0xFF1565C0);

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<ChatViewModel>().send(text);
    _msgCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isFinder ? 'Chat with Claimant' : 'Chat with Finder',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            Text(widget.claim.itemCategory,
                style: const TextStyle(
                    fontWeight: FontWeight.w400, fontSize: 12)),
          ],
        ),
      ),
      body: Column(
        children: [
          _SafeZoneBar(currentZone: vm.safeZone),
          Expanded(
            child: vm.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _primaryBlue))
                : vm.messages.isEmpty
                    ? _emptyChat()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: vm.messages.length,
                        itemBuilder: (_, i) {
                          final m = vm.messages[i];
                          final mine = m.senderId == vm.currentUserId;
                          return _Bubble(text: m.body, mine: mine);
                        },
                      ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _emptyChat() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Your identities stay private.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Say hello to arrange the handover.',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5)),
          ],
        ),
      );

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  filled: true,
                  fillColor: const Color(0xFFF0F4FF),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: _primaryBlue,
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Safe-zone selector (FR 5.6) ───────────────────────────────────────────────

class _SafeZoneBar extends StatelessWidget {
  final String? currentZone;

  const _SafeZoneBar({required this.currentZone});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8F5E9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Safe handover zone',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32))),
                Text(
                  currentZone ?? 'Not chosen yet — tap to select',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: currentZone == null
                        ? Colors.grey.shade600
                        : const Color(0xFF1B5E20),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _pickZone(context),
            child: const Text('Choose',
                style: TextStyle(
                    color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _pickZone(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Choose a Safe Zone',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...kSafeZones.map((z) => ListTile(
                  leading: const Icon(Icons.location_on_rounded,
                      color: Color(0xFF2E7D32)),
                  title: Text(z),
                  onTap: () {
                    context.read<ChatViewModel>().setSafeZone(z);
                    Navigator.of(sheetCtx).pop();
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;

  const _Bubble({required this.text, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: mine ? Colors.white : const Color(0xFF263238),
            fontSize: 14.5,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
