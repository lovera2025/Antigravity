import '../../../models/contrato_alumno.dart';
import '../../../models/mesa_extra_item.dart';
import '../repositories/contratos_repository.dart';
import 'mesas_extra_utils.dart';
import 'salon_mesas.dart';

/// Lo que se guarda al editar un alumno.
///
/// El número de mesa viaja **solo si alguien lo cambió a mano**. Si se mandara
/// siempre, una PC que todavía no bajó el sorteo pisaría los números con lo que
/// tenía (vacío o viejo) al editar cualquier otra cosa del alumno. Vaciarlo a
/// propósito lo libera (`null`).
///
/// **Los acompañantes y la música, igual** (6.0.0). Se cargan de a cientos
/// desde el Excel del delegado (`planilla_delegado.dart`): una PC que todavía
/// no bajó esa carga los mandaría vacíos al editar un teléfono, y los borraría
/// en la nube y en las demás. Vaciar la música a propósito la borra (`null`).
///
/// **La mora, igual** (6.1.0): una PC que todavía no bajó un perdón o un arreglo
/// de la nube volvía a subir su mora vieja al editar cualquier cosa. Así, el
/// 16-oct, editar a una alumna desde la PC del jefe habría devuelto a la
/// nube los $166.200 cargados a mano que ya se habían puesto en 0.
Map<String, dynamic> datosEdicionAlumno({
  required ContratoAlumno antes,
  required ContratoAlumno editado,
  required String numeroMesaEscrito,
}) {
  final datos = editado.toJson()
    ..remove('numero_mesa')
    ..remove('nombres_acompanantes')
    ..remove('cantidad_acompanantes')
    ..remove('musica_elegida');
  final moraAntes = antes.toJson();
  for (final campo in camposMoraDelAlumno) {
    final ahora = datos.remove(campo);
    if (ahora != moraAntes[campo]) datos[campo] = ahora;
  }
  final mesaAntes = antes.numeroMesa?.trim() ?? '';
  final mesaAhora = numeroMesaEscrito.trim();
  if (mesaAhora != mesaAntes) {
    datos['numero_mesa'] = mesaAhora.isEmpty ? null : mesaAhora;
  }
  if (!_mismosAcompanantes(antes, editado)) {
    datos['nombres_acompanantes'] = editado.nombresAcompanantes;
    datos['cantidad_acompanantes'] = editado.nombresAcompanantes.length;
  }
  final musicaAntes = antes.musicaElegida?.trim() ?? '';
  final musicaAhora = editado.musicaElegida?.trim() ?? '';
  if (musicaAhora != musicaAntes) {
    datos['musica_elegida'] = musicaAhora.isEmpty ? null : musicaAhora;
  }
  return datos;
}

/// Las columnas de la mora del alumno: Editar alumno las manda solo si
/// cambiaron (ver [datosEdicionAlumno]).
const camposMoraDelAlumno = [
  'mora_pendiente_tracked',
  'mora_cobrada_offset',
  'mora_fecha_referencia',
  'mora_exenta_hasta',
  'mora_exencion_reinicia',
  'mora_tracked_ajuste',
];

/// Si los dos tienen los mismos acompañantes con nombre, en el mismo orden.
bool _mismosAcompanantes(ContratoAlumno antes, ContratoAlumno editado) {
  List<String> limpios(List<String> nombres) => [
        for (final n in nombres)
          if (n.trim().isNotEmpty) n.trim(),
      ];
  final a = limpios(antes.nombresAcompanantes);
  final b = limpios(editado.nombresAcompanantes);
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Si lo que se editó de un alumno cambia lo que dice la lista de la puerta:
/// su nombre, su mesa o sus acompañantes. Lo demás (el teléfono, una silla, el
/// plan de cuotas) no llega a Recepción ni al tótem.
bool edicionCambiaLaPuerta({
  required ContratoAlumno antes,
  required ContratoAlumno editado,
  required String numeroMesaEscrito,
}) {
  return antes.nombreAlumno.trim() != editado.nombreAlumno.trim() ||
      (antes.numeroMesa?.trim() ?? '') != numeroMesaEscrito.trim() ||
      !_mismosAcompanantes(antes, editado);
}

/// El guardado de Editar alumno, en un solo lugar: la ficha (de lo que se
/// carga de a muchos, solo lo que cambió: [datosEdicionAlumno]), la cuenta
/// rehecha desde los pagos y las mesas adicionales al día.
///
/// Lo usan la ventana de Editar alumno y ANULAR de una mesa adicional "a
/// confirmar" (6.9.2), que baja la adicional **por este mismo camino**: no
/// hay otro que edite la cuenta de un alumno.
Future<void> guardarEdicionDeAlumno(
  ContratosRepository repo, {
  required ContratoAlumno antes,
  required ContratoAlumno editado,
  required String numeroMesaEscrito,
}) async {
  await repo.actualizarContrato(
    antes.id,
    datosEdicionAlumno(
      antes: antes,
      editado: editado,
      numeroMesaEscrito: numeroMesaEscrito,
    ),
  );
  await repo.recalcularProgresoContrato(antes.id);
  await repo.reconciliarMesasEstadoContrato(antes.id);
}

/// Una mesa adicional menos en el contrato de un alumno (6.9.2): la cuenta que
/// hace Editar alumno cuando se le baja la cantidad de mesas, sin la ventana.
///
/// Es para ANULAR una adicional "a confirmar" desde el PLANO. Cuenta pura: la
/// ficha como quedaría ([editado]), o por qué no se puede ([problema]). Se
/// baja **la última** adicional: lo pagado de las mesas se reparte de la
/// primera a la última, así que la última es la que no tiene nada.
///
/// Lo demás de la ficha no cambia: ni el nombre, ni la mesa (su número lo
/// suelta el plano), ni las sillas, ni la mora.
class BajaDeAdicional {
  final ContratoAlumno? editado;
  final String? problema;

  const BajaDeAdicional.ok(ContratoAlumno this.editado) : problema = null;
  const BajaDeAdicional.noSePuede(String this.problema) : editado = null;

  bool get sePuede => problema == null;

  static BajaDeAdicional de(ContratoAlumno al) {
    // Las mismas dos cuentas con que abre la ventana de Editar alumno.
    final cantidad = al.mesaExtraPrecio > 0
        ? (al.mesaExtraCantidad > 0 ? al.mesaExtraCantidad : 1)
        : 0;
    if (cantidad < 1) {
      return const BajaDeAdicional.noSePuede(
        'Ya no tiene una mesa adicional en su contrato.',
      );
    }
    final unitario = al.precioUnitarioMesaExtra;
    final nueva = cantidad - 1;
    final estado = MesasExtraUtils.estadoDesdeContrato(al);
    if (!MesasExtraUtils.puedeReducirCantidad(estado, nueva)) {
      return const BajaDeAdicional.noSePuede(
        'Esa mesa adicional tiene pagos anotados: no se anula desde acá. '
        'Mirala en Editar alumno.',
      );
    }
    final entran = SalonMesas.maxSillasExtraPara(1 + nueva);
    if (al.sillasExtraCantidad > entran) {
      return BajaDeAdicional.noSePuede(
        'Tiene ${al.sillasExtraCantidad} sillas extra, y con una mesa menos '
        'entran hasta $entran: primero bajale las sillas en Editar alumno.',
      );
    }
    final cuotas = al.mesaExtraCuotas < 1 ? 1 : al.mesaExtraCuotas;
    final montoMesas = double.parse((unitario * nueva).toStringAsFixed(2));
    final total = double.parse(
      (al.montoTotalPactado - al.mesaExtraPrecio + montoMesas)
          .toStringAsFixed(2),
    );
    final saldo = double.parse(
      (al.saldoDeudor + (total - al.montoTotalPactado)).toStringAsFixed(2),
    );
    if (saldo < -0.01) {
      return const BajaDeAdicional.noSePuede(
        'Lo que ya pagó supera el total sin esa mesa: no se anula desde acá. '
        'Mirala en Editar alumno.',
      );
    }
    final mesas = nueva > 0 && unitario > 0
        ? MesasExtraUtils.construirParaGuardar(
            cantidadNueva: nueva,
            precioUnitario: unitario,
            cuotasPlan: cuotas,
            estadoAnterior: estado,
            pagadoTotalFallback: al.mesaExtraPagado,
          )
        : const <MesaExtraItem>[];
    return BajaDeAdicional.ok(
      al.copyWith(
        montoTotalPactado: total,
        saldoDeudor: saldo < 0 ? 0 : saldo,
        mesaExtraPrecio: montoMesas,
        mesaExtraCuotas: cuotas,
        mesaExtraCantidad: nueva,
        mesasExtraEstadoRaw: mesas.map((e) => e.toJson()).toList(),
      ),
    );
  }
}
