import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lo que cambia el salón lo hace solo el jefe: armar y personalizar el plano,
/// sortear, deshacer, restaurar, y cambiar o mudar familias de mesa (ver
/// `lib/features/common/utils/solo_jefe.dart`).
///
/// Los botones llegan apagados sin modo jefe, y eso lo prueban los tests de la
/// barra y de la pantalla del plano. Acá se cuida la segunda llave: **cada
/// función que guarda el salón pregunta por el modo jefe antes de guardar**.
///
/// Las dos pantallas leen de la base con Riverpod y no se pueden montar en un
/// test, así que se leen del texto del archivo, igual que
/// `sync_tablas_v73_test` lee el motor. Importa porque es lo que evita que dos
/// PCs se pisen el plano: la fila sube entera, y con una sola PC cambiándola no
/// hay a quién pisar.
void main() {
  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  const pantallaFiesta = 'lib/features/eventos/detalle_evento_masivo_screen.dart';
  const pantallaPlano = 'lib/features/plano/plano_evento_screen.dart';

  /// Las dos llamadas por las que se guarda el salón: los números de mesa (con
  /// su renglón y, si hace falta, el plano) y el plano solo.
  final guardado = RegExp(r'\basignarNumerosMesa\(|\bplanos\.guardar\(');

  /// Donde empieza cada función de la pantalla.
  final funcion = RegExp(r'^  Future<void> (\w+)\(', multiLine: true);

  /// Las funciones de [ruta] que guardan el salón, cada una con si pregunta
  /// por el modo jefe **antes** de guardar.
  Map<String, bool> guardanElSalon(String ruta) {
    final fuente = leer(ruta);
    final funciones = funcion.allMatches(fuente).toList();
    final resultado = <String, bool>{};
    for (final g in guardado.allMatches(fuente)) {
      final donde = funciones.lastWhere(
        (f) => f.start < g.start,
        orElse: () => fail('un guardado fuera de una función, en $ruta'),
      );
      final hastaElGuardado = fuente.substring(donde.start, g.start);
      resultado[donde.group(1)!] =
          hastaElGuardado.contains('_frenaSinModoJefe()');
    }
    return resultado;
  }

  test('la fiesta: sortear, deshacer y restaurar preguntan por el modo jefe', () {
    final funciones = guardanElSalon(pantallaFiesta);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan el salón sin preguntar por el modo jefe',
    );
    // Si aparece una función nueva que guarda, que pregunte y se sume acá.
    expect(funciones.keys.toSet(), {
      '_ejecutarSorteo',
      '_ejecutarSorteoConPlano',
      '_deshacerSorteoMesas',
      '_restaurarSorteoAnterior',
    });
  });

  test('el plano: armar, personalizar y cambiar familias preguntan por el modo '
      'jefe', () {
    final funciones = guardanElSalon(pantallaPlano);
    expect(
      funciones.entries.where((e) => !e.value).map((e) => e.key),
      isEmpty,
      reason: 'guardan el salón sin preguntar por el modo jefe',
    );
    expect(funciones.keys.toSet(), {'_guardar', '_cambiarConfig', '_cambiarMesas'});
  });

  test('la llave pregunta por el modo jefe de verdad', () {
    for (final ruta in [pantallaFiesta, pantallaPlano]) {
      final fuente = leer(ruta);
      final i = fuente.indexOf('bool _frenaSinModoJefe() {');
      expect(i, greaterThanOrEqualTo(0), reason: 'falta la llave en $ruta');
      final cuerpo = fuente.substring(i, fuente.indexOf('\n  }', i));
      expect(
        cuerpo,
        contains('if (ref.read(esRolJefeProvider)) return false;'),
        reason: ruta,
      );
      expect(cuerpo, contains('return true;'), reason: ruta);
    }
  });

  test('Editar alumno: el número de mesa escrito a mano pasa por la llave', () {
    final fuente =
        leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    // Lo escrito en el casillero se lee en un solo lugar: lo que se le pasa a
    // `numeroMesaParaGuardar`, que sin modo jefe devuelve el que ya tenía.
    expect(
      RegExp(r'_numeroMesaCtrl\.text').allMatches(fuente).length,
      1,
      reason: 'el casillero se lee por fuera de numeroMesaParaGuardar',
    );
    expect(
      fuente,
      contains('''
      final numeroMesa = numeroMesaParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.numeroMesa,
        escrito: _numeroMesaCtrl.text,
      );'''),
    );
    // Y el casillero se dibuja con el modo jefe de la sesión.
    expect(fuente, contains('final esJefe = ref.watch(esRolJefeProvider);'));
    expect(fuente, contains('CasilleroNumeroMesa('));
  });

  test('nadie más guarda el salón', () {
    // Los números de mesa, el renglón del cambio y el plano se escriben por
    // estos caminos. Si otra pantalla empieza a usarlos, tiene que preguntar
    // por el modo jefe y sumarse a los tests de arriba.
    Set<String> archivosCon(String texto) => {
          for (final f in Directory('lib').listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(texto))
              f.path.replaceAll('\\', '/'),
        };

    expect(archivosCon('asignarNumerosMesa('), {
      pantallaFiesta,
      pantallaPlano,
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
    expect(archivosCon('planosEventoRepositoryProvider'), {
      pantallaFiesta,
      pantallaPlano,
      'lib/features/plano/repositories/planos_evento_repository.dart',
    });
    expect(archivosCon('PlanosEventoRepository.guardarEn('), {
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
    expect(archivosCon('MesasMovimientosRepository.registrarEn('), {
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
    // En la fiesta el plano solo se lee: guardarlo, lo guarda el sorteo junto
    // con los números, por `asignarNumerosMesa`.
    expect(leer(pantallaFiesta), isNot(contains('planos.guardar(')));
  });

  test('Editar alumno: acompañantes y música pasan por la llave', () {
    final fuente =
        leer('lib/features/eventos/widgets/modal_alumno_premium.dart');
    final guardar = fuente.substring(fuente.indexOf('void _submit() async {'));
    final hastaElDibujo = guardar.substring(0, guardar.indexOf('Widget build('));
    // Al guardar, lo escrito en la ficha se lee en un solo lugar: lo que se le
    // pasa a cada llave, que sin modo jefe devuelve lo que el alumno ya tenía.
    expect(
      hastaElDibujo,
      contains('''
      final acompanantes = acompanantesParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.nombresAcompanantes,
        escritos: _acompanantes,
      );'''),
    );
    expect(
      hastaElDibujo,
      contains('''
      final musica = musicaParaGuardar(
        esJefe: ref.read(esRolJefeProvider),
        antes: widget.alumno?.musicaElegida,
        escrita: _musicaElegidaCtrl.text,
      ).trim();'''),
    );
    expect(
      RegExp(r'_musicaElegidaCtrl\.text').allMatches(hastaElDibujo).length,
      1,
      reason: 'la música se lee por fuera de musicaParaGuardar',
    );
    expect(
      RegExp(r'\b_acompanantes\b').allMatches(hastaElDibujo).length,
      1,
      reason: 'los acompañantes se leen por fuera de acompanantesParaGuardar',
    );
    // En la ficha, sin modo jefe no se agregan ni se sacan.
    expect(fuente, contains('enabled: esJefe,'));
    expect(fuente, contains('onPressed: !esJefe'));
    expect(fuente, contains('onDeleted: !esJefe'));
  });

  test('el Excel del delegado lo carga solo el jefe, con las tres llaves', () {
    // 1. El renglón de PLANILLAS llega apagado sin modo jefe.
    final barra =
        leer('lib/features/eventos/widgets/grupo_fiesta_toolbar.dart');
    expect(barra, contains('accion: esJefe ? onAcompanantesYMusica : null,'));

    final fiesta = leer(pantallaFiesta);
    final i = fiesta.indexOf('Future<void> _abrirAcompanantesYMusica() async {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fiesta.substring(i, fiesta.indexOf('\n  }\n', i));
    // 2. Al abrir.
    expect(cuerpo, contains('if (!ref.read(esRolJefeProvider)) return soloJefe();'));
    // 3. Otra vez justo antes de guardar, y antes que el guardado.
    final llave = cuerpo.indexOf('''
          if (!ref.read(esRolJefeProvider)) {
            throw StateError(kSoloEnModoJefe);
          }''');
    expect(llave, greaterThanOrEqualTo(0));
    expect(
      cuerpo.indexOf('cargarAcompanantesYMusica('),
      greaterThan(llave),
    );
  });

  test('nadie más carga acompañantes y música de a muchos', () {
    final quienes = {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('cargarAcompanantesYMusica('))
          f.path.replaceAll('\\', '/'),
    };
    expect(quienes, {
      pantallaFiesta,
      'lib/features/eventos/repositories/contratos_repository.dart',
    });
  });
}
