// El cierre de caja de verdad (`CierreCajaScreen`) con datos inventados, sin la base ni
// la nube: los cobros del día los da un estado fijo, y la barra es una noche en memoria
// (`noche_de_barra.dart`). Lo usan `test/cierre_por_sector_test.dart` y la ventana de
// prueba `tool/cierre_sector_prueba.dart`.
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/cierre_caja/models/turno_caja.dart';
import 'package:arguello_events/features/cierre_caja/providers/cierre_caja_provider.dart';
import 'package:arguello_events/features/common/providers/admin_provider.dart';

import 'noche_de_barra.dart';

/// El modo jefe, prendido o apagado desde la prueba.
class ModoJefeDelCierre extends AdminAuthNotifier {
  final bool prendido;

  ModoJefeDelCierre(this.prendido);

  @override
  AdminAuthState build() => AdminAuthState(isAdmin: prendido, modoJefe: prendido);

  void poner(bool si) => state = AdminAuthState(isAdmin: si, modoJefe: si);
}

/// Los cobros del día, fijos: el efectivo y la transferencia del día completo. No lee la
/// base ni sube nada; refrescar no hace nada.
class CierreDePrueba extends CierreCajaNotifier {
  @override
  CierreCajaState build() => CierreCajaState(
        dia: DateTime.utc(2026, 12, 5),
        turno: TurnoCaja.dia,
        corteHorarioAr: 14,
        consolidado: true,
        efectivoBruto: 482300,
        transferenciaBruta: 315000,
        efectivoNeto: 482300,
        transferenciaNeta: 315000,
        totalNeto: 797300,
      );

  @override
  Future<void> refrescarManual() async {}

  @override
  Future<void> refrescarEnSilencio() async {}

  @override
  Future<void> aplicarRestriccionOperativa() async {}
}

/// Todo lo que el cierre necesita, con la barra de [noche] y el reloj fijo la mañana
/// siguiente a TÉCNICA PINAROLI.
List<Override> reemplazosDelCierre(NocheDeBarra noche, {bool modoJefe = true}) => [
      ...noche.operadores.reemplazos,
      ...noche.prueba.reemplazos,
      adminAuthProvider.overrideWith(() => ModoJefeDelCierre(modoJefe)),
      cierreCajaProvider.overrideWith(CierreDePrueba.new),
      // Las fiestas ya las da la barra en memoria (`reemplazos`).
      barraDelJefeProvider.overrideWithValue(noche.prueba.barra),
      relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 12, 5, 9)),
    ];
