import 'package:flutter_test/flutter_test.dart';
import 'package:smartmatch/services/classification_service.dart';

void main() {
  group('ClassificationService.mapLabelToCategory', () {
    test('does not match id/card/cap inside unrelated words', () {
      expect(ClassificationService.mapLabelToCategory('video'), 'Other');
      expect(ClassificationService.mapLabelToCategory('lid'), 'Other');
      expect(ClassificationService.mapLabelToCategory('solid'), 'Other');
      expect(ClassificationService.mapLabelToCategory('cardboard'), 'Other');
      expect(ClassificationService.mapLabelToCategory('capsule'), 'Other');
    });

    test('maps paper and documents to stationery', () {
      expect(
        ClassificationService.mapLabelToCategory('paper'),
        'Books & Stationery',
      );
      expect(
        ClassificationService.mapLabelToCategory('document'),
        'Books & Stationery',
      );
    });

    test('maps representative campus items', () {
      expect(
        ClassificationService.mapLabelToCategory('mobile phone'),
        'Electronics',
      );
      expect(
        ClassificationService.mapLabelToCategory('student ID'),
        'IDs & Cards',
      );
      expect(
        ClassificationService.mapLabelToCategory('water bottle'),
        'Water Bottles',
      );
      expect(
        ClassificationService.mapLabelToCategory('bottle cap'),
        'Water Bottles',
      );
      expect(
        ClassificationService.mapLabelToCategory('baseball cap'),
        'Clothing & Accessories',
      );
      expect(
        ClassificationService.mapLabelToCategory('backpack'),
        'Bags & Wallets',
      );
      expect(
        ClassificationService.mapLabelToCategory('keychain'),
        'Keys & Lanyards',
      );
      expect(
        ClassificationService.mapLabelToCategory('set of keys'),
        'Keys & Lanyards',
      );
      expect(
        ClassificationService.mapLabelToCategory('key ring'),
        'Keys & Lanyards',
      );
      expect(
        ClassificationService.mapLabelToCategory('padlock'),
        'Keys & Lanyards',
      );
    });
  });

  group('ClassificationService.keyShapeEvidenceScore', () {
    test('detects the three-part key silhouette evidence', () {
      final score = ClassificationService.keyShapeEvidenceScore({
        'Tableware': 0.74,
        'Goggles': 0.59,
        'Nail': 0.37,
      });

      expect(score, isNotNull);
      expect(score!, greaterThanOrEqualTo(0.50));
      expect(score, lessThan(0.75));
    });

    test('does not classify ordinary eyewear or metal alone as a key', () {
      expect(
        ClassificationService.keyShapeEvidenceScore({
          'Glasses': 0.90,
          'Sunglasses': 0.82,
          'Flesh': 0.70,
        }),
        isNull,
      );
      expect(
        ClassificationService.keyShapeEvidenceScore({
          'Metal': 0.90,
          'Nail': 0.70,
        }),
        isNull,
      );
    });
  });
}
