// Quién queda anotado en lo que se registra (una entrega de entradas, un sorteo).
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/utils/quien_opera.dart';

import 'helpers/operadores_en_memoria.dart';

void main() {
  final carla = operadorDePrueba('a0000000-0000-4000-8000-000000000201', 'Carla', '4321');

  test('en el mostrador de Entradas, el nombre del operador que entró', () {
    final app = AppRoleState(
      kind: AppRoleKind.entradas,
      operador: carla,
      permisos: const PermisosEfectivos(entradas: true),
    );
    expect(quienOperaDe(app: app, nombrePerfil: 'Oficina', email: 'x@y.z'), 'Carla');
  });

  test('en modo jefe, "Jefe"', () {
    expect(quienOperaDe(app: const AppRoleState(kind: AppRoleKind.jefe)), 'Jefe');
  });

  test('sin operador, el perfil y después el mail', () {
    const nadie = AppRoleState();
    expect(quienOperaDe(app: nadie, nombrePerfil: 'Oficina'), 'Oficina');
    expect(quienOperaDe(app: nadie, email: 'x@y.z'), 'x@y.z');
    expect(quienOperaDe(app: nadie), 'Sin identificar');
  });
}
