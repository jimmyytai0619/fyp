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
    });
  });
}
