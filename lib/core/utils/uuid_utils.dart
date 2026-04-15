import 'package:uuid/uuid.dart';

class UuidUtils {
  static const _uuid = Uuid();

  /// Genera un UUID v4 estándar.
  static String generate() {
    return _uuid.v4();
  }
}
