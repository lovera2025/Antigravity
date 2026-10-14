import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **La puerta sigue al sorteo.** El sorteo deja la mesa en el alumno, pero
/// Recepción y el tótem leen otra lista (`invitados`). Si un guardado de mesas
/// no la pone al día, la puerta sigue diciendo la mesa vieja, o sigue mostrando
/// a una institución cuyo sorteo se deshizo.
///
/// Las dos pantallas del salón no se pueden montar enteras en un test (leen de
/// la base con Riverpod), así que se leen del texto, igual que
/// `solo_modo_jefe_test.dart`. Lo que hace la puerta con cada caso está probado
/// en `lista_puerta_test.dart`; acá se cuida que **nadie se olvide de
/// llamarla**.
void main() {
  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantallaFiesta = 'lib/features/eventos/detalle_evento_masivo_screen.dart';
  const pantallaPlano = 'lib/features/plano/plano_evento_screen.dart';

  final guardado = RegExp(r'\basignarNumerosMesa\(');
  final funcion = RegExp(r'^  Future<void> (\w+)\(', multiLine: true);
  const llamada = 'ref.read(puertaAlDiaProvider).trasElSalon(';

  /// Las funciones de [ruta] que guardan mesas, cada una con si después del
  /// guardado —y dentro de la misma función— deja la puerta al día.
  Map<String, bool> guardanMesas(String ruta) {
    final fuente = leer(ruta);
    final funciones = funcion.allMatches(fuente).toList();
    final resultado = <String, bool>{};
    for (final g in guardado.allMatches(fuente)) {
      final i = funciones.lastIndexWhere((f) => f.start < g.start);
      if (i < 0) fail('un guardado de mesas fuera de una función, en $ruta');
      final fin =
          i + 1 < funciones.length ? funciones[i + 1].start : fuente.length;
      final despuesDelGuardado = fuente.substring(g.start, fin);
      resultado[funciones[i].group(1)!] = despuesDelGuardado.contains(llamada);
    }
    return resultado;
  }

  test('la fiesta: sortear, deshacer y restaurar dejan la puerta al día', () {
    final funciones = guardanMesas(pantallaFiesta);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan mesas y no dejan al día la lista de la puerta',
    );
    // Si aparece una función nueva que guarda mesas, que llame a la puerta y
    // se sume acá.
    expect(funciones.keys.toSet(), {
      '_ejecutarSorteo',
      '_ejecutarSorteoConPlano',
      '_deshacerSorteoMesas',
      '_restaurarSorteoAnterior',
    });
  });

  test('el plano: cambiar o mudar una familia deja la puerta al día', () {
    final funciones = guardanMesas(pantallaPlano);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan mesas y no dejan al día la lista de la puerta',
    );
    expect(funciones.keys.toSet(), {'_cambiarMesas'});
  });

  test('la puerta se pone al día antes de subir, para que viaje junto', () {
    // El orden importa: lo que se sube justo después del guardado es lo que se
    // encoló hasta ahí. Si la puerta se arma después, Recepción y el tótem se
    // enteran un ciclo más tarde que las mesas.
    for (final ruta in [pantallaFiesta, pantallaPlano]) {
      final fuente = leer(ruta);
      for (final g in guardado.allMatches(fuente)) {
        final resto = fuente.substring(g.start);
        final puerta = resto.indexOf(llamada);
        final subidas = [
          resto.indexOf('.afterMassiveMutation('),
          resto.indexOf('subirYa('),
          resto.indexOf('subida.subir('),
        ].where((i) => i >= 0);
        final primeraSubida =
            subidas.isEmpty ? -1 : subidas.reduce((a, b) => a < b ? a : b);
        expect(puerta, greaterThanOrEqualTo(0), reason: ruta);
        expect(
          primeraSubida,
          greaterThan(puerta),
          reason: 'en $ruta la puerta se pone al día después de subir',
        );
      }
    }
  });

  test('lo que cambia a un alumno solo también llega a la puerta', () {
    final fiesta = leer(pantallaFiesta);
    // Una baja sale de la lista con su familia; al reincorporarse vuelve.
    final baja = fiesta.substring(
      fiesta.indexOf('Future<void> _toggleBajaTemporal('),
      fiesta.indexOf('Future<void> _eliminarAlumnoPermanente('),
    );
    expect(baja, contains('.trasLosAlumnos(widget.evento.id, [alumno.id])'));
    // Un alumno eliminado se lleva sus filas: después no hay cómo encontrarlas.
    final eliminar = fiesta.substring(
      fiesta.indexOf('Future<void> _eliminarAlumnoPermanente('),
    );
    expect(
      eliminar.indexOf('.trasEliminar(widget.evento.id, alumno.id)'),
      greaterThan(eliminar.indexOf('eliminarContratoPermanente(alumno.id)')),
    );

    final ficha = leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    // Editar: solo si cambió el nombre, la mesa o los acompañantes.
    expect(ficha, contains('if (edicionCambiaLaPuerta('));
    expect(ficha, contains('.trasLosAlumnos(widget.evento.id, [al.id])'));
    // Alta: un alumno nuevo en una fiesta ya sorteada entra a la lista.
    expect(
      ficha,
      contains('.trasLosAlumnos(widget.evento.id, [nuevoContrato.id])'),
    );
  });

  test('vaciar la lista entera solo pasa por el salón', () {
    // `trasElSalon` es la única que puede dejar a una fiesta sin lista, y solo
    // la llaman las pantallas del salón, que son del jefe y antes miran la
    // nube. Si otra pantalla empieza a llamarla, una PC atrasada podría vaciar
    // la puerta de una institución.
    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('.trasElSalon('))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {pantallaFiesta, pantallaPlano});
  });

  test('lo que se importa del Excel del delegado llega a la puerta', () {
    // Los acompañantes son filas de la lista de la puerta: con la fiesta ya
    // sorteada, cargarlos sin avisarle dejaría a Recepción sin esas personas.
    final fiesta = leer(pantallaFiesta);
    final i = fiesta.indexOf('Future<void> _abrirAcompanantesYMusica() async {');
    final cuerpo = fiesta.substring(i, fiesta.indexOf('\n  }\n', i));
    final guardado = cuerpo.indexOf('cargarAcompanantesYMusica(');
    final puerta = cuerpo.indexOf('.trasLosAlumnos(');
    final subida = cuerpo.indexOf('.afterMassiveMutation(');
    expect(guardado, greaterThanOrEqualTo(0));
    expect(puerta, greaterThan(guardado));
    // Antes de subir, para que viaje junto.
    expect(subida, greaterThan(puerta));
  });
}
