import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/barra_local.dart';
import '../datos/barra_repositorio.dart';

/// La barra de la fiesta como la ve esta PC (la base y la cola de subida): las cajas,
/// las ventas y las anulaciones de todas las cajas que bajaron. La lee Recepción para
/// saber qué vales de silla anuló la barra (6.4.0). Los tests la reemplazan.
///
/// Aparte de `barra_providers.dart` a propósito: ese trae la impresora por Bluetooth, y
/// esto lo usa también la página del celular de la puerta.
final barraDelJefeProvider = Provider<BarraDelJefe>((ref) => BarraLocal());
