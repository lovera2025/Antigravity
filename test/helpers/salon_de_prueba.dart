import 'package:arguello_events/features/plano/modelo/armado_salon.dart';

/// Un salón chico hecho a mano, para probar el paso de los egresados: el
/// escenario arriba, la pasarela al medio de arriba abajo y tres filas de
/// cuatro mesas, dos de cada lado. Numerado fila por fila, cruzando la
/// pasarela y volviendo:
///
///            ESCENARIO
///      1    2  |P|  3    4
///      8    7  |P|  6    5
///      9   10  |P| 11   12
///
/// Pegadas a la pasarela: 2, 3, 7, 6, 10 y 11.
ArmadoSalon salonDePrueba({
  bool conPasarela = true,
  bool conEscenario = true,
  List<MesaPlano> otras = const [],
  List<HojaPlano> otrasHojas = const [],
}) {
  MesaPlano m(int n, double x, double y) =>
      MesaPlano(numero: n, hoja: 'A', x: x, y: y);
  return ArmadoSalon(
    clave: 'prueba@1',
    nombre: 'De prueba',
    radio: 8,
    hojas: [
      const HojaPlano(id: 'A', titulo: 'A', caja: RectPlano(0, 0, 100, 120)),
      ...otrasHojas,
    ],
    mesas: [
      m(1, 10, 20), m(2, 30, 20), m(3, 70, 20), m(4, 90, 20),
      m(8, 10, 40), m(7, 30, 40), m(6, 70, 40), m(5, 90, 40),
      m(9, 10, 60), m(10, 30, 60), m(11, 70, 60), m(12, 90, 60),
      ...otras,
    ],
    sectores: [
      if (conEscenario)
        const SectorPlano(
          tipo: TipoSector.escenario,
          texto: 'Escenario',
          hoja: 'A',
          caja: RectPlano(35, 0, 30, 8),
        ),
      if (conPasarela)
        const SectorPlano(
          tipo: TipoSector.pasarela,
          texto: '',
          hoja: 'A',
          caja: RectPlano(46, 8, 8, 60),
        ),
    ],
  );
}
