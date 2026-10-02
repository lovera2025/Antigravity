// El plano del salón en papel: que salga una hoja por cada hoja del armado, en
// los tres estilos, con cualquier apellido, y que diga lo que tiene que decir.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/common/services/plano_pdf.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

import 'helpers/leer_pdf.dart';

ContratoAlumno alumno(
  String id,
  String nombre, {
  List<int> mesas = const [],
  String? division = '5° A',
  int sillas = 0,
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: mesas.length > 1 ? 70000.0 * (mesas.length - 1) : 0,
      mesaExtraCantidad: mesas.length > 1 ? mesas.length - 1 : 0,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

/// Una familia por mesa de [desde] a [hasta], con apellidos distintos.
List<ContratoAlumno> familias(int desde, int hasta, {String division = '5° A'}) =>
    [
      for (var n = desde; n <= hasta; n++)
        alumno('f$n', 'FAMILIA$n, ALUMNO', mesas: [n], division: division),
    ];

final _evento = Evento(
  id: 'e',
  clienteId: 'c',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 5),
  estado: EstadoEvento.planificacion,
  modalidad: 'masivo',
  cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE PRUEBA'),
);

final _cuando = DateTime(2026, 11, 13, 9, 15);

/// Con la letra de fábrica del paquete, para poder leer lo que escribió.
Future<Uint8List> sinLetras(
  PlanoDeLaFiesta plano, {
  EstiloPlano estilo = EstiloPlano.arquitecto,
  bool blancoYNegro = true,
  String? lineaSorteo,
}) =>
    PlanoPdf.construir(
      institucion: 'ESCUELA DE PRUEBA',
      plano: plano,
      estilo: estilo,
      lineaSorteo: lineaSorteo,
      blancoYNegro: blancoYNegro,
      generada: _cuando,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pagina3 = ArmadosPredefinidos.normal2aPagina3();
  ArmadoSalon aMedida(int cantidad) => ArmarAMedida.armar(
        OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: cantidad),
      ).armado;

  group('una hoja de papel por cada hoja del salón', () {
    test('los tres estilos, en color y en blanco y negro, con las letras de la app',
        () async {
      final plano = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano(
          fijadas: const {78: MesaFijada(alumnoId: 'fija')},
          libres: const {77: MesaLibre()},
          bloques: const [
            BloqueDivision('5A', 1, 40),
            BloqueDivision('5B', 41, 76),
          ],
        ),
        alumnos: [
          alumno('doble', 'GÓMEZ, SOFÍA', mesas: [1, 2], sillas: 2),
          ...familias(3, 40),
          alumno('dobleb', 'NÚÑEZ, IVÁN', mesas: [41, 42], division: '5° B'),
          ...familias(43, 76, division: '5° B'),
          alumno('fija', 'RÍOS, MATEO', division: '5° B'),
        ],
      );
      for (final estilo in EstiloPlano.values) {
        for (final bn in [false, true]) {
          final bytes = await PdfService.construirPlanoPdf(
            _evento,
            plano,
            estilo: estilo,
            blancoYNegro: bn,
            lineaSorteo: 'Sorteo del 12/11/2026 21:40 hs · Jefe',
            generada: _cuando,
          );
          expect(paginasDelPdf(bytes), 1, reason: '${estilo.name} bn=$bn');
        }
      }
    });

    test('un salón de dos hojas sale en dos hojas, ni una más', () async {
      final armado = ArmadosPredefinidos.normal2a2b();
      final plano = PlanoDeLaFiesta.desde(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: familias(1, armado.cantidadComunes),
      );
      for (final estilo in EstiloPlano.values) {
        final bytes = await PdfService.construirPlanoPdf(
          _evento,
          plano,
          estilo: estilo,
          generada: _cuando,
        );
        expect(paginasDelPdf(bytes), 2, reason: estilo.name);
      }
    });

    test('todos los armados de fábrica, vacíos y llenos', () async {
      for (final armado in ArmadosPredefinidos.todos) {
        for (final alumnos in [
          const <ContratoAlumno>[],
          familias(1, armado.mesas.last.numero),
        ]) {
          final bytes = await sinLetras(
            PlanoDeLaFiesta.desde(
              armado: armado,
              config: ConfigPlano.vacia,
              alumnos: alumnos,
            ),
          );
          expect(
            paginasDelPdf(bytes),
            armado.hojas.length,
            reason: '${armado.clave} con ${alumnos.length} familias',
          );
        }
      }
    });

    test('a medida, con el encabezado más largo (título, sorteo y medidas)',
        () async {
      final armado = aMedida(132);
      final plano = PlanoDeLaFiesta.desde(
        armado: armado,
        config: const ConfigPlano(
          titulo: 'Fiesta de egresados 2026',
          subtitulo: 'Promoción de los cincuenta años de la escuela',
        ),
        alumnos: familias(1, 132),
      );
      final bytes = await sinLetras(
        plano,
        lineaSorteo: 'Sorteo restaurado el 12/11/2026 21:40 hs · Jefe · '
            '12 cambios con motivo · 3 cambios a mano después',
      );
      expect(paginasDelPdf(bytes), 1);
    });
  });

  group('lo que dice el papel', () {
    test('los números, los apellidos y lo que mide el playón', () async {
      final armado = aMedida(60);
      final plano = PlanoDeLaFiesta.desde(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('a', 'GÓMEZ, SOFÍA', mesas: [1, 2]),
          alumno('b', 'ÑANDUBAY, TOMÁS', mesas: [3]),
        ],
      );
      final texto = contenidoDelPdf(await sinLetras(plano));
      expect(texto.contains('(GÓMEZ)'), isTrue, reason: '(GÓMEZ)');
      expect(texto.contains('(ÑANDUBAY)'), isTrue, reason: '(ÑANDUBAY)');
      // La segunda mesa de una familia no repite el apellido.
      expect('(GÓMEZ)'.allMatches(texto).length, 1);
      expect(texto.contains('(60)'), isTrue, reason: '(60)');
      // El hormigón queda cortado: sus medidas van en el encabezado.
      expect(texto.contains('frente'), isTrue, reason: 'frente');
      expect(texto.contains('costado'), isTrue, reason: 'costado');
      expect(texto.contains('aproximadas'), isTrue, reason: 'aproximadas');
    });

    test('un armado del Canva no habla del playón', () async {
      final plano = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: familias(1, 10),
      );
      final texto = contenidoDelPdf(await sinLetras(plano));
      expect(texto.contains('frente'), isFalse, reason: 'frente');
      expect(texto.contains('(78)'), isTrue, reason: '(78)');
    });

    test('con el pasto en uso, la leyenda dice que hay que avisar', () async {
      final armado = ArmadosPredefinidos.tecnica1a1b();
      final pasto = armado.pasto.first;
      final plano = PlanoDeLaFiesta.desde(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('p', 'PASTORE, LUZ', mesas: [pasto])],
      );
      final texto = contenidoDelPdf(await sinLetras(plano));
      expect(texto.contains('Pasto'), isTrue, reason: 'Pasto');
      expect(texto.contains('avisar'), isTrue, reason: 'avisar');
      expect(texto.contains('(PASTORE)'), isTrue, reason: '(PASTORE)');
    });

    test('sin pasto, libres ni fijadas, la leyenda no los nombra', () async {
      final plano = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: familias(1, 5),
      );
      final texto = contenidoDelPdf(await sinLetras(plano));
      expect(texto.contains('Pasto'), isFalse, reason: 'Pasto');
      expect(texto.contains('Libre'), isFalse, reason: 'Libre');
      expect(texto.contains('Fijada'), isFalse, reason: 'Fijada');
    });

    test('un apellido con signos que la letra no tiene no frena el PDF',
        () async {
      final plano = PlanoDeLaFiesta.desde(
        armado: pagina3,
        config: ConfigPlano.vacia,
        alumnos: [
          alumno('r', 'ŻÓŁĆ 😀 ΩMEGA, X', mesas: [1]),
          alumno('l', 'DE LA FUENTE Y GONZÁLEZ DEL VALLE, ANA', mesas: [2]),
          alumno('v', ', SIN APELLIDO', mesas: [3]),
        ],
      );
      // Con la letra de fábrica y con las de la app.
      expect(paginasDelPdf(await sinLetras(plano)), 1);
      for (final estilo in EstiloPlano.values) {
        final bytes = await PdfService.construirPlanoPdf(
          _evento,
          plano,
          estilo: estilo,
          generada: _cuando,
        );
        expect(paginasDelPdf(bytes), 1, reason: estilo.name);
      }
    });
  });

  group('los apellidos entran o no se escriben', () {
    test('con las mesas chicas no se escriben y el pie lo dice', () async {
      // El playón lleno no se recorta: las mesas quedan chicas.
      const opciones = OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 1,
      );
      final lleno = ArmarAMedida.capacidad(opciones);
      final armado = aMedida(lleno);
      final plano = PlanoDeLaFiesta.desde(
        armado: armado,
        config: ConfigPlano.vacia,
        alumnos: [alumno('a', 'GÓMEZ, SOFÍA', mesas: [1])],
      );
      final bytes = await sinLetras(plano);
      final texto = contenidoDelPdf(bytes);
      expect(paginasDelPdf(bytes), 1);
      expect(texto.contains('(GÓMEZ)'), isFalse, reason: '(GÓMEZ)');
      expect(texto.contains('apellidos'), isTrue, reason: 'apellidos');
      // El número sí va siempre.
      expect(texto.contains('($lleno)'), isTrue, reason: '($lleno)');
    });

    test('el alto de la letra entra entre una mesa y la de abajo', () {
      for (final estilo in EstiloPlano.values) {
        for (final escala in [0.2, 0.3, 0.4, 0.6, 1.0]) {
          final tam = PlanoPdf.tamApellido(
            armado: pagina3,
            hoja: 'A',
            estilo: estilo,
            escala: escala,
          );
          if (tam == 0) continue;
          expect(tam, greaterThanOrEqualTo(PlanoPdf.apellidoMinimoPt));
          expect(tam, lessThanOrEqualTo(PlanoPdf.apellidoMaximoPt));
          // Las filas de la página 3 están a 115 unidades.
          final hueco =
              (115 - 2 * PlanoPdf.ocupa(pagina3, estilo, escala)) * escala;
          expect(tam, lessThan(hueco), reason: '${estilo.name} a $escala');
        }
      }
    });

    test('a una escala muy chica no hay apellidos; a una grande, sí', () {
      expect(
        PlanoPdf.tamApellido(
          armado: pagina3,
          hoja: 'A',
          estilo: EstiloPlano.arquitecto,
          escala: 0.1,
        ),
        0,
      );
      expect(
        PlanoPdf.tamApellido(
          armado: pagina3,
          hoja: 'A',
          estilo: EstiloPlano.arquitecto,
          escala: 0.4,
        ),
        greaterThan(0),
      );
    });
  });
}
