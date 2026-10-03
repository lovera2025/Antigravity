import 'armado_salon.dart';

/// Los armados del Canva del jefe ("Plano Mesas Predio"), en la misma escala
/// que la página 3, que es la única que trae los números puestos por él.
///
/// La numeración es una serpentina: los números consecutivos quedan pegados, y
/// así una familia con dos o tres mesas se sienta junta. Donde no se puede (la
/// otra hoja, o del otro lado de la pasarela) el armado tiene un corte y el
/// sorteo no parte ahí a nadie.
///
/// Una numeración publicada no se cambia: si hay que arreglarla, se agrega una
/// versión nueva de la clave (`@2`) y las fiestas que ya eligieron la vieja la
/// conservan, porque tienen su copia.
class ArmadosPredefinidos {
  ArmadosPredefinidos._();

  static const normal2aPagina3Clave = 'normal_2a_p3@1';
  static const normal2aPaginas45Clave = 'normal_2a_p45@1';
  static const normal2a2bClave = 'normal_2a_2b@1';
  static const tecnica1a1bClave = 'tecnica_1a_1b@1';

  static List<ArmadoSalon> get todos => [
        normal2aPagina3(),
        normal2aPaginas45(),
        normal2a2b(),
        tecnica1a1b(),
      ];

  static ArmadoSalon? porClave(String clave) {
    for (final a in todos) {
      if (a.clave == clave) return a;
    }
    return null;
  }

  /// Las mesas de [armado] que no están donde las trae el armado de fábrica:
  /// alguien las corrió o las agregó a mano en esa fiesta. Vacío si el armado
  /// no es uno de los del Canva.
  ///
  /// Sirve para saber a cuáles avisarles si quedan apretadas: las que siguen
  /// donde las puso el jefe no se discuten.
  static Set<int> corridas(ArmadoSalon armado) {
    final fabrica = porClave(armado.clave);
    if (fabrica == null) return const {};
    return {
      for (final m in armado.mesas)
        if (!_dondeEstaba(fabrica.mesa(m.numero), m)) m.numero,
    };
  }

  static bool _dondeEstaba(MesaPlano? fabrica, MesaPlano hoy) =>
      fabrica != null &&
      fabrica.hoja == hoy.hoja &&
      (fabrica.x - hoy.x).abs() < 0.01 &&
      (fabrica.y - hoy.y).abs() < 0.01;

  /// Normal 2A, página 3: 78 mesas, numeradas por el jefe.
  ///
  /// Bloque izquierdo de 5 × 6 por filas, alternando (la 1 junto al
  /// escenario); fila de abajo 31, 32, 41, 42 y 53; bloque derecho por
  /// columnas, alternando, con arriba el escenario y el ingreso.
  static ArmadoSalon normal2aPagina3() {
    const filas = [350.0, 470.0, 585.0, 700.0, 815.0, 930.0, 1045.0];
    const izq = [316.0, 428.0, 538.0, 650.0, 760.0];
    const medio = [873.0, 980.0];
    const der = [1085.0, 1188.0, 1278.0, 1379.0, 1478.0, 1577.0, 1673.0];

    final mesas = <MesaPlano>[];
    void poner(int n, double x, double y) =>
        mesas.add(MesaPlano(numero: n, hoja: 'A', x: x, y: y));

    for (var f = 0; f < 6; f++) {
      for (var i = 0; i < 5; i++) {
        poner(f * 5 + i + 1, izq[f.isEven ? 4 - i : i], filas[f]);
      }
    }
    poner(31, izq[4], filas[6]);
    poner(32, medio[0], filas[6]);
    for (var i = 0; i < 4; i++) {
      poner(33 + i, medio[0], filas[5 - i]);
      poner(37 + i, medio[1], filas[2 + i]);
    }
    poner(41, medio[1], filas[6]);
    poner(42, der[0], filas[6]);
    var n = 43;
    for (var c = 0; c < der.length; c++) {
      for (var i = 0; i < 5; i++) {
        poner(n++, der[c], filas[c.isOdd ? 1 + i : 5 - i]);
      }
      if (c == 1) poner(n++, der[1], filas[6]);
    }

    return ArmadoSalon(
      clave: normal2aPagina3Clave,
      nombre: 'Normal 2A · página 3',
      descripcion: '78 mesas, con la numeración del jefe',
      hojas: const [
        HojaPlano(
          id: 'A',
          titulo: 'Normal 2A',
          caja: RectPlano(80, 250, 1760, 1230),
        ),
      ],
      mesas: mesas,
      sectores: const [
        SectorPlano(
          tipo: TipoSector.escenario,
          texto: 'Escenario',
          hoja: 'A',
          caja: RectPlano(787, 268, 278, 47),
        ),
        SectorPlano(
          tipo: TipoSector.escenario,
          texto: '',
          hoja: 'A',
          caja: RectPlano(873, 315, 107, 122),
        ),
        SectorPlano(
          tipo: TipoSector.ingreso,
          texto: 'Ingreso egresados',
          hoja: 'A',
          caja: RectPlano(1190, 283, 450, 95),
        ),
        SectorPlano(
          tipo: TipoSector.brindis,
          texto: 'Sector brindis',
          hoja: 'A',
          caja: RectPlano(98, 430, 150, 535),
          vertical: true,
        ),
        SectorPlano(
          tipo: TipoSector.cajas,
          texto: 'Barra y cajas',
          hoja: 'A',
          caja: RectPlano(1748, 515, 67, 450),
          vertical: true,
        ),
        SectorPlano(
          tipo: TipoSector.barra,
          texto: 'Barra',
          hoja: 'A',
          caja: RectPlano(292, 1015, 353, 90),
        ),
        SectorPlano(
          tipo: TipoSector.banos,
          texto: 'Baños',
          hoja: 'A',
          caja: RectPlano(1288, 1015, 440, 95),
        ),
        SectorPlano(
          tipo: TipoSector.pista,
          texto: 'Pista de baile',
          hoja: 'A',
          caja: RectPlano(750, 1115, 475, 340),
        ),
      ],
      ingreso: const PuntoPlano('A', 1415, 330),
    );
  }

  // ── Normal 2A, páginas 4 y 5 (y 2B) ─────────────────────────────────────
  //
  // Escenario de lado a lado y pasarela al medio. A cada lado, 9 filas: de la
  // 1 a la 5 con 5 mesas, de la 6 a la 9 con 6 (la de más, del lado de
  // afuera). Dos mesas al medio en la fila 9, bajo el final de la pasarela,
  // separadas de los bloques. La geometría es aproximada (fotos del Canva);
  // los números son los que importan para el sorteo.

  static const _filasN = [
    390.0, 502.0, 614.0, 726.0, 838.0, 950.0, 1062.0, 1174.0, 1286.0,
  ];

  /// Columnas del bloque izquierdo, de adentro (junto a la pasarela) hacia
  /// afuera. La sexta solo existe en las filas 6 a 9.
  static const _izqN = [830.0, 725.0, 620.0, 515.0, 410.0, 305.0];
  static const _medioN = [1025.0, 1115.0];
  static const _derN = [1310.0, 1415.0, 1520.0, 1625.0, 1730.0, 1835.0];

  static List<MesaPlano> _mesasNormal2A() {
    final mesas = <MesaPlano>[];
    void poner(int n, double x, double y) =>
        mesas.add(MesaPlano(numero: n, hoja: 'A', x: x, y: y));

    // Izquierda, por filas desde el escenario (1-49): las impares de afuera
    // hacia adentro, las pares al revés. Así la 25 y la 49 quedan adentro,
    // como los bloques de colores del jefe (1-24 y 25-49).
    var n = 1;
    for (var f = 0; f < 9; f++) {
      final cols = f < 5 ? 5 : 6;
      final deAfueraAdentro = f.isEven;
      for (var i = 0; i < cols; i++) {
        final c = deAfueraAdentro ? cols - 1 - i : i;
        poner(n++, _izqN[c], _filasN[f]);
      }
    }
    // Las dos del medio (50 y 51), que el jefe dejó libres.
    poner(n++, _medioN[0], _filasN[8]);
    poner(n++, _medioN[1], _filasN[8]);
    // Derecha, por filas desde abajo (52-100): la fila 9 de adentro hacia
    // afuera, y así alternando hasta la fila 1.
    for (var f = 8; f >= 0; f--) {
      final cols = f < 5 ? 5 : 6;
      final deAdentroAfuera = (8 - f).isEven;
      for (var i = 0; i < cols; i++) {
        final c = deAdentroAfuera ? i : cols - 1 - i;
        poner(n++, _derN[c], _filasN[f]);
      }
    }
    return mesas;
  }

  static const _sectoresNormal2A = [
    SectorPlano(
      tipo: TipoSector.escenario,
      texto: 'Escenario',
      hoja: 'A',
      caja: RectPlano(300, 270, 1540, 50),
    ),
    SectorPlano(
      tipo: TipoSector.pasarela,
      texto: 'Pasarela',
      hoja: 'A',
      caja: RectPlano(1015, 320, 110, 740),
      vertical: true,
    ),
  ];

  /// Normal 2A, páginas 4 y 5: 100 mesas. Reproduce los bloques de colores
  /// del jefe (1-24, 25-49, 50-51 libres, 52-54, 55-80 y 81-100). La
  /// numeración es una propuesta, a confirmar con el jefe.
  static ArmadoSalon normal2aPaginas45() => ArmadoSalon(
        clave: normal2aPaginas45Clave,
        nombre: 'Normal 2A · páginas 4 y 5',
        descripcion: '100 mesas, con pasarela',
        hojas: const [
          HojaPlano(
            id: 'A',
            titulo: 'Normal 2A',
            caja: RectPlano(250, 250, 1640, 1100),
          ),
        ],
        mesas: _mesasNormal2A(),
        sectores: _sectoresNormal2A,
      );

  /// Normal 2A + 2B: las 100 de la hoja A y, abajo, la hoja B con filas de
  /// 6 + 2 + 6 (101 en adelante, en serpentina). **La hoja B es provisoria**:
  /// la foto de la página 6 salió cortada. Con la foto entera se hace `@2`.
  static ArmadoSalon normal2a2b({int filasHojaB = 3}) {
    final mesas = _mesasNormal2A();
    const filasB = [390.0, 502.0, 614.0, 726.0, 838.0, 950.0];
    // Columnas de la hoja B de izquierda a derecha, alineadas con la A.
    final colsB = [
      ..._izqN.reversed,
      ..._medioN,
      ..._derN,
    ];
    var n = 101;
    for (var f = 0; f < filasHojaB && f < filasB.length; f++) {
      for (var i = 0; i < colsB.length; i++) {
        final c = f.isEven ? i : colsB.length - 1 - i;
        mesas.add(MesaPlano(numero: n++, hoja: 'B', x: colsB[c], y: filasB[f]));
      }
    }
    final altoB = filasB[filasHojaB - 1] + 38 + 60 - 250;
    return ArmadoSalon(
      clave: normal2a2bClave,
      nombre: 'Normal 2A + 2B',
      descripcion: '${mesas.length} mesas en dos hojas (la B, provisoria)',
      hojas: [
        const HojaPlano(
          id: 'A',
          titulo: 'Normal 2A',
          caja: RectPlano(250, 250, 1640, 1100),
        ),
        HojaPlano(
          id: 'B',
          titulo: 'Normal 2B',
          caja: RectPlano(250, 250, 1640, altoB),
        ),
      ],
      mesas: mesas,
      sectores: _sectoresNormal2A,
    );
  }

  // ── Técnica 1A + 1B ─────────────────────────────────────────────────────
  //
  // 1A: bloque izquierdo de 5 × 8, bloque derecho de 5 × 8 y dos mesas al
  // medio en la fila 8, bajo la pasarela. 1B, abajo: 4 filas de 5 + 2 + 5.
  // Pasto a los costados: 3 por lado en la 1A (filas 6 a 8) y una columna de
  // 7 por lado en la 1B. Comunes 1-130, pasto 131-150 en U. La numeración es
  // una propuesta, a confirmar con el jefe.

  static const _filasT = [
    390.0, 498.0, 606.0, 714.0, 822.0, 930.0, 1038.0, 1146.0,
  ];

  /// Columnas del bloque izquierdo, de afuera (L1) hacia adentro (L5).
  static const _izqT = [330.0, 435.0, 540.0, 645.0, 750.0];
  static const _medioT = [940.0, 1030.0];

  /// Columnas del bloque derecho, de adentro (R1) hacia afuera (R5).
  static const _derT = [1220.0, 1325.0, 1430.0, 1535.0, 1640.0];
  static const _pastoIzqT = 225.0;
  static const _pastoDerT = 1745.0;

  /// Técnica 1A + 1B: 130 mesas comunes y 20 de pasto, del 131 en adelante.
  static ArmadoSalon tecnica1a1b() {
    final mesas = <MesaPlano>[];
    void poner(int n, String h, double x, double y, {bool pasto = false}) =>
        mesas.add(MesaPlano(numero: n, hoja: h, x: x, y: y, pasto: pasto));

    // 1A izquierda (1-40): la 1 adentro, junto al escenario y la pasarela;
    // las filas impares de adentro hacia afuera, las pares al revés.
    var n = 1;
    for (var f = 0; f < 8; f++) {
      for (var i = 0; i < 5; i++) {
        final c = f.isEven ? 4 - i : i;
        poner(n++, 'A', _izqT[c], _filasT[f]);
      }
    }
    // Al medio, fila 8 (41-42).
    poner(n++, 'A', _medioT[0], _filasT[7]);
    poner(n++, 'A', _medioT[1], _filasT[7]);
    // 1A derecha desde abajo (43-82): la fila 8 de adentro hacia afuera, y así
    // alternando hasta la fila 1, donde la 82 queda adentro.
    for (var f = 7; f >= 0; f--) {
      final deAdentroAfuera = (7 - f).isEven;
      for (var i = 0; i < 5; i++) {
        final c = deAdentroAfuera ? i : 4 - i;
        poner(n++, 'A', _derT[c], _filasT[f]);
      }
    }
    // 1B (83-130): 4 filas de 12, en el orden físico L1-L5, M1-M2, R1-R5,
    // alternando el sentido.
    final colsB = [..._izqT, ..._medioT, ..._derT];
    for (var f = 0; f < 4; f++) {
      for (var i = 0; i < colsB.length; i++) {
        final c = f.isEven ? i : colsB.length - 1 - i;
        poner(n++, 'B', colsB[c], _filasT[f]);
      }
    }
    // Pasto en U (131-150): baja por la izquierda (1A filas 6-8, después la
    // columna de 7 de la 1B) y sube por la derecha.
    for (var f = 5; f < 8; f++) {
      poner(n++, 'A', _pastoIzqT, _filasT[f], pasto: true);
    }
    for (var f = 0; f < 7; f++) {
      poner(n++, 'B', _pastoIzqT, _filasT[f], pasto: true);
    }
    for (var f = 6; f >= 0; f--) {
      poner(n++, 'B', _pastoDerT, _filasT[f], pasto: true);
    }
    for (var f = 7; f >= 5; f--) {
      poner(n++, 'A', _pastoDerT, _filasT[f], pasto: true);
    }

    return ArmadoSalon(
      clave: tecnica1a1bClave,
      nombre: 'Técnica 1A + 1B',
      descripcion: '130 mesas y 20 de pasto, en dos hojas',
      hojas: const [
        HojaPlano(
          id: 'A',
          titulo: 'Técnica 1A',
          caja: RectPlano(170, 250, 1630, 960),
        ),
        HojaPlano(
          id: 'B',
          titulo: 'Técnica 1B',
          caja: RectPlano(170, 250, 1630, 850),
        ),
      ],
      mesas: mesas,
      sectores: const [
        SectorPlano(
          tipo: TipoSector.escenario,
          texto: 'Escenario',
          hoja: 'A',
          caja: RectPlano(225, 270, 1520, 50),
        ),
        SectorPlano(
          tipo: TipoSector.pasarela,
          texto: 'Pasarela',
          hoja: 'A',
          caja: RectPlano(930, 320, 110, 740),
          vertical: true,
        ),
      ],
    );
  }
}
