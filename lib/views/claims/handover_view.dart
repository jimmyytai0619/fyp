import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/claim.dart';
import '../../services/api_service.dart';

const _primaryBlue = Color(0xFF1565C0);
const _green = Color(0xFF2E7D32);

/// Encoded inside the QR so a scan is self-contained: `HANDOVER:claimId:code`.
String _encode(String claimId, String code) => 'HANDOVER:$claimId:$code';

/// Parses a scanned payload back into (claimId, code); null if it isn't ours.
({String claimId, String code})? _decode(String raw) {
  final parts = raw.trim().split(':');
  if (parts.length != 3 || parts[0] != 'HANDOVER') return null;
  return (claimId: parts[1], code: parts[2]);
}

// ── Finder side: show the QR + 6-digit code ──────────────────────────────────
class HandoverCodeView extends StatefulWidget {
  final Claim claim;
  const HandoverCodeView({super.key, required this.claim});

  @override
  State<HandoverCodeView> createState() => _HandoverCodeViewState();
}

class _HandoverCodeViewState extends State<HandoverCodeView> {
  String? _code;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiService().startHandover(widget.claim.id);
      if (!mounted) return;
      if (RegExp(r'^\d{6}$').hasMatch(result)) {
        setState(() => _code = result);
      } else {
        setState(() => _error = _friendly(result));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create the code. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(String status) => switch (status) {
        'NOT_VERIFIED' => 'This claim must be approved before handover.',
        'NOT_FINDER' => 'Only the finder can show the handover code.',
        _ => 'Could not create the code. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Handover Code',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const CircularProgressIndicator(color: _primaryBlue)
              : _error != null
                  ? _errorBox(_error!)
                  : _codeCard(),
        ),
      ),
    );
  }

  Widget _codeCard() {
    final code = _code!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Show this to the person collecting the item',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Color(0xFF546E7A)),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              QrImageView(
                data: _encode(widget.claim.id, code),
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              const Text('Or enter this code:',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E))),
              const SizedBox(height: 6),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: Color(0xFF1A237E),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          widget.claim.handoverVerified
              ? '✅ Already verified by the claimant.'
              : 'Waiting for the claimant to scan or enter it…',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: widget.claim.handoverVerified ? _green : Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Generate a new code'),
        ),
      ],
    );
  }

  Widget _errorBox(String msg) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFC62828), size: 40),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
        ],
      );
}

// ── Claimant side: scan the QR or type the code ──────────────────────────────
class HandoverVerifyView extends StatefulWidget {
  final Claim claim;
  const HandoverVerifyView({super.key, required this.claim});

  @override
  State<HandoverVerifyView> createState() => _HandoverVerifyViewState();
}

class _HandoverVerifyViewState extends State<HandoverVerifyView> {
  final _codeCtrl = TextEditingController();
  bool _manual = false; // false = scanner, true = type the code
  bool _busy = false;
  bool _handled = false; // guard against repeated scan callbacks

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String code) async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _snack('Enter the 6-digit code.', isError: true);
      return;
    }
    setState(() => _busy = true);
    String result;
    try {
      result = await ApiService().verifyHandover(widget.claim.id, code);
    } catch (_) {
      result = 'ERROR';
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (result == 'OK') {
      _snack('Handover verified!', isError: false);
      Navigator.of(context).pop(true);
    } else {
      _handled = false; // allow another scan attempt
      _snack(_friendly(result), isError: true);
    }
  }

  String _friendly(String status) => switch (status) {
        'BAD_CODE' => 'That code is incorrect. Check with the finder.',
        'NO_CODE' => "The finder hasn't shown a code yet.",
        'NOT_CLAIMANT' => 'Only the claimant can verify this handover.',
        _ => 'Could not verify. Please try again.',
      };

  void _onScan(BarcodeCapture capture) {
    if (_handled || _busy) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final decoded = _decode(raw);
      if (decoded == null) continue;
      if (decoded.claimId != widget.claim.id) {
        _handled = true;
        _snack('This code is for a different claim.', isError: true);
        return;
      }
      _handled = true;
      _submit(decoded.code);
      return;
    }
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFD32F2F) : _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Verify Handover',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => setState(() => _manual = !_manual),
            child: Text(_manual ? 'Scan QR' : 'Enter Code',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _manual ? _codeEntry() : _scanner(),
    );
  }

  Widget _scanner() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MobileScanner(onDetect: _onScan),
              // Simple viewfinder
              Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              if (_busy)
                const Positioned(
                  bottom: 40,
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Point at the finder\'s QR code. No camera? Tap "Enter Code".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  Widget _codeEntry() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pin_rounded, size: 48, color: _primaryBlue),
            const SizedBox(height: 16),
            const Text('Enter the 6-digit code the finder is showing',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF546E7A))),
            const SizedBox(height: 20),
            TextField(
              controller: _codeCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _submit(_codeCtrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Verify',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
