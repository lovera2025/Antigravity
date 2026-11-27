import '../../caja_sesiones/models/permisos_operador.dart';
import '../datos/barra_repositorio.dart';
import 'pedido_de_cierre.dart';

/// Quién hace algo en la barra. Sale del PIN que se puso en ese aparato (y de sus
/// permisos), o del modo jefe; nunca de lo que diga una fila.
enum RolEnLaBarra {
  /// Vende con su caja, a ciegas: no ve plata, no anula ni toca el cambio.
  cajera,

  /// Mira y controla: ve todas las cajas con la plata, anula, retira, maneja el cambio y
  /// da el OK de los cierres. También puede vender con su propia caja, en una tablet.
  encargada,

  /// Solo el stock: lo que hay, lo que tiene que cargar, y anota cada movimiento.
  repositor,

  /// Todo.
  jefe,

  /// La central de la otra barra, enganchada con esta: ya revisó lo de sus cajas.
  central,
}

/// Lo que no le toca a quien está usando el aparato: el guardado no lo hace.
class NoLeTocaEnLaBarra implements Exception {
  final String motivo;
  const NoLeTocaEnLaBarra(this.motivo);

  @override
  String toString() => motivo;
}

/// **Quién puede qué en la barra** (decidido por el usuario el 26-nov-2026, con la matriz
/// del plan del 4-dic). Una sola regla, pura, que usan las pantallas, el guardado
/// (`BarraConLaRed`) y la central de la notebook (lo que llega por el wifi). Si una
/// pantalla deja algo y el guardado o la central no, gana el no.
abstract final class ReglasDeLaBarra {
  /// El rol de un operador en la barra según sus permisos. Null: no es de la barra.
  static RolEnLaBarra? dePermisos(PermisosEfectivos p) {
    if (p.encargadaBarra) return RolEnLaBarra.encargada;
    if (p.barra) return RolEnLaBarra.cajera;
    return null;
  }

  /// Abrir una caja y vender en ella: la cajera, y la encargada con su propia caja.
  static bool abreCajaYVende(RolEnLaBarra? r) => r == RolEnLaBarra.cajera || r == RolEnLaBarra.encargada;

  /// Anular una venta (siempre con motivo). **La cajera no** (26-nov-2026).
  static bool anula(RolEnLaBarra? r) =>
      r == RolEnLaBarra.encargada || r == RolEnLaBarra.jefe || r == RolEnLaBarra.central;

  /// Sacar efectivo de una caja, o darle, agregarle o ajustarle el cambio después de
  /// abierta (con el porqué). La cajera pone el cambio solo al abrir.
  static bool manejaLaPlataDeLasCajas(RolEnLaBarra? r) => r == RolEnLaBarra.encargada || r == RolEnLaBarra.jefe;

  /// **La cajera pone el cambio una sola vez** (26-nov-2026): si abrió sin cambio, lo
  /// puede poner mientras no vendió nada; después lo maneja la encargada.
  static bool cajeraPoneElCambio(CajaBarra caja, {required bool yaVendio}) => caja.cambioInicial == 0 && !yaVendio;

  /// Ver todas las cajas con la plata (LAS CAJAS), su detalle e imprimirlo.
  static bool veLaPlataDeTodas(RolEnLaBarra? r) => r == RolEnLaBarra.encargada || r == RolEnLaBarra.jefe;

  /// Dar el OK de un cierre o pedir que cuente de nuevo.
  static bool daElOk(RolEnLaBarra? r) => r == RolEnLaBarra.encargada || r == RolEnLaBarra.jefe;

  /// Reponer, pasar de una barra a otra, faltantes, contar, "voy en camino".
  static bool mueveElStock(RolEnLaBarra? r) => r == RolEnLaBarra.repositor || r == RolEnLaBarra.jefe;

  /// Repartir con cuánto arranca cada barra y poner el aviso.
  static bool reparteElStock(RolEnLaBarra? r) => r == RolEnLaBarra.jefe;

  /// El catálogo, los precios y el recargo.
  static bool cambiaCatalogoYPrecios(RolEnLaBarra? r) => r == RolEnLaBarra.jefe;

  /// **Ver** el catálogo y los precios de venta, sin cambiarlos: la encargada y el jefe
  /// (pedido del usuario el 26-nov-2026: "que pueda ver el catálogo y precio, y hasta
  /// ahí").
  static bool veCatalogoYPrecios(RolEnLaBarra? r) => r == RolEnLaBarra.encargada || r == RolEnLaBarra.jefe;

  /// El precio de lista, las recetas, lo que se le debe al proveedor y la ganancia:
  /// **solo el jefe** (audio 77, 26-nov-2026). La encargada no.
  static bool veElCostoYLaGanancia(RolEnLaBarra? r) => r == RolEnLaBarra.jefe;

  /// **Si la caja [cajaId] se puede cerrar ya**: el jefe sí; los demás, solo con el OK
  /// del último pedido o habiendo cerrado sin esperar (con su motivo, anotado antes).
  static bool puedeCerrar(RolEnLaBarra? rol, String cajaId, Iterable<PasoDelCierre> pasos) {
    if (rol == RolEnLaBarra.jefe || rol == RolEnLaBarra.central) return true;
    final e = PedidoDeCierre.de(cajaId, pasos);
    return e.aceptado || e.sinOk;
  }

  /// **Si lo que manda un aparato por el wifi se guarda en la central** (null) o por qué
  /// no. [rol], [equipo] y [operadorId] son de quien puso su PIN en ese aparato; [yaEsta]
  /// es la fila con ese id que ya tiene la central; [caja], la caja de la fila; [pasos],
  /// los pasos del cierre de esa caja (solo hacen falta para un cierre); y
  /// [hechoPorUnaEncargada], si quien firma la fila es una encargada (el OK que se da en
  /// la tablet de la cajera con LA ENCARGADA ESTÁ ACÁ).
  ///
  /// Lo que no es de ese aparato (otro `device_id`: una fila de otro que tenía guardada)
  /// se acepta solo si la central no la tiene: así se repone lo que faltaba, sin pisar
  /// nada de nadie.
  static String? porQueNoSeGuarda({
    required String tabla,
    required Map<String, Object?> fila,
    required RolEnLaBarra rol,
    required String equipo,
    String? operadorId,
    Map<String, Object?>? yaEsta,
    CajaBarra? caja,
    Iterable<PasoDelCierre> pasos = const [],
    bool hechoPorUnaEncargada = false,
  }) {
    if (rol == RolEnLaBarra.jefe || rol == RolEnLaBarra.central) return null;
    final deEsteAparato = fila['device_id'] == equipo;
    if (!deEsteAparato) {
      return yaEsta == null ? null : 'No se pisa lo que hizo otro aparato';
    }
    final cajaPropia = caja != null && caja.deviceId == equipo;
    switch (tabla) {
      case 'barra_stock_movimientos':
        return mueveElStock(rol) ? null : 'El stock lo mueve el repositor';
      case 'barra_stock_barras':
        return 'El reparto lo hace el jefe';
    }
    if (rol == RolEnLaBarra.repositor) return 'El repositor solo anota el stock';
    switch (tabla) {
      case 'barra_cajas':
        if (!abreCajaYVende(rol)) return 'No abre cajas';
        if (yaEsta == null) {
          return fila['operador_id'] == operadorId ? null : 'La caja es de otra persona';
        }
        if (yaEsta['device_id'] != equipo) return 'La caja es de otro aparato';
        final cambioAntes = yaEsta['cambio_inicial'];
        if ('$cambioAntes' != '${fila['cambio_inicial']}' &&
            !manejaLaPlataDeLasCajas(rol) &&
            !(cambioAntes is num && cambioAntes == 0)) {
          return 'El cambio lo maneja la encargada';
        }
        final cierra = yaEsta['cerrada_at'] == null && fila['cerrada_at'] != null;
        if (cierra && !puedeCerrar(rol, '${fila['id']}', pasos)) return 'Falta el OK de la encargada';
        return null;
      case 'barra_ventas':
        if (!abreCajaYVende(rol)) return 'No vende';
        if (!cajaPropia) return 'La venta es de una caja de otro aparato';
        if (yaEsta != null) return 'Una venta no se cambia';
        return null;
      case 'barra_vales':
        return cajaPropia || veLaPlataDeTodas(rol) ? null : 'El vale es de una caja de otro aparato';
      case 'barra_anulaciones':
        // La encargada desde su aparato, o con su PIN en la tablet de esa caja.
        return anula(rol) || (cajaPropia && hechoPorUnaEncargada) ? null : 'Anula solo la encargada';
      case 'barra_cierres':
        final tipo = TipoPasoDelCierre.deClave(fila['tipo'] as String?);
        if (tipo == TipoPasoDelCierre.ok || tipo == TipoPasoDelCierre.recontar) {
          // La encargada, desde su aparato, a una caja que no es la suya.
          if (daElOk(rol) && caja != null && caja.operadorId != operadorId) return null;
          // LA ENCARGADA ESTÁ ACÁ: su PIN en la tablet de la cajera.
          if (cajaPropia && hechoPorUnaEncargada) return null;
          return 'El OK lo da la encargada';
        }
        return cajaPropia ? null : 'El cierre es de una caja de otro aparato';
    }
    return 'No se reparte';
  }
}
