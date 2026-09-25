import 'dart:math';

import '../../../core/utils/uuid_utils.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart';
import 'cobro_abono_acumulado.dart';
import 'mesas_extra_utils.dart';
import 'mora_cuota_calculator.dart';
import 'salon_mesas.dart';

/// Las entradas que le corresponden a un egresado, según su cuenta.
class EntradasDeAlumno {
  /// Lugares: 8 por mesa más las sillas extra que figuran en la cuenta.
  final int lugares;

  /// Egresado y acompañantes: tienen cena. Se entregan sin número.
  final int vip;

  const EntradasDeAlumno({required this.lugares, required this.vip});

  /// El resto de los lugares, con número del talonario.
  int get generales => max(0, lugares - vip);

  bool get entran => vip <= lugares;
}

/// Lo que debe un egresado, con la misma cuenta que la pantalla de cobro.
class DeudaAlumno {
  /// El saldo de la ficha (`saldo_deudor`), el que muestra la grilla.
  final double saldoFicha;

  /// El saldo que dan los pagos (`recalcularSaldoDesdePagos`).
  final double saldoPagos;

  /// La mora pendiente, igual que en el cobro.
  final double mora;

  const DeudaAlumno({
    required this.saldoFicha,
    required this.saldoPagos,
    required this.mora,
  });

  /// La misma regla que usan la grilla ("liquidado") y el cobro ("no tiene
  /// saldo pendiente"): saldo y mora en cero, con margen de un centavo.
  bool get pagoTodo =>
      saldoFicha <= RetiroEntradas.margen &&
      saldoPagos <= RetiroEntradas.margen &&
      mora <= RetiroEntradas.margen;

  /// La ficha y los pagos no dicen lo mismo. Pasó con ARGUELLO, TOMAS: la
  /// ficha decía la base pagada y no había ningún pago. Antes de entregar hay
  /// que revisar la cuenta.
  bool get noCoincide =>
      (saldoFicha - saldoPagos).abs() > RetiroEntradas.diferenciaMaxima;

  /// Lo que se le dice que debe: el mayor de los dos saldos, más la mora.
  double get total => max(saldoFicha, saldoPagos) + mora;
}

/// Por qué no se le pueden entregar las entradas todavía.
enum BloqueoRetiro {
  ninguno,

  /// Debe algo: cuotas, mesas o sillas extra, o mora.
  debe,

  /// La ficha y los pagos no coinciden.
  cuentaNoCoincide,

  /// No tiene mesa asignada, o el número no se entiende.
  sinMesa,

  /// Sus números de mesa no coinciden con su cuenta (le falta o le sobra una).
  mesasNoCoinciden,

  /// Tiene más personas con cena que lugares.
  noEntran,
}

/// Un renglón de la planilla de entrega en papel. Lo que la app ya sabe va
/// impreso; el nombre de quien retira queda siempre en blanco, porque lo
/// escribe esa persona (no se firma).
class FilaPlanillaEntrega {
  final String alumnoId;
  final String egresado;
  final String mesa;
  final int vip;
  final int generales;

  /// Los números del talonario si ya se entregó; vacío si no.
  final String delAl;

  /// Menores de 10 si ya se entregó; vacío si no.
  final String menores;

  /// El parentesco si ya se entregó; vacío si no.
  final String parentesco;

  /// Por qué no se puede entregar ("Debe: no entregar"), o `null`.
  final String? noEntregar;

  final bool entregado;

  const FilaPlanillaEntrega({
    required this.alumnoId,
    required this.egresado,
    required this.mesa,
    required this.vip,
    required this.generales,
    required this.delAl,
    required this.menores,
    required this.parentesco,
    required this.noEntregar,
    required this.entregado,
  });
}

/// La cuenta de un evento en la pantalla de retiro.
class ResumenRetiro {
  final int alumnos;
  final int retiraron;

  /// Sin retirar y con deuda: no se les puede entregar.
  final int conDeuda;
  final int entradasEntregadas;
  final int entradasTotales;

  const ResumenRetiro({
    required this.alumnos,
    required this.retiraron,
    required this.conDeuda,
    required this.entradasEntregadas,
    required this.entradasTotales,
  });

  int get faltan => alumnos - retiraron;
}

/// Las reglas del retiro de entradas. Todo es puro: la pantalla, la planilla y
/// los tests usan esto mismo, así dicen siempre lo mismo.
class RetiroEntradas {
  RetiroEntradas._();

  /// Margen para decir "en cero": un centavo, como la grilla y el cobro.
  static const double margen = 0.01;

  /// Desde cuánta diferencia entre la ficha y los pagos se pide revisar.
  /// Algunos montos del contrato se guardan con redondeo (float4 en la nube),
  /// así que se deja pasar hasta un peso.
  static const double diferenciaMaxima = 1.0;

  static EntradasDeAlumno entradasDe(ContratoAlumno a) {
    final o = SalonMesas.ocupacion(a);
    return EntradasDeAlumno(lugares: o.asientos, vip: o.personas);
  }

  static DeudaAlumno deudaDe(
    ContratoAlumno a, {
    required Iterable<Map<String, dynamic>> pagos,
    required double moraCobradaHistorial,
    DateTime? ahoraAr,
  }) {
    final recalculo = recalcularSaldoDesdePagos(
      montoTotalPactado: a.montoTotalPactado,
      totalCuotas: a.totalCuotas,
      mesaExtraPrecio: a.mesaExtraPrecio,
      sillasExtraPrecioTotal: a.sillasExtraPrecioTotal,
      precioUnitarioMesaExtra: a.precioUnitarioMesaExtra,
      mesaExtraCuotas: a.mesaExtraCuotas,
      mesaExtraCantidad: a.mesaExtraCantidad,
      sillasExtraCuotas: a.sillasExtraCuotas,
      pagos: pagos,
    );
    final mora = MoraCuotaCalculator.moraPendienteOperativa(
      contrato: a,
      moraCobradaHistorial: moraCobradaHistorial,
      ahoraAr: ahoraAr,
    );
    return DeudaAlumno(
      saldoFicha: max(0.0, a.saldoDeudor),
      saldoPagos: recalculo.saldoDeudor,
      mora: mora,
    );
  }

  /// Por qué no se le puede entregar, o [BloqueoRetiro.ninguno]. Primero la
  /// plata, después las mesas.
  static BloqueoRetiro bloqueo(ContratoAlumno a, DeudaAlumno deuda) {
    if (deuda.noCoincide) return BloqueoRetiro.cuentaNoCoincide;
    if (!deuda.pagoTodo) return BloqueoRetiro.debe;
    if (MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isEmpty) {
      return BloqueoRetiro.sinMesa;
    }
    if (SalonMesas.avisoMesas(a) != null) return BloqueoRetiro.mesasNoCoinciden;
    if (!entradasDe(a).entran) return BloqueoRetiro.noEntran;
    return BloqueoRetiro.ninguno;
  }

  /// Qué está mal en los números del talonario, o `null` si están bien.
  ///
  /// [deOtros] son los números ya entregados a las otras familias del evento
  /// (nombre → tramos): ninguno se puede repetir.
  static String? errorTramos({
    required List<TramoTalonario> tramos,
    required int generales,
    Map<String, List<TramoTalonario>> deOtros = const {},
  }) {
    if (generales == 0) {
      return tramos.isEmpty ? null : 'No lleva entradas generales: sacá los números.';
    }
    if (tramos.isEmpty) {
      return 'Escribí el primer número de las entradas que le das.';
    }
    for (final t in tramos) {
      if (t.desde < 1) return 'Los números del talonario empiezan en 1.';
      if (t.hasta < t.desde) return 'El tramo ${t.desde} al ${t.hasta} está al revés.';
    }
    final total = tramos.fold<int>(0, (s, t) => s + t.cantidad);
    if (total != generales) {
      return 'Son $total números y tiene que llevar $generales '
          '${generales == 1 ? 'general' : 'generales'}.';
    }
    for (var i = 0; i < tramos.length; i++) {
      for (var j = i + 1; j < tramos.length; j++) {
        if (tramos[i].seCruzaCon(tramos[j])) {
          return 'Los tramos ${tramos[i].texto} y ${tramos[j].texto} se pisan.';
        }
      }
    }
    for (final e in deOtros.entries) {
      for (final otro in e.value) {
        for (final t in tramos) {
          if (t.seCruzaCon(otro)) {
            final numero = max(t.desde, otro.desde);
            return 'El $numero ya se le dio a ${e.key} (${otro.texto}).';
          }
        }
      }
    }
    return null;
  }

  /// Lo que falta para registrar quién retira, por campo. Vacío si está todo.
  static Map<String, String> erroresQuienRetira({
    required ParentescoRetiro? parentesco,
    required String nombre,
    String motivo = '',
    bool autorizacionFirmada = false,
    required bool escribioEnPlanilla,
  }) {
    final errores = <String, String>{};
    if (parentesco == null) errores['parentesco'] = 'Elegí quién retira.';
    final palabras =
        nombre.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
    if (palabras < 2) errores['nombre'] = 'Escribí nombre y apellido.';
    if (parentesco == ParentescoRetiro.otraPersona) {
      if (motivo.trim().isEmpty) {
        errores['motivo'] = 'Escribí por qué no viene un familiar directo.';
      }
      if (!autorizacionFirmada) {
        errores['autorizacion'] =
            'Sin autorización firmada no se entrega a otra persona.';
      }
    }
    if (!escribioEnPlanilla) {
      errores['planilla'] =
          'Falta que escriba su nombre y apellido en la planilla.';
    }
    return errores;
  }

  /// Si la cuenta cambió después de entregar: cuántas le faltan (positivo) o
  /// cuántas se llevó de más (negativo), VIP y generales por separado.
  static ({int vip, int generales}) diferencia(
    EntradasRetiro entregado,
    EntradasDeAlumno hoy,
  ) =>
      (vip: hoy.vip - entregado.vip, generales: hoy.generales - entregado.generales);

  static bool cambioLaCuenta(EntradasRetiro entregado, EntradasDeAlumno hoy) {
    final d = diferencia(entregado, hoy);
    return d.vip != 0 || d.generales != 0;
  }

  /// Los números ya entregados a otras familias del evento, por nombre, para
  /// que no se repitan. Solo cuentan las entregas vigentes.
  static Map<String, List<TramoTalonario>> tramosDeOtros(
    Iterable<ContratoAlumno> alumnos,
    Map<String, EntradasRetiro> retiros, {
    required String salvo,
  }) =>
      {
        for (final a in alumnos)
          if (a.id != salvo &&
              (retiros[a.id]?.entregado ?? false) &&
              retiros[a.id]!.tramos.isNotEmpty)
            a.nombreAlumno.trim(): retiros[a.id]!.tramos,
      };

  /// La entrega a guardar. Si antes hubo una anulada, conserva quién anuló y
  /// por qué: la fila es una sola por alumno.
  static EntradasRetiro nuevaEntrega({
    required ContratoAlumno alumno,
    required EntradasDeAlumno entradas,
    required List<TramoTalonario> tramos,
    required int menores10,
    required ParentescoRetiro parentesco,
    required String nombre,
    String motivo = '',
    bool autorizacionFirmada = false,
    required String quien,
    required DateTime ahora,
    EntradasRetiro? anterior,
  }) {
    final otra = parentesco == ParentescoRetiro.otraPersona;
    return EntradasRetiro(
      id: UuidUtils.entradasRetiroId(alumno.id),
      contratoAlumnoId: alumno.id,
      estado: EstadoRetiro.entregado,
      vip: entradas.vip,
      generales: entradas.generales,
      tramos: tramos,
      menores10: max(0, menores10),
      parentesco: parentesco,
      retiroNombre: nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase(),
      otraPersonaMotivo: otra ? motivo.trim() : null,
      autorizacionFirmada: otra && autorizacionFirmada,
      escribioEnPlanilla: true,
      entregadoPor: quien,
      entregadoAt: ahora,
      anuladoPor: anterior?.anuladoPor,
      anuladoAt: anterior?.anuladoAt,
      anuladoMotivo: anterior?.anuladoMotivo,
      createdAt: anterior?.createdAt ?? ahora,
      updatedAt: ahora,
    );
  }

  /// La misma fila, anulada: queda quién, cuándo y por qué. No se borra nada.
  static EntradasRetiro anular(
    EntradasRetiro r, {
    required String motivo,
    required String quien,
    required DateTime ahora,
  }) =>
      EntradasRetiro(
        id: r.id,
        contratoAlumnoId: r.contratoAlumnoId,
        estado: EstadoRetiro.anulado,
        vip: r.vip,
        generales: r.generales,
        tramos: r.tramos,
        menores10: r.menores10,
        parentesco: r.parentesco,
        retiroNombre: r.retiroNombre,
        otraPersonaMotivo: r.otraPersonaMotivo,
        autorizacionFirmada: r.autorizacionFirmada,
        escribioEnPlanilla: r.escribioEnPlanilla,
        entregadoPor: r.entregadoPor,
        entregadoAt: r.entregadoAt,
        anuladoPor: quien,
        anuladoAt: ahora,
        anuladoMotivo: motivo.trim(),
        createdAt: r.createdAt,
        updatedAt: ahora,
      );

  /// Lo que dice el bloqueo en la planilla y en la pantalla, en pocas palabras.
  static String? textoBloqueo(BloqueoRetiro b) => switch (b) {
        BloqueoRetiro.ninguno => null,
        BloqueoRetiro.debe => 'Debe: no entregar',
        BloqueoRetiro.cuentaNoCoincide => 'Revisar la cuenta: no entregar',
        BloqueoRetiro.sinMesa => 'Sin mesa: no entregar',
        BloqueoRetiro.mesasNoCoinciden => 'Revisar sus mesas: no entregar',
        BloqueoRetiro.noEntran => 'No entran: no entregar',
      };

  /// Los renglones de la planilla de entrega, uno por egresado activo.
  static FilaPlanillaEntrega filaPlanilla(
    ContratoAlumno a, {
    EntradasRetiro? retiro,
    required DeudaAlumno deuda,
  }) {
    final e = entradasDe(a);
    final entregado = retiro?.entregado ?? false;
    return FilaPlanillaEntrega(
      alumnoId: a.id,
      egresado: a.nombreAlumno.trim(),
      mesa: SalonMesas.textoMesasPuerta(a) ?? '-',
      vip: entregado ? retiro!.vip : e.vip,
      generales: entregado ? retiro!.generales : e.generales,
      delAl: entregado ? TramoTalonario.legible(retiro!.tramos) : '',
      menores: entregado ? '${retiro!.menores10}' : '',
      parentesco: entregado ? retiro!.parentesco?.etiqueta ?? '' : '',
      noEntregar: entregado ? null : textoBloqueo(bloqueo(a, deuda)),
      entregado: entregado,
    );
  }

  static ResumenRetiro resumen(
    Iterable<ContratoAlumno> alumnos,
    Map<String, EntradasRetiro> retiros,
    Map<String, DeudaAlumno> deudas,
  ) {
    var total = 0, retiraron = 0, conDeuda = 0, entregadas = 0, totales = 0;
    for (final a in alumnos) {
      total++;
      totales += entradasDe(a).lugares;
      final r = retiros[a.id];
      if (r != null && r.entregado) {
        retiraron++;
        entregadas += r.entradas;
      } else if (!(deudas[a.id]?.pagoTodo ?? true) ||
          (deudas[a.id]?.noCoincide ?? false)) {
        conDeuda++;
      }
    }
    return ResumenRetiro(
      alumnos: total,
      retiraron: retiraron,
      conDeuda: conDeuda,
      entradasEntregadas: entregadas,
      entradasTotales: totales,
    );
  }
}
