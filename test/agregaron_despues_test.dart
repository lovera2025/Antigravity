// Quiénes agregaron una mesa adicional o sillas extra después del sorteo
// (pedido del usuario, 27-nov-2026): el programa lo sabe solo, comparando lo
// cargado hoy con lo anotado al sortear, y VENDER lo avisa al entrar. Con el
// descuento va solo lo que la familia ya tenía cargado al sorteo, pagado o no.
//
// Todo puro: sin pantalla, sin base, sin reloj.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/agregaron_despues.dart';
import 'package:arguello_events/features/eventos/services/lugares_al_sorteo.dart';
import 'package:arguello_events/features/eventos/services/lugares_pagos.dart';
import 'package:arguello_events/features/eventos/services/retiro_entradas.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

// 12/11/2026 21:40 en Argentina.
final _sorteoEl = DateTime.utc(2026, 11, 13, 0, 40);

ContratoAlumno _alumno(
  String id, {
  int extras = 0,
  int sillas = 0,
  int acompanantes = 0,
  String? nombre,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre ?? 'ALUMNO $id',
      cantidadAcompanantes: acompanantes,
      montoTotalPactado: 300000 + 70000.0 * extras + 8000.0 * sillas,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      createdAt: DateTime.utc(2026, 3, 1),
    );

/// La foto: lo que cada familia tenía al sorteo (mesas con la del contrato).
FotoDeLosLugares _foto(Map<String, (int, int)> alSorteo) => FotoDeLosLugares.anotada(
      {for (final e in alSorteo.entries) e.key: LugaresCargados(e.value.$1, e.value.$2)},
      sorteoEl: _sorteoEl,
    );

SorteoMesasRegistro _sorteo({Map<String, String>? lugares}) => SorteoMesasRegistro(
      id: 's',
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: const {'a': '12'},
      lugares: lugares,
      hechoPor: 'Jefe',
      createdAt: _sorteoEl,
    );

void main() {
  group('quién agregó después del sorteo', () {
    test('quien tiene lo mismo que al sorteo no figura', () {
      final r = AgregaronDespues.de(
        foto: _foto({'a': (2, 1)}),
        alumnos: [_alumno('a', extras: 1, sillas: 1), _alumno('b')],
      );
      expect(r.hay, isFalse);
      expect(r.familias, isEmpty);
      expect(r.sinAnotar, isFalse);
    });

    test('la mesa adicional cargada después: 1 mesa, sus 8 entradas', () {
      final r = AgregaronDespues.de(
        foto: _foto({}),
        alumnos: [_alumno('a', extras: 1)],
      );
      final f = r.familias.single;
      expect(f.id, 'a');
      expect((f.mesas, f.sillas, f.entradas), (1, 0, 8));
      expect(f.queAgrego, '1 mesa adicional');
      expect(f.cuantasEntradas, '8 entradas');
    });

    test('las sillas cargadas después: una entrada por silla', () {
      final r = AgregaronDespues.de(
        foto: _foto({'a': (2, 0)}),
        alumnos: [_alumno('a', extras: 1, sillas: 2)],
      );
      final f = r.familias.single;
      expect((f.mesas, f.sillas, f.entradas), (0, 2, 2));
      expect(f.queAgrego, '2 sillas extra');
      expect(f.cuantasEntradas, '2 entradas');
    });

    test('solo cuenta lo de más: tenía 1 mesa adicional y 1 silla, hoy 2 y 3', () {
      final r = AgregaronDespues.de(
        foto: _foto({'a': (2, 1)}),
        alumnos: [_alumno('a', extras: 2, sillas: 3)],
      );
      final f = r.familias.single;
      expect((f.mesas, f.sillas, f.entradas), (1, 2, 10));
      expect(f.queAgrego, '1 mesa adicional y 2 sillas extra');
    });

    test('una sola silla: "1 silla extra", "1 entrada"', () {
      final f = AgregaronDespues.de(
        foto: _foto({}),
        alumnos: [_alumno('a', sillas: 1)],
      ).familias.single;
      expect(f.queAgrego, '1 silla extra');
      expect(f.cuantasEntradas, '1 entrada');
    });

    test('quien no figura en la foto tenía solo la mesa del contrato '
        '(también quien entró a la fiesta después del sorteo)', () {
      final r = AgregaronDespues.de(
        foto: _foto({'otro': (2, 0)}),
        alumnos: [_alumno('nuevo', extras: 1, sillas: 1)],
      );
      expect((r.familias.single.mesas, r.familias.single.sillas), (1, 1));
    });

    test('quien sacó lo que tenía y lo volvió a cargar no figura: lo tenía al sorteo', () {
      final r = AgregaronDespues.de(
        foto: _foto({'a': (2, 2)}),
        alumnos: [_alumno('a', extras: 1, sillas: 2)],
      );
      expect(r.hay, isFalse);
    });

    test('quien hoy tiene menos que al sorteo no figura', () {
      final r = AgregaronDespues.de(
        foto: _foto({'a': (3, 2)}),
        alumnos: [_alumno('a', extras: 1)],
      );
      expect(r.hay, isFalse);
    });

    test('en orden alfabético, y `de` encuentra a cada uno', () {
      final r = AgregaronDespues.de(
        foto: _foto({}),
        alumnos: [
          _alumno('z', sillas: 1, nombre: 'ULMO, CELIA'),
          _alumno('y', extras: 1, nombre: 'CEIBO, ANA'),
          _alumno('x', nombre: 'TIPA, GASTON'),
        ],
      );
      expect([for (final f in r.familias) f.alumno.nombreAlumno], ['CEIBO, ANA', 'ULMO, CELIA']);
      expect(r.de('y')?.mesas, 1);
      expect(r.de('x'), isNull);
    });

    test('los VIP que no entran en la mesa del contrato ocupan lo agregado: '
        'esas entradas no se compran', () {
      // 9 acompañantes + el egresado = 10 con cena: 2 pasan de la mesa del
      // contrato y ocupan las 2 sillas cargadas después.
      final r = AgregaronDespues.de(
        foto: _foto({}),
        alumnos: [_alumno('a', sillas: 2, acompanantes: 9)],
      );
      final f = r.familias.single;
      expect((f.sillas, f.entradas), (2, 0));
      expect(f.cuantasEntradas, 'sin entradas para comprar');
    });

    test('la firma cambia si cambia quién o qué', () {
      final foto = _foto({});
      final una = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 1)]);
      final igual = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 1)]);
      final mas = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 1, sillas: 1)]);
      final otra = AgregaronDespues.de(
        foto: foto,
        alumnos: [_alumno('a', extras: 1), _alumno('b', sillas: 1)],
      );
      expect(una.firma, igual.firma);
      expect(una.firma, isNot(mas.firma));
      expect(una.firma, isNot(otra.firma));
    });
  });

  group('dice lo mismo que lo que el programa cobra sin descuento', () {
    test('por alumno, las entradas son las sin descuento de A PAGAR y de la entrega', () {
      final foto = _foto({'a': (2, 1), 'b': (1, 0), 'c': (1, 2)});
      final alumnos = [
        _alumno('a', extras: 2, sillas: 3),
        _alumno('b', extras: 1, sillas: 2, acompanantes: 9),
        _alumno('c', sillas: 2),
        _alumno('d', extras: 3, sillas: 1, acompanantes: 12),
        _alumno('e'),
      ];
      final r = AgregaronDespues.de(foto: foto, alumnos: alumnos);
      for (final a in alumnos) {
        final sinDescuento = APagarDeLaFamilia.de(a, pagos: const [], foto: foto).sinDescuento;
        final cosasDeDespues = RetiroEntradas.entradasDe(a, foto: foto).cosas.where((c) => !c.alSorteo);
        expect(r.de(a.id)?.entradas ?? 0, sinDescuento, reason: 'A PAGAR de ${a.id}');
        expect(r.de(a.id)?.entradas ?? 0, RetiroEntradas.entradasDe(a, foto: foto).sinDescuento,
            reason: 'la entrega de ${a.id}');
        // Figura todo el que tiene algo cargado después, aunque no compre nada.
        expect(r.de(a.id) != null, cosasDeDespues.isNotEmpty, reason: 'figura ${a.id}');
      }
      expect([for (final f in r.familias) f.id], ['a', 'b', 'd']);
    });
  });

  group('sin lo anotado al sorteo', () {
    test('sin sorteo: nadie, y no es "sin anotar"', () {
      final r = AgregaronDespues.de(
        foto: FotoDeLosLugares.sinSorteo,
        alumnos: [_alumno('a', extras: 1, sillas: 2)],
      );
      expect(r.hay, isFalse);
      expect(r.sinAnotar, isFalse);
      expect(r.sorteoEl, isNull);
    });

    test('sorteada sin anotar: nadie (todo va con descuento), y lo dice', () {
      final foto = LugaresAlSorteo.vigente([_sorteo()]);
      expect(foto.estado, EstadoDeLosLugares.sinAnotar);
      final r = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 1, sillas: 2)]);
      expect(r.hay, isFalse);
      expect(r.sinAnotar, isTrue);
      expect(r.sorteoEl, _sorteoEl);
    });

    test('con lo anotado, lleva el día del sorteo', () {
      final foto = LugaresAlSorteo.vigente([_sorteo(lugares: const {'a': '2,0'})]);
      final r = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 1, sillas: 1)]);
      expect(r.sorteoEl, _sorteoEl);
      expect((r.familias.single.mesas, r.familias.single.sillas), (0, 1));
    });

    test('un texto que no se entiende no le saca el descuento a nadie', () {
      final foto = LugaresAlSorteo.vigente([_sorteo(lugares: const {'a': 'roto'})]);
      final r = AgregaronDespues.de(foto: foto, alumnos: [_alumno('a', extras: 4, sillas: 6)]);
      expect(r.hay, isFalse);
    });
  });

  test('nadie: la lista vacía de fábrica', () {
    expect(AgregaronDespues.nadie.hay, isFalse);
    expect(AgregaronDespues.nadie.sinAnotar, isFalse);
    expect(AgregaronDespues.nadie.firma, '');
  });
}
