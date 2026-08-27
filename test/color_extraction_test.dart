import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:smartmatch/services/classification_service.dart';

void main() {
  group('center-object colour extraction', () {
    test('prefers a centred red object over a blue background', () {
      final pixels = _imageWithCentredObject(
        background: const ui.Color(0xFF1565C0),
        object: const ui.Color(0xFFE32636),
      );

      final result = ClassificationService.extractCenterObjectColor(
        pixels,
        100,
        100,
      );

      expect(_rgb(result!), 0xE32636);
    });

    test('does not favour saturated background over a neutral object', () {
      final pixels = _imageWithCentredObject(
        background: const ui.Color(0xFF00A85A),
        object: const ui.Color(0xFF777777),
      );

      final result = ClassificationService.extractCenterObjectColor(
        pixels,
        100,
        100,
      );

      expect(_rgb(result!), 0x777777);
    });

    test('keeps white as a valid object colour', () {
      final pixels = _imageWithCentredObject(
        background: const ui.Color(0xFF795548),
        object: const ui.Color(0xFFFFFFFF),
      );

      final result = ClassificationService.extractCenterObjectColor(
        pixels,
        100,
        100,
      );

      expect(_rgb(result!), 0xFFFFFF);
    });
  });
}

Uint8List _imageWithCentredObject({
  required ui.Color background,
  required ui.Color object,
}) {
  const width = 100;
  const height = 100;
  final rgba = Uint8List(width * height * 4);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final isObject = x >= 37 && x < 63 && y >= 25 && y < 75;
      final color = isObject ? object : background;
      final offset = (y * width + x) * 4;
      final argb = color.toARGB32();
      rgba[offset] = (argb >> 16) & 0xFF;
      rgba[offset + 1] = (argb >> 8) & 0xFF;
      rgba[offset + 2] = argb & 0xFF;
      rgba[offset + 3] = (argb >> 24) & 0xFF;
    }
  }
  return rgba;
}

int _rgb(ui.Color color) => color.toARGB32() & 0xFFFFFF;
