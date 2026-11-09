import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/palette.dart';
import 'add_food.dart';
import 'food_widgets.dart';
import 'nutrition_screen.dart';

/// Opens the camera to scan the barcode on a packet. Returns true when the food it found
/// was added to the diary.
Future<bool?> scanFood(BuildContext context, {required String date}) => Navigator.of(
  context,
  rootNavigator: true, // over the glass bottom bar too
).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanScreen(date: date)));

/// Builds the camera view. It calls [onCode] with every barcode it reads. A parameter so a
/// test can stand in for the camera, which a test machine does not have.
typedef CameraBuilder = Widget Function(BuildContext context, void Function(String code) onCode);

/// The barcode formats printed on food: EAN-13 (also UPC-A, which it reads as), EAN-8, UPC-E.
const _foodFormats = [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE];

/// Looks the barcode up, then shows the food the same way as the search does, to log it.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, required this.date, this.camera});

  final String date;

  /// Stands in for the real camera in tests.
  final CameraBuilder? camera;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  // Only made when the real camera is used (a test stands in for it).
  late final MobileScannerController? _controller = widget.camera == null
      ? MobileScannerController(formats: _foodFormats, detectionSpeed: DetectionSpeed.noDuplicates)
      : null;

  // One barcode at a time: the camera reads the same packet many times a second, and keeps
  // reading while the food is open on top of it.
  bool _busy = false;
  bool _lookingUp = false; // only while the server is asked, not while the food is open
  String? _problem;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lookingUp = true;
      _problem = null;
    });
    Food? food;
    try {
      final json = await ref.read(apiProvider).get('/foods/barcode/$code');
      food = Food.fromJson(json as Map<String, dynamic>);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lookingUp = false;
        // A product that is simply not known reads differently from a dropped connection.
        _problem = error is ApiException && error.status == 404
            ? (error.code == 'no_nutrition'
                  ? 'That product has no nutrition information yet. Search for it by name instead.'
                  : 'No product found for that barcode. Search for it by name instead.')
            : messageOf(error);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _lookingUp = false);
    final added = await showFoodForMeal(context, food, date: widget.date, meal: mealForNow(DateTime.now()));
    if (!mounted) return;
    if (added == true) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false); // back to scanning, for the next packet
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          if (widget.camera == null)
            IconButton(
              tooltip: 'Torch',
              icon: const Icon(Icons.flashlight_on_outlined),
              onPressed: () => _controller?.toggleTorch(),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.camera?.call(context, _onCode) ??
              MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                  if (code != null) _onCode(code);
                },
                errorBuilder: (context, error) =>
                    _CameraProblem(denied: error.errorCode == MobileScannerErrorCode.permissionDenied),
              ),
          // A frame to aim the packet's barcode at.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: _problem == null ? Hxvy.accent : Hxvy.over, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Center(
              child: _lookingUp
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Looking it up…'),
                      ],
                    )
                  : Text(
                      _problem ?? 'Point the camera at the barcode on the packet',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: _problem == null ? Hxvy.text : Hxvy.over),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.denied});

  final bool denied;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        denied
            ? 'Hxvy needs the camera to scan barcodes. Allow it in your phone\'s settings for Hxvy, then come back.'
            : 'The camera could not start. Search for the food by name instead.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
