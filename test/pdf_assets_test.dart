import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'las fuentes del cierre están incluidas para trabajar sin internet',
    () async {
      final regular = await rootBundle.load(
        'assets/google_fonts/Outfit-Regular.ttf',
      );
      final bold = await rootBundle.load('assets/google_fonts/Outfit-Bold.ttf');

      expect(regular.lengthInBytes, greaterThan(10000));
      expect(bold.lengthInBytes, greaterThan(10000));
    },
  );
}
