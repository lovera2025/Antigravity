import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/filtro_mora_masivos.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// El filtro de mora de la grilla de masivos.
///
/// Existe para poder llamar a los que deben: si deja a alguien afuera, ese
/// alumno no se llama y no aparece en la planilla.
void main() {
  ContratoAlumno alumno(String id, {String? curso, bool baja = false}) =>
      ContratoAlumno(
        id: id,
        eventoId: 'evt',
        nombreAlumno: baja ? '[BAJA] $id' : id,
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 200000,
        cuotasPagadas: 4,
        totalCuotas: 9,
        cursoDivision: curso,
      );

  MoraCuotaDetalle cuota(int n, double interes) => MoraCuotaDetalle(
    numeroCuota: n,
    vencimiento: DateTime(2026, 5, 31),
    diasMora: 30,
    interesBruto: interes,
    mesLabel: 'May 2026',
  );

  MoraDeAlumno mora({double vencida = 0, double tracked = 0}) => (
    total: vencida + tracked,
    desglose: vencida > 0 ? [cuota(5, vencida)] : <MoraCuotaDetalle>[],
    tracked: tracked,
  );

  group('cumpleFiltroMora', () {
    final soloVencida = alumno('VENCIDA');
    final soloFicha = alumno('FICHA');
    final ambas = alumno('AMBAS');
    final alDia = alumno('AL_DIA');
    final suspendido = alumno('SUSPENDIDO', baja: true);

    final mapa = <String, MoraDeAlumno>{
      'VENCIDA': mora(vencida: 30400),
      'FICHA': mora(tracked: 19400),
      'AMBAS': mora(vencida: 27800, tracked: 19400),
      'AL_DIA': mora(),
      'SUSPENDIDO': mora(vencida: 12000, tracked: 5000),
    };

    test('todos no filtra nada, ni siquiera las bajas', () {
      for (final a in [soloVencida, soloFicha, ambas, alDia, suspendido]) {
        expect(cumpleFiltroMora(a, mapa, FiltroMora.todos), isTrue);
      }
    });

    test('con mora deja los tres que deben y saca al que está al día', () {
      expect(cumpleFiltroMora(soloVencida, mapa, FiltroMora.conMora), isTrue);
      expect(cumpleFiltroMora(soloFicha, mapa, FiltroMora.conMora), isTrue);
      expect(cumpleFiltroMora(ambas, mapa, FiltroMora.conMora), isTrue);
      expect(cumpleFiltroMora(alDia, mapa, FiltroMora.conMora), isFalse);
    });

    test('solo vencida ignora al que únicamente tiene remanente', () {
      expect(
        cumpleFiltroMora(soloVencida, mapa, FiltroMora.soloVencida),
        isTrue,
      );
      expect(cumpleFiltroMora(ambas, mapa, FiltroMora.soloVencida), isTrue);
      expect(cumpleFiltroMora(soloFicha, mapa, FiltroMora.soloVencida), isFalse);
    });

    test('solo no cobrada ignora al que únicamente tiene calendario', () {
      expect(
        cumpleFiltroMora(soloFicha, mapa, FiltroMora.soloNoCobrada),
        isTrue,
      );
      expect(cumpleFiltroMora(ambas, mapa, FiltroMora.soloNoCobrada), isTrue);
      expect(
        cumpleFiltroMora(soloVencida, mapa, FiltroMora.soloNoCobrada),
        isFalse,
      );
    });

    test('las bajas quedan afuera de todo filtro de mora', () {
      // Están suspendidos y su mora está congelada: no se los llama.
      for (final f in [
        FiltroMora.conMora,
        FiltroMora.soloVencida,
        FiltroMora.soloNoCobrada,
      ]) {
        expect(cumpleFiltroMora(suspendido, mapa, f), isFalse, reason: '$f');
      }
    });

    test('un alumno sin mora calculada no entra (y no explota)', () {
      final huerfano = alumno('SIN_DATO');
      expect(cumpleFiltroMora(huerfano, mapa, FiltroMora.conMora), isFalse);
    });

    test('se combina con el filtro de curso en vez de pisarlo', () {
      final segundoA = alumno('DOS_A', curso: '2');
      final segundoB = alumno('DOS_B', curso: '2');
      final tercero = alumno('TRES', curso: '3');
      final m = <String, MoraDeAlumno>{
        'DOS_A': mora(vencida: 10000),
        'DOS_B': mora(),
        'TRES': mora(vencida: 8000),
      };

      final resultado = [segundoA, segundoB, tercero]
          .where((a) => (a.cursoDivision ?? '') == '2')
          .where((a) => cumpleFiltroMora(a, m, FiltroMora.conMora))
          .map((a) => a.id)
          .toList();

      expect(resultado, ['DOS_A']);
    });
  });

  // El chip de mora, la grilla y la planilla tienen que hablar del mismo
  // conjunto. Mientras el chip ignoró el curso, la búsqueda y hasta el filtro de
  // mora que él mismo rotulaba, decía "59 · $3.530.504" con 18 filas abajo y un
  // PDF de $297.788 saliendo de su propio botón.
  group('cumpleCursoYBusqueda', () {
    final dosA = alumno('PEREZ', curso: '2');
    final dosB = alumno('GOMEZ', curso: '2');
    final tres = alumno('LOPEZ', curso: '3');
    final todos = [dosA, dosB, tres];

    test('sin curso ni búsqueda no recorta nada', () {
      expect(todos.where(cumpleCursoYBusqueda).length, 3);
    });

    test('el curso recorta y respeta espacios de sobra', () {
      final conEspacios = alumno('RUIZ', curso: '  2  ');
      expect(
        [...todos, conEspacios]
            .where((a) => cumpleCursoYBusqueda(a, cursoDivision: '2'))
            .map((a) => a.id),
        ['PEREZ', 'GOMEZ', 'RUIZ'],
      );
    });

    test('la búsqueda mira nombre y curso', () {
      expect(
        todos.where((a) => cumpleCursoYBusqueda(a, busqueda: 'lop')).map((a) => a.id),
        ['LOPEZ'],
      );
      expect(
        todos.where((a) => cumpleCursoYBusqueda(a, busqueda: '3')).map((a) => a.id),
        ['LOPEZ'],
      );
    });

    test('curso y búsqueda se combinan, no se pisan', () {
      expect(
        todos
            .where((a) => cumpleCursoYBusqueda(a, cursoDivision: '2', busqueda: 'gom'))
            .map((a) => a.id),
        ['GOMEZ'],
      );
    });

    test('una búsqueda de solo espacios no filtra', () {
      expect(todos.where((a) => cumpleCursoYBusqueda(a, busqueda: '   ')).length, 3);
    });
  });

  group('el chip y la planilla cuentan lo mismo', () {
    final conMoraDos = alumno('CON_MORA_2', curso: '2');
    final sinMoraDos = alumno('SIN_MORA_2', curso: '2');
    final conMoraTres = alumno('CON_MORA_3', curso: '3');
    final fichaDos = alumno('FICHA_2', curso: '2');
    final padron = [conMoraDos, sinMoraDos, conMoraTres, fichaDos];

    final m = <String, MoraDeAlumno>{
      'CON_MORA_2': mora(vencida: 30400),
      'SIN_MORA_2': mora(),
      'CON_MORA_3': mora(vencida: 8000),
      'FICHA_2': mora(tracked: 19400),
    };

    /// El conjunto que alimentan el chip y la planilla: los dos recortes juntos.
    List<String> alcance({String? curso, String busqueda = '', required FiltroMora filtro}) =>
        padron
            .where((a) => cumpleCursoYBusqueda(a, cursoDivision: curso, busqueda: busqueda))
            .where((a) => cumpleFiltroMora(a, m, filtro))
            .map((a) => a.id)
            .toList();

    test('el curso recorta el conjunto de mora', () {
      expect(alcance(filtro: FiltroMora.conMora),
          ['CON_MORA_2', 'CON_MORA_3', 'FICHA_2']);
      expect(alcance(curso: '2', filtro: FiltroMora.conMora),
          ['CON_MORA_2', 'FICHA_2']);
    });

    test('el filtro por tipo recorta dentro del curso', () {
      expect(alcance(curso: '2', filtro: FiltroMora.soloNoCobrada), ['FICHA_2']);
      expect(alcance(curso: '2', filtro: FiltroMora.soloVencida), ['CON_MORA_2']);
    });

    test('la búsqueda también', () {
      expect(alcance(busqueda: 'con_mora', filtro: FiltroMora.conMora),
          ['CON_MORA_2', 'CON_MORA_3']);
    });
  });

  group('moraVencidaDe', () {
    test('suma el desglose y no cuenta el remanente', () {
      final m = (
        total: 30000.0,
        desglose: [cuota(5, 12000), cuota(6, 8000)],
        tracked: 10000.0,
      );
      expect(moraVencidaDe(m), closeTo(20000, 0.01));
    });
  });
}
