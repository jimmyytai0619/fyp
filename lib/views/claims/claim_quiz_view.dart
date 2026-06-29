import 'package:flutter/material.dart';

import '../../services/api_service.dart';

/// FR 5.1 / 5.2 / NFR 3.1 — Zero-Trust ownership quiz. The claimant must answer
/// the finder's security question before a claim is created. Locks after 3 fails.
class ClaimQuizView extends StatefulWidget {
  final String itemId;
  final String question;

  const ClaimQuizView({
    super.key,
    required this.itemId,
    required this.question,
  });

  @override
  State<ClaimQuizView> createState() => _ClaimQuizViewState();
}

class _ClaimQuizViewState extends State<ClaimQuizView> {
  final _answerCtrl = TextEditingController();
  bool _submitting = false;
  bool _locked = false;

  static const _primaryBlue = Color(0xFF1565C0);

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_answerCtrl.text.trim().isEmpty) {
      _snack('Please enter your answer.', isError: true);
      return;
    }
    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();

    String result;
    try {
      result = await ApiService()
          .submitClaim(itemId: widget.itemId, answer: _answerCtrl.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Something went wrong. Please try again.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case 'PASSED':
        _snack('Correct! Claim submitted for the finder to approve.',
            isError: false);
        Navigator.of(context).pop(true);
        break;
      case 'WRONG':
        _answerCtrl.clear();
        _snack('Incorrect answer. Please try again.', isError: true);
        break;
      case 'LOCKED':
        setState(() => _locked = true);
        _snack('Locked after 3 failed attempts.', isError: true);
        break;
      case 'ALREADY':
        _snack('You have already claimed this item.', isError: true);
        Navigator.of(context).pop(false);
        break;
      case 'REJECTED':
        _snack('Your previous claim for this item was rejected.',
            isError: true);
        Navigator.of(context).pop(false);
        break;
      case 'OWN_ITEM':
        _snack('This is your own reported item.', isError: true);
        Navigator.of(context).pop(false);
        break;
      case 'NO_QUESTION':
        _snack('This item has no ownership question set.', isError: true);
        Navigator.of(context).pop(false);
        break;
      default:
        _snack('Could not submit claim. Please try again.', isError: true);
    }
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Verify Ownership',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    color: _primaryBlue, size: 40),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Security Question',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9E9E9E),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    widget.question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _answerCtrl,
                    enabled: !_locked,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Type your answer',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _primaryBlue, width: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: (_submitting || _locked) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        _locked ? 'Locked' : 'Verify & Submit Claim',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _locked
                  ? 'This claim is locked. Please contact campus security.'
                  : 'You have 3 attempts to answer correctly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: _locked ? const Color(0xFFC62828) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
