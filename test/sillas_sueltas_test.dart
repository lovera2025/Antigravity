// Las sillas sueltas (6.5.0, pedido del usuario el 9-nov): las que no van a una
// mesa. La familia que ya está en el tope de 2 extra por mesa, o que quiere una
// silla al lado o en otro lugar, la compra igual: la barra la vende como "Silla
// suelta", con su vale, y la puerta la anota con su botón, sin tope. Va en
// `sillas_puerta` con la mesa en 0: sin columnas nuevas ni SQL.
import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/silla_de_la_puerta.dart';
import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/sillas_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/vales_anulados.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/puerta_en_memoria.dart' show alumnoDePrueba, eventoMasivo;

final _hora = DateTime.utc(2026, 12, 12, 23);

void main() {
  group('en la barra', () {
    test('"Silla suelta" es silla de la puerta, y suelta', () {
      for (final n in ['Silla suelta', 'SILLA SUELTA', 'Sillas sueltas']) {
        expect(esSillaDeLaPuerta(n), isTrue, reason: n);
        expect(esSillaSuelta(n), isTrue, reason: n);
      }
      for (final n in ['Silla extra', 'SILLA', 'Fernet']) {
        expect(esSillaSuelta(n), isFalse, reason: n);
      }
    });

    test('el vale de una suelta lo dice', () {
      final suelta = Vale.deUnaSilla(_renglon('Silla suelta'));
      final deMesa = Vale.deUnaSilla(_renglon('Silla extra'));
      expect(suelta.esDeSilla, isTrue);
      expect(suelta.esDeSillaSuelta, isTrue);
      expect(deMesa.esDeSillaSuelta, isFalse);
    });

    test('el cierre cuenta las de mesa y las sueltas aparte', () {
      final caja = _caja();
      final cierre = CierreDeBarra.de(caja, [
        _venta(caja, 1, [_renglon('Silla extra', cantidad: 2)]),
        _venta(caja, 2, [_renglon('Silla suelta'), _renglon('Fernet')]),
      ], const []);
      expect(cierre.sillas, 2);
      expect(cierre.sillasSueltas, 1);
      final resumen = ResumenDeCajas.de(
        cajas: [caja],
        ventas: [
          _venta(caja, 1, [_renglon('Silla suelta', cantidad: 3)]),
        ],
        anulaciones: const [],
      );
      expect(resumen.sillas, 0);
      expect(resumen.sillasSueltas, 3);
    });
  });

  group('en la puerta', () {
    const juli = 'c1000000-0000-4000-8000-000000000001';
    // PÉREZ, JULIANA: mesa 12 con sus 2 extra del contrato: ya en el tope.
    final alumna = alumnoDePrueba(juli, 'PÉREZ, JULIANA', mesas: [12], sillas: 2);
    final puerta = PuertaDelEvento.masivo(
      alumnos: [alumna],
      invitados: const [],
    );
    final grupo = puerta.grupos.single;

    var n = 0;
    SillaPuerta silla(int mesa, String vale) {
      n++;
      return SillaPuerta(
        id: 's$n',
        eventoId: eventoMasivo,
        contratoAlumnoId: juli,
        mesa: mesa,
        vale: vale,
        createdAt: _hora,
        updatedAt: _hora,
      );
    }

    PedidoPuerta suelta({String? vale = '2 0017'}) => PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: grupo.titular.id,
          silla: DatosSilla(vale: vale, suelta: true),
        );

    DecisionSilla decidir(
      PedidoPuerta p,
      List<SillaPuerta> base, {
      ValesAnulados anulados = ValesAnulados.ninguno,
    }) =>
        decidirSilla(
          pedido: p,
          grupo: grupo,
          deLaNoche: base,
          valesAnulados: anulados,
        );

    test('con la familia en el tope, la silla de mesa no entra y la suelta sí',
        () {
      expect(grupo.puedeSumarSilla, isFalse);
      final d = decidir(suelta(), const []);
      expect(d.hace, QueHaceLaCentral.sumarSilla);
      expect(d.mesa, SillaPuerta.mesaSuelta);
      expect(d.vale, '2-17');
      expect(d.aviso, isNull);
    });

    test('sin tope: se suman las que paguen', () {
      final base = [for (var i = 1; i <= 5; i++) silla(0, '2 $i')];
      expect(decidir(suelta(vale: '2 9'), base).hace,
          QueHaceLaCentral.sumarSilla);
    });

    test('sin vale, con el vale usado o anulado, no', () {
      expect(decidir(suelta(vale: null), const []).hace, QueHaceLaCentral.nada);
      expect(decidir(suelta(), [silla(12, '2-17')]).aviso,
          'El vale 2-17 ya se usó para otra silla.');
      expect(
        decidir(suelta(), const [],
                anulados: ValesAnulados.fromJson(const ['2-17']))
            .aviso,
        'El vale 2-17 está anulado en la barra.',
      );
    });

    test('una suelta no es "fuera de sus mesas" ni ocupa lugar en la mesa', () {
      final familia = SillasDeLaFamilia.de(alumna, null, [silla(0, '2-30')]);
      expect(familia.mesas.map((m) => m.numero), [12]);
      expect(familia.mesas.single.sumadas, 0);
      expect(familia.mesas.single.estado, EstadoMesaPuerta.llena);
    });

    test('lo que se dice y lo que se cuenta esa noche', () {
      final s = silla(0, '2-30');
      expect(textoSillaSumada(s), startsWith('+1 silla suelta · vale 2-30'));
      expect(
        textoSillaHecha(sumar: true, mesa: 0, nombre: 'PÉREZ, JULIANA'),
        'Silla suelta anotada para PÉREZ, JULIANA.',
      );
      expect(
        textoSillaHecha(sumar: false, mesa: 0, nombre: 'PÉREZ, JULIANA'),
        'Silla suelta quitada de PÉREZ, JULIANA.',
      );
      final conteo = ConteoDeLaNoche.de([silla(12, '2-31'), s]);
      expect(conteo.sumadas, 2);
      expect(conteo.sueltas, 1);
      expect(conteo.texto, startsWith('Esta noche: 2 sillas sumadas (1 suelta)'));
      expect(ConteoDeLaNoche.fromJson(conteo.toJson())!.sueltas, 1);
    });

    test('el pedido viaja con "suelta"', () {
      final datos = DatosSilla.fromJson(
        const DatosSilla(vale: '2 17', suelta: true).toJson(),
      )!;
      expect(datos.suelta, isTrue);
      expect(DatosSilla.fromJson(const {'vale': '1'})!.suelta, isFalse);
    });

    test('ningún armado numera una mesa 0', () {
      for (final a in [
        ArmadosPredefinidos.normal2aPagina3(),
      ]) {
        expect(a.existe(SillaPuerta.mesaSuelta), isFalse);
      }
    });
  });
}

RenglonVenta _renglon(String nombre, {int cantidad = 1}) => RenglonVenta(
      productoId: nombre,
      nombre: nombre,
      precio: 8000,
      cantidad: cantidad,
    );

CajaBarra _caja() => CajaBarra.abrir(
      eventoId: eventoMasivo,
      operadorNombre: 'Caja 2',
      numeroCaja: 2,
      cambioInicial: 20000,
      ahora: _hora,
    );

VentaBarra _venta(CajaBarra caja, int numero, List<RenglonVenta> r) =>
    VentaBarra.nueva(
      cajaBarraId: caja.id,
      eventoId: eventoMasivo,
      numero: numero,
      renglones: r,
      medio: MedioBarra.efectivo,
      efectivo: CuentaBarra(r).total,
      transferencia: 0,
      ahora: _hora,
    );
