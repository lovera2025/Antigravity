import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../models/invitado.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../repositories/invitados_repository.dart';
import 'lista_puerta.dart';

/// Cómo quedó la lista de la puerta después de un cambio del salón.
class PuertaAlDiaResultado {
  /// Cuántas personas tiene ahora la lista de la puerta de esa fiesta.
  final int personas;

  /// Cuántas filas se sacaron (una baja, un acompañante quitado, o todas).
  final int sacadas;

  /// Nadie tiene mesa: la fiesta no va en la lista de la puerta.
  final bool sinSorteo;

  /// No se pudo dejar al día. Las mesas ya están guardadas: esto es aparte, y
  /// se arregla con MÁS → "Pasar a la lista de la puerta".
  final bool fallo;

  const PuertaAlDiaResultado({
    required this.personas,
    required this.sacadas,
    required this.sinSorteo,
    this.fallo = false,
  });

  const PuertaAlDiaResultado.conFallo()
      : personas = 0,
        sacadas = 0,
        sinSorteo = false,
        fallo = true;

  factory PuertaAlDiaResultado.de(PlanListaPuerta plan) => PuertaAlDiaResultado(
        personas: plan.personas,
        sacadas: plan.sobrantes.length,
        sinSorteo: plan.sinSorteo,
      );

  /// El renglón que se suma al aviso de lo que se hizo. Vacío si no hay nada
  /// para decir (la fiesta no estaba en la puerta y sigue sin estar).
  String get renglon {
    if (fallo) {
      return 'La lista de la puerta no se pudo actualizar: tocá MÁS → '
          '"Pasar a la lista de la puerta"';
    }
    if (sinSorteo) {
      return sacadas > 0
          ? 'Recepción y el tótem quedaron sin la lista de esta fiesta'
          : '';
    }
    return 'Recepción y el tótem ya tienen la lista: $personas persona(s)';
  }
}

/// **La puerta sigue al sorteo.**
///
/// El sorteo deja la mesa en el alumno (`contratos_alumnos.numero_mesa`), pero
/// Recepción y el tótem leen `invitados`. Esto las pone de acuerdo cada vez que
/// el jefe cambia el salón, para que no dependa de acordarse de pasar la lista:
///
/// - al sortear, restaurar o cambiar una familia de mesa, la lista de la fiesta
///   se arma (o se corrige) sola;
/// - al deshacer el sorteo entero, se vacía sola.
///
/// **Armar o vaciar la lista entera ([trasElSalon]) solo lo hace la PC que
/// acaba de cambiar el salón**, que es la del jefe y que antes de guardar ya
/// miró la nube (`mesasDeOtraPcSinBajar`). Las demás la reciben por la nube,
/// como cualquier otro dato: una PC atrasada nunca arma ni vacía la lista por
/// su cuenta.
///
/// Corregir las filas de un alumno ([trasLosAlumnos], [trasEliminar]) lo hace
/// cualquiera que le cambie el nombre o lo dé de baja: son sus filas y nada
/// más, y en una PC donde nadie tiene mesa no hace nada.
///
/// No tira: las mesas ya están guardadas cuando se llama. Si algo falla,
/// devuelve [PuertaAlDiaResultado.fallo] y el aviso dice cómo arreglarlo.
class PuertaAlDia {
  final ContratosRepository _contratos;
  final InvitadosRepository _invitados;
  final ConnectivityService _conexion;

  const PuertaAlDia(this._contratos, this._invitados, this._conexion);

  /// Cómo quedaría la lista de [eventoId], sin escribir nada. Con [soloDe],
  /// solo lo de esos alumnos (ver [planListaPuerta]).
  ///
  /// Antes baja lo que haya cargado otra PC, si hay red: se compara contra la
  /// lista real, no contra la que esta PC tenía.
  Future<PlanListaPuerta> comoQuedaria(
    String eventoId, {
    Set<String>? soloDe,
  }) async {
    if (_conexion.currentStatus == AppConnectivity.online) {
      await _invitados.forceRefresh(eventoId);
    }
    return planListaPuerta(
      alumnos: await _contratos.getByEvento(eventoId),
      existentes: await _invitados.getLocalesByEvento(eventoId),
      soloDe: soloDe,
    );
  }

  /// Después de sortear, deshacer, restaurar o cambiar familias de mesa: deja
  /// la lista de la fiesta entera como las mesas de hoy.
  Future<PuertaAlDiaResultado> trasElSalon(String eventoId) =>
      _aplicar(eventoId, null);

  /// Después de cambiarle a uno o varios alumnos algo que la puerta muestra
  /// —el nombre, la mesa, los acompañantes, una baja o una reincorporación—:
  /// corrige solo sus filas. Nunca vacía la fiesta.
  Future<PuertaAlDiaResultado> trasLosAlumnos(
    String eventoId,
    Iterable<String> contratoIds,
  ) =>
      _aplicar(eventoId, contratoIds.toSet());

  /// Después de eliminar a un alumno para siempre: saca sus filas de la
  /// puerta. Hay que hacerlo en ese momento: sin el alumno ya no hay forma de
  /// saber cuáles eran las suyas, y quedarían en la lista para siempre.
  Future<PuertaAlDiaResultado> trasEliminar(
    String eventoId,
    String contratoId,
  ) async {
    try {
      final suyas = {
        for (var lugar = 0; lugar < kMaxLugaresPorAlumno; lugar++)
          idInvitadoPuerta(contratoId, lugar),
      };
      final existentes = await _invitados.getLocalesByEvento(eventoId);
      final plan = PlanListaPuerta(
        nuevas: const [],
        aActualizar: const [],
        iguales: 0,
        sobrantes: [
          for (final i in existentes)
            if (suyas.contains(i.id)) i,
        ],
        yaIngresados: 0,
      );
      await _invitados.aplicarListaPuerta(eventoId, plan);
      return PuertaAlDiaResultado.de(plan);
    } catch (e) {
      debugPrint('No se pudo sacar de la puerta al alumno eliminado: $e');
      return const PuertaAlDiaResultado.conFallo();
    }
  }

  /// Cuántos de los que salieron de los alumnos están marcados como adentro.
  /// Es lo que se perdería al deshacer el sorteo entero.
  Future<int> adentro(String eventoId) async {
    try {
      final alumnos = await _contratos.getByEvento(eventoId);
      final generados = {
        for (final a in alumnos)
          for (var lugar = 0; lugar < kMaxLugaresPorAlumno; lugar++)
            idInvitadoPuerta(a.id, lugar),
      };
      final existentes = await _invitados.getLocalesByEvento(eventoId);
      return existentes
          .where(
            (i) =>
                generados.contains(i.id) &&
                i.estadoIngreso == EstadoIngreso.ingresado,
          )
          .length;
    } catch (e) {
      debugPrint('No se pudo contar los ingresos de la puerta: $e');
      return 0;
    }
  }

  Future<PuertaAlDiaResultado> _aplicar(
    String eventoId,
    Set<String>? soloDe,
  ) async {
    try {
      final plan = await comoQuedaria(eventoId, soloDe: soloDe);
      await _invitados.aplicarListaPuerta(eventoId, plan);
      return PuertaAlDiaResultado.de(plan);
    } catch (e) {
      debugPrint('La lista de la puerta no se pudo dejar al día: $e');
      return const PuertaAlDiaResultado.conFallo();
    }
  }
}

final puertaAlDiaProvider = Provider<PuertaAlDia>(
  (ref) => PuertaAlDia(
    ref.watch(contratosRepositoryProvider),
    ref.watch(invitadosRepositoryProvider),
    ref.watch(connectivityServiceProvider),
  ),
);
