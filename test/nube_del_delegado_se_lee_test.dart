// Lo que contesta la nube del link del delegado, **leído por el programa**.
//
// Las pantallas se prueban con un doble en memoria que arma los objetos a mano,
// así que nada comprobaba que el programa leyera bien el JSON de verdad: una
// rotura a propósito (leer `sin_enviar` como enviado, o `vencido` como abierto)
// pasaba todas las pruebas.
//
// `test/datos/nube_del_delegado.json` son las respuestas del SQL de verdad en
// una historia fija. Las saca `tool/delegado_sandbox/muestras.mjs` del Postgres
// de prueba, y `pruebas.mjs` (M1) falla si el archivo ya no es lo que contesta
// el SQL. Si cambia el SQL: `node muestras.mjs` y esta prueba dice si el
// programa lo sigue leyendo bien.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/delegado/datos/link_del_delegado.dart';
import 'package:arguello_events/features/delegado/datos/nube_del_delegado.dart';

void main() {
  final m = (jsonDecode(File('test/datos/nube_del_delegado.json').readAsStringSync())
          as Map)
      .cast<String, dynamic>();
  Map<String, dynamic> de(String clave) => (m[clave] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> lista(String clave) => [
        for (final x in m[clave] as List) (x as Map).cast<String, dynamic>(),
      ];

  group('la página del delegado', () {
    ListaDelDelegado l(String clave) => ListaDelDelegado.fromJson(de(clave));
    AlumnoDelLink alumno(ListaDelDelegado l, String nombre) =>
        l.alumnos.singleWhere((a) => a.nombre == nombre);

    test('un link que no existe, apagado, o de alguien que se sacó', () {
      expect([l('lista_link_malo').ok, l('lista_link_malo').motivo], [false, 'link']);
      expect(l('lista_link_malo').fiesta, '', reason: 'no dice de qué fiesta es');
      expect(l('lista_apagado').motivo, 'apagado');
      expect(l('lista_apagado').alumnos, isEmpty);
      expect(l('lista_sacado').motivo, 'sacado');
      expect(l('lista_sacado').alumnos, isEmpty);
    });

    test('antes de entrar: la fiesta, hasta cuándo, si está lleno y quiénes '
        'ya entraron, sin ningún alumno', () {
      final nadie = l('lista_sin_nadie');
      expect([nadie.ok, nadie.motivo, nadie.lleno], [false, 'entrar', false]);
      expect(nadie.fiesta, 'Escuela Normal · Promo 2026');
      expect(nadie.venceTexto, 'jueves 19/11 a las 20:00');
      expect(nadie.delegados, isEmpty);

      final lleno = l('lista_para_entrar');
      expect(lleno.lleno, isTrue);
      expect(lleno.delegados, ['LAURA GÓMEZ', 'PEDRO SOSA']);
      expect(lleno.alumnos, isEmpty);
    });

    test('adentro: quién soy, cuándo envié, cuánto me queda sin enviar y la '
        'cuenta', () {
      final a = l('lista_adentro');
      expect(a.ok, isTrue);
      expect(a.yoNombre, 'LAURA GÓMEZ');
      expect([a.yoEntregado, a.yoEnvioTexto, a.yoSinEnviar], [true, 'jue 12/11 15:00', 1]);
      expect([a.total, a.cargados, a.faltan, a.mios], [12, 5, 7, 3]);
      expect([a.vencido, a.soloLectura], [false, false], reason: 'enviar no cierra');
      expect(a.alumnos, hasLength(12));
    });

    test('cada alumno: de quién es, en qué quedó, quién lo cargó y cuándo', () {
      final a = l('lista_adentro');
      List<Object?> de(String n) {
        final x = alumno(a, n);
        return [x.de, x.estado, x.cargo, x.cuandoTexto];
      }

      expect(de('ACOSTA, LUCÍA'),
          [DeQuien.otro, EstadoDeLaCarga.sinEnviar, 'PEDRO SOSA', 'jue 12/11 16:00']);
      expect(de('ÁLVAREZ, BRUNO'),
          [DeQuien.mio, EstadoDeLaCarga.enviado, 'LAURA GÓMEZ', 'jue 12/11 15:00']);
      expect(de('BENÍTEZ, MATEO'), [DeQuien.libre, EstadoDeLaCarga.falta, null, null]);
      expect(de('CABRERA, SOFÍA'),
          [DeQuien.mio, EstadoDeLaCarga.aceptado, 'LAURA GÓMEZ', 'jue 12/11 15:00']);
      expect(de('ESCOBAR, VALENTINA'),
          [DeQuien.mio, EstadoDeLaCarga.sinEnviar, 'LAURA GÓMEZ', 'jue 12/11 16:00']);
    });

    test('lo vigente: lo cargado por el link y, en el casillero vacío, lo del '
        'programa', () {
      final a = l('lista_adentro');
      final acosta = alumno(a, 'ACOSTA, LUCÍA');
      expect([acosta.progAcomp, acosta.progMusica], [true, true]);
      expect(acosta.acompanantes, ['ACOSTA, JORGE', 'RÍOS, MARTA']);
      expect(acosta.musica, 'Corregido por Pedro');
      expect(acosta.esDeOtro, isTrue, reason: 'avisa antes de corregirlo');
      expect(acosta.rotuloDeCargado, 'Ya cargado · PEDRO SOSA · jue 12/11 16:00');

      final benitez = alumno(a, 'BENÍTEZ, MATEO');
      expect([benitez.progAcomp, benitez.progMusica, benitez.cargado], [true, false, false]);
      expect(benitez.acompanantes, ['BENÍTEZ, CARLA']);

      final alvarez = alumno(a, 'ÁLVAREZ, BRUNO');
      expect(alvarez.acompanantes, ['ÁLVAREZ, EVA']);
      expect([alvarez.musica, alvarez.esDeOtro], ['Tema de Laura', false]);
    });

    test('vencido: adentro, con todo a la vista y sin poder cargar', () {
      final v = l('lista_vencido');
      expect([v.ok, v.vencido, v.soloLectura], [true, true, true]);
      expect(v.alumnos, hasLength(12));
    });

    test('lo que contestan entrar, guardar y enviar', () {
      RespuestaDelegado r(String clave) => RespuestaDelegado.fromJson(de(clave));
      expect([r('entrar_ok').ok, r('entrar_ok').sesion], [true, 'SESION-LAURA']);
      expect(r('entrar_nombre').motivo, 'nombre');
      expect(r('entrar_lleno').motivo, 'lleno');
      expect(r('entrar_sacado').motivo, 'sacado');

      expect([r('guardar_ok').ok, r('guardar_ok').libre], [true, false]);
      expect([r('guardar_libre').ok, r('guardar_libre').libre], [true, true]);
      expect(r('guardar_vacio').motivo, 'vacio');
      expect(r('guardar_tope').motivo, 'tope');
      expect([r('guardar_largo').motivo, r('guardar_largo').campo], ['largo', 'musica']);
      expect(r('guardar_vencido').motivo, 'vencido');

      expect([r('entregar_ok').ok, r('entregar_ok').ya], [true, false]);
      expect([r('entregar_ya').ok, r('entregar_ya').ya], [true, true]);
      expect([r('entregar_nada').ok, r('entregar_nada').motivo], [false, 'nada']);
    });
  });

  group('la ventana del link, en el programa', () {
    EstadoDelLink e(String clave) => EstadoDelLink.fromJson(de(clave));

    test('sin link, abierto, cerrado a mano y vencido', () {
      expect(e('link_sin').hay, isFalse);
      expect([e('link_abierto').estado, e('link_abierto').abierto], [EstadoLink.abierto, true]);
      expect([e('link_apagado').estado, e('link_apagado').abierto], [EstadoLink.apagado, false]);
      expect([e('link_vencido').estado, e('link_vencido').abierto], [EstadoLink.vencido, false]);
    });

    test('la clave, el límite, el cupo y la cuenta de cada estado', () {
      final a = e('link_abierto');
      expect([a.clave, a.cupo], ['CLAVE', 2]);
      expect([a.venceTexto, a.venceLocal], ['jueves 19/11 a las 20:00', '2026-11-19 20:00']);
      expect(
        [a.total, a.enPrograma, a.cargados, a.faltan, a.sinEnviar, a.enviados, a.aceptados],
        [12, 0, 4, 7, 3, 1, 1],
      );
    });

    test('el aviso: lo enviado sin traer, y al vencer lo que nadie envió', () {
      expect(e('link_abierto').aviso, contains('envió LAURA GÓMEZ (1)'));
      expect(
        e('link_vencido').aviso,
        contains('venció sin enviar: LAURA GÓMEZ (cargó 1), PEDRO SOSA (cargó 2)'),
      );
      final p = lista('pendientes').single;
      expect(p['evento_id'], 'aaaaaaaa-0000-4000-8000-000000000001');
      expect('${p['texto']}', contains('envió LAURA GÓMEZ (2)'));
    });

    test('los delegados, por persona', () {
      final d = e('link_abierto').delegados;
      expect(d.map((x) => x.nombre), ['LAURA GÓMEZ', 'PEDRO SOSA']);
      final laura = d.first, pedro = d.last;
      expect([laura.id, laura.aparatos, laura.cargados, laura.sinEnviar], ['celular-1', 1, 3, 1]);
      expect([laura.entroTexto, laura.envioTexto, laura.sacado],
          ['jue 12/11 15:00', 'jue 12/11 15:00', false]);
      expect([pedro.id, pedro.cargados, pedro.sinEnviar, pedro.envioTexto],
          ['celular-2', 2, 2, null]);
      expect(e('link_con_sacado').delegados.last.sacado, isTrue);
      // Los celulares, uno por aparato: los sigue mandando para la versión
      // anterior del programa.
      final c = e('link_con_sacado').celulares;
      expect(c.map((x) => [x.id, x.nombre, x.cargados, x.entregado, x.sacado]), [
        ['celular-1', 'LAURA GÓMEZ', 3, true, false],
        ['celular-2', 'PEDRO SOSA', 2, false, true],
      ]);
      expect([c.first.entroTexto, c.first.entregadoTexto, c.last.entregadoTexto],
          ['jueves 12/11 a las 15:00', 'jueves 12/11 a las 15:00', null]);
    });

    test('lo cargado para traer: quién, cuándo, si está enviado y si ya se '
        'trajo', () {
      final c = {
        for (final x in lista('cargas').map(CargaDelDelegado.fromJson)) x.alumno: x,
      };
      final acosta = c['ACOSTA, LUCÍA']!;
      expect([acosta.entregado, acosta.traido, acosta.activo], [false, false, true]);
      expect(acosta.quienYCuando, 'Lo cargó PEDRO SOSA · jue 12/11 16:00');
      expect([acosta.musica, acosta.acompanantes], ['Corregido por Pedro', <String>[]]);
      expect(acosta.alumnoId, 'a0000000-0000-4000-8000-000000000001');
      expect([c['ÁLVAREZ, BRUNO']!.entregado, c['ÁLVAREZ, BRUNO']!.traido], [true, false]);
      expect(c['ÁLVAREZ, BRUNO']!.acompanantes, ['ÁLVAREZ, EVA']);
      expect([c['CABRERA, SOFÍA']!.entregado, c['CABRERA, SOFÍA']!.traido], [true, true]);
      expect(c['CABRERA, SOFÍA']!.division, '6° A');
    });

    test('la lista ALUMNOS: el estado de cada uno, quién lo cargó y si corrige '
        'algo que ya estaba', () {
      final t = {
        for (final x in lista('alumnos_estado').map(AlumnoDelTablero.fromJson)) x.alumno: x,
      };
      expect(t, hasLength(12));
      List<Object?> de(String n) =>
          [t[n]!.estado, t[n]!.cargo, t[n]!.delegadoId, t[n]!.otraVez];
      expect(de('ACOSTA, LUCÍA'), [EstadoDeLaCarga.sinEnviar, 'PEDRO SOSA', 'celular-2', true]);
      expect(de('ÁLVAREZ, BRUNO'), [EstadoDeLaCarga.enviado, 'LAURA GÓMEZ', 'celular-1', false]);
      expect(de('BENÍTEZ, MATEO'), [EstadoDeLaCarga.falta, null, null, false]);
      expect(de('CABRERA, SOFÍA'), [EstadoDeLaCarga.aceptado, 'LAURA GÓMEZ', 'celular-1', false]);
      expect(t['ACOSTA, LUCÍA']!.cuandoTexto, 'jue 12/11 16:00');
      expect(t['ACOSTA, LUCÍA']!.acompanantes, ['ACOSTA, JORGE', 'RÍOS, MARTA']);
      expect([t['ACOSTA, LUCÍA']!.division, t['ACOSTA, LUCÍA']!.musica], ['6° A', 'Corregido por Pedro']);
    });

    test('el historial: quién hizo qué y cuándo, en palabras', () {
      final h = lista('historial').map(CambioDelHistorial.fromJson).toList();
      expect(h.first.quien, 'LAURA GÓMEZ');
      expect(h.first.cuandoTexto, 'jue 12/11 15:00');
      expect(h.first.alumnoId, 'a0000000-0000-4000-8000-000000000002');
      expect(h.first.enPalabras, 'Guardó: ÁLVAREZ, EVA — Música: Tema de Laura');
      final aceptado = h.singleWhere((x) => x.que == 'aceptado');
      expect([aceptado.quien, aceptado.enPalabras],
          ['Junior Eventos', 'Aceptado y cargado en el programa']);
      final vacio = h.singleWhere((x) => x.que == 'vacio');
      expect([vacio.quien, vacio.enPalabras], ['LAURA GÓMEZ', 'Sacó lo que había cargado']);
      expect(h.map((x) => x.que).toSet(), {'guardo', 'aceptado', 'vacio'});
    });

    test('lo que contestan crear y cambiar', () {
      RespuestaDelegado r(String clave) => RespuestaDelegado.fromJson(de(clave));
      expect([r('crear').ok, r('crear').clave], [true, 'CLAVE']);
      expect(r('sacar').ok, isTrue);
      expect([r('cambiar_mal').ok, r('cambiar_mal').motivo], [false, 'accion']);
    });
  });
}
