import 'dart:convert';

import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/puerta_en_memoria.dart';

/// La lista de la puerta viaja de la central al celular (`toJson` y
/// `fromJson`): del otro lado tiene que verse y buscarse igual.
PuertaDelEvento _ida(PuertaDelEvento p, String eventoId) =>
    PuertaDelEvento.fromJson(
      jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
      eventoId: eventoId,
    );

List<String> _ids(Iterable<GrupoPuerta> grupos) =>
    [for (final g in grupos) for (final p in g.personas) p.id];

void main() {
  const c1 = 'c1000000-0000-4000-8000-000000000001';
  const c2 = 'c2000000-0000-4000-8000-000000000002';
  const c3 = 'c3000000-0000-4000-8000-000000000003';

  final alumnos = [
    alumnoDePrueba(c1, 'PÉREZ, JUAN',
        mesas: [12, 13], extras: 1, sillas: 2, acomp: ['GÓMEZ, ANA'],
        musica: 'Tusa · Karol G'),
    alumnoDePrueba(c2, 'ACOSTA, LUCÍA', mesas: [14], division: '5° A'),
    alumnoDePrueba(c3, 'BENÍTEZ, TOMÁS'),
  ];
  final juan = idInvitadoPuerta(c1, 0);
  final ana = idInvitadoPuerta(c1, 1);
  final filas = [
    Invitado(
      id: juan,
      eventoId: eventoMasivo,
      nombreCompleto: 'PÉREZ, JUAN',
      dni: '',
      numeroMesa: '12-13',
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: horaDeIngreso,
    ),
    Invitado(
      id: ana,
      eventoId: eventoMasivo,
      nombreCompleto: 'GÓMEZ, ANA',
      dni: '',
      numeroMesa: '12-13',
      estadoIngreso: EstadoIngreso.pendiente,
    ),
    Invitado(
      id: 'a-mano-1',
      eventoId: eventoMasivo,
      nombreCompleto: 'RUIZ, MARTA',
      dni: '30111222',
      numeroMesa: '40',
      estadoIngreso: EstadoIngreso.pendiente,
    ),
  ];
  final masivo = PuertaDelEvento.masivo(
    alumnos: alumnos,
    repartos: {
      c1: SillasReparto(
        id: 'r1',
        contratoAlumnoId: c1,
        sillasPrincipal: 1,
        sillasExtra: 2,
        mesas: 2,
        createdAt: horaDeIngreso,
        updatedAt: horaDeIngreso,
      ),
    },
    invitados: filas,
    sillasPuerta: [
      SillaPuerta(
        id: 'sp1',
        eventoId: eventoMasivo,
        contratoAlumnoId: c1,
        mesa: 13,
        vale: '0012',
        anotadoPor: 'Pato',
        nota: 'la abuela',
        createdAt: horaDeIngreso,
        updatedAt: horaDeIngreso,
      ),
      SillaPuerta(
        id: 'sp2',
        eventoId: eventoMasivo,
        contratoAlumnoId: c2,
        mesa: 14,
        vale: '0015',
        anotadoPor: 'Juli',
        createdAt: horaDeIngreso,
        updatedAt: horaDeIngreso,
      ).quitada(por: 'Juli', motivo: 'devolvieron el vale', ahora: horaDeIngreso),
    ],
  );

  test('las sillas de la noche llegan igual: las líneas, los movimientos y el '
      'conteo', () {
    final llego = _ida(masivo, eventoMasivo);
    expect(llego.conteoDeLaNoche.texto, masivo.conteoDeLaNoche.texto);
    expect(llego.conteoDeLaNoche.texto, contains('vale 0012'));
    for (var i = 0; i < masivo.grupos.length; i++) {
      final a = masivo.grupos[i];
      final b = llego.grupos[i];
      expect(b.contratoId, a.contratoId);
      expect(b.puedeSumarSilla, a.puedeSumarSilla);
      expect([for (final m in b.sillasPorMesa.mesas) m.texto],
          [for (final m in a.sillasPorMesa.mesas) m.texto]);
      expect([for (final s in b.movimientos) s.toMap()],
          [for (final s in a.movimientos) s.toMap()]);
    }
    final juan = llego.grupos.firstWhere((g) => g.contratoId == c1);
    expect(juan.movimientos.single.nota, 'la abuela');
  });

  test('una lista de una central más vieja, sin las sillas, se lee igual', () {
    final json = jsonDecode(jsonEncode(masivo.toJson())) as Map<String, dynamic>;
    json.remove('conteo');
    for (final g in json['grupos'] as List) {
      (g as Map).remove('contrato');
      g.remove('sillasPorMesa');
      g.remove('movimientos');
    }
    final llego = PuertaDelEvento.fromJson(json, eventoId: eventoMasivo);
    expect(llego.total, masivo.total);
    expect(llego.conteoDeLaNoche.texto, isNull);
    expect(llego.grupos.every((g) => g.sillasPorMesa.vacia), isTrue);
    expect(llego.grupos.every((g) => !g.puedeSumarSilla), isTrue);
  });

  test('un masivo llega igual: grupos, mesas, sillas, música y quién entró',
      () {
    final llego = _ida(masivo, eventoMasivo);

    expect(llego.masivo, isTrue);
    expect(llego.sorteado, masivo.sorteado);
    expect(llego.bajas, masivo.bajas);
    expect(llego.total, masivo.total);
    expect(llego.adentro, 1);
    expect(_ids(llego.grupos), _ids(masivo.grupos));

    for (var i = 0; i < masivo.grupos.length; i++) {
      final a = masivo.grupos[i];
      final b = llego.grupos[i];
      expect(b.division, a.division);
      expect(b.sinMesa, a.sinMesa);
      expect(b.sillas, a.sillas);
      expect(b.sillasAConfirmar, a.sillasAConfirmar);
      expect(b.musica, a.musica);
      expect(b.acompanantesSinNombre, a.acompanantesSinNombre);
      expect(b.cargadoAMano, a.cargadoAMano);
      for (var j = 0; j < a.personas.length; j++) {
        final x = a.personas[j];
        final y = b.personas[j];
        expect(y.nombre, x.nombre);
        expect(y.dni, x.dni);
        expect(y.mesa, x.mesa);
        expect(y.esAlumno, x.esAlumno);
        expect(y.acompanaA, x.acompanaA);
        expect(y.ingresado, x.ingresado);
        expect(y.textoHora, x.textoHora);
        expect(y.fila == null, x.fila == null);
        expect(y.iniciales, x.iniciales);
      }
    }
  });

  test('del otro lado se busca igual: por nombre en cualquier orden, por mesa '
      'y por DNI', () {
    final llego = _ida(masivo, eventoMasivo);
    for (final consulta in ['juan perez', '13', '12', 'gomez', '30111', 'z']) {
      expect(_ids(llego.buscar(consulta)), _ids(masivo.buscar(consulta)),
          reason: consulta);
    }
    expect(_ids(llego.buscar('', filtro: FiltroPuerta.adentro)),
        _ids(masivo.buscar('', filtro: FiltroPuerta.adentro)));
    expect(llego.alApretarEnter('perez').aviso,
        masivo.alApretarEnter('perez').aviso);
  });

  test('quien no tiene fila todavía sigue sin fila (se crea al ingresarlo)', () {
    final llego = _ida(masivo, eventoMasivo);
    final tomas =
        llego.personas.firstWhere((p) => p.id == idInvitadoPuerta(c3, 0));
    expect(tomas.fila, isNull);
    expect(tomas.ingresado, isFalse);
  });

  test('un particular también', () {
    final particular = PuertaDelEvento.particular([
      Invitado(
        id: 'p1',
        eventoId: eventoParticular,
        nombreCompleto: 'LÓPEZ, ROSA',
        dni: '28999111',
        numeroMesa: '3',
        estadoIngreso: EstadoIngreso.ingresado,
        updatedAt: horaDeIngreso,
      ),
      Invitado(
        id: 'p2',
        eventoId: eventoParticular,
        nombreCompleto: 'DÍAZ, PEDRO',
        dni: '31000222',
        estadoIngreso: EstadoIngreso.pendiente,
      ),
    ]);
    final llego = _ida(particular, eventoParticular);
    expect(llego.masivo, isFalse);
    expect(llego.total, 2);
    expect(llego.adentro, 1);
    expect(_ids(llego.buscar('28999')), ['p1']);
    expect(llego.personas.first.fila!.eventoId, eventoParticular);
    expect(llego.grupos.every((g) => g.cargadoAMano), isTrue);
  });
}
