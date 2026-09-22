import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Reads the pairing QR that the receiver screen draws.
///
/// The camera is only ever a faster way to type: what it reads is the same
/// six digits the keypad asks for, and it goes down the same pairing path.
/// So the keypad stays — for a television across the room, a refused camera,
/// or a viewer who would rather not hand the camera over at all.
class CastScanPage extends StatefulWidget {
  const CastScanPage({super.key});

  /// Pushes the scanner and returns the code it read, or null if the viewer
  /// backed out or asked to type it instead.
  static Future<String?> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (_) => const CastScanPage(),
        fullscreenDialog: true,
      ),
    );
  }

  /// The pairing code inside [raw], whatever shape it arrived in.
  ///
  /// The receiver encodes a small json object — `{v, s, c}` — of which only
  /// the code matters here: the session id travels with it, but the phone has
  /// no use for an id the claim is about to hand back anyway. A bare six
  /// digits is accepted too, so a code read off a printout still works.
  ///
  /// Anything else is somebody else's QR and is ignored rather than guessed
  /// at — stripping the non-digits out of a stray barcode would now and then
  /// leave six of them and send the viewer a failed pairing they never asked
  /// for.
  static String? codeIn(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) return null;
        final code = '${decoded['c'] ?? ''}';
        return _sixDigits.hasMatch(code) ? code : null;
      } on FormatException {
        return null;
      }
    }

    return _sixDigits.hasMatch(text) ? text : null;
  }

  static final RegExp _sixDigits = RegExp(r'^\d{6}$');

  @override
  State<CastScanPage> createState() => _CastScanPageState();
}

class _CastScanPageState extends State<CastScanPage> {
  // QR only: letting the detector chew on every barcode format it knows costs
  // frames and can only ever turn up codes this app has no use for.
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // The default is 640x480, which is thin for reading a code off a
    // television across a room; more pixels give the detector more to work
    // with and the frame rate still has room to spare for a still subject.
    cameraResolution: const Size(1280, 720),
  );

  bool _done = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final code = CastScanPage.codeIn(barcode.rawValue);
      if (code == null) continue;
      // The camera keeps firing while the route unwinds; one read is enough.
      _done = true;
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'مسح رمز الشاشة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scanner,
            builder: (context, state, _) => IconButton(
              tooltip: 'الإضاءة',
              onPressed: () => _scanner.toggleTorch(),
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final side = (size.shortestSide * 0.66).clamp(180.0, 320.0);
          final window = Rect.fromCenter(
            center: size.center(Offset.zero),
            width: side,
            height: side,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // No scanWindow: the red frame is a place to aim, not a
              // boundary. Restricting detection to it means a code that is
              // readable on screen but a little outside the rectangle is
              // never even looked at — and the mapping between the window
              // and the camera texture is its own source of misses.
              MobileScanner(
                controller: _scanner,
                onDetect: _onDetect,
                errorBuilder: (context, error, _) => _ScannerError(error: error),
              ),
              IgnorePointer(child: CustomPaint(painter: _Cutout(window))),
              Positioned(
                left: 24,
                right: 24,
                top: window.bottom + 28,
                child: const Text(
                  'وجّه الكاميرا نحو الرمز الظاهر على التلفاز',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 28,
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.keyboard_rounded, size: 19),
                    label: const Text('أدخل الرمز يدويًا'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shown in place of the preview when the camera cannot be had.
///
/// A refused camera is not a broken app — the keypad is one tap away — so
/// this says which of the two happened and points at the way through.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    final message = denied
        ? 'لم يُسمح للتطبيق باستخدام الكاميرا. يمكنك إدخال الرمز يدويًا.'
        : unsupported
            ? 'هذا الجهاز لا يدعم المسح. أدخل الرمز يدويًا.'
            : 'تعذّر تشغيل الكاميرا. أدخل الرمز يدويًا.';

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied ? Icons.no_photography_rounded : Icons.videocam_off_rounded,
                color: Colors.white54,
                size: 44,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.6),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                ),
                child: const Text('إدخال الرمز'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims everything but the window, so the eye knows where to aim.
class _Cutout extends CustomPainter {
  const _Cutout(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(window, const Radius.circular(22));

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(frame),
      ),
      Paint()..color = const Color(0xB3000000),
    );

    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFFE50914),
    );
  }

  @override
  bool shouldRepaint(_Cutout old) => old.window != window;
}
