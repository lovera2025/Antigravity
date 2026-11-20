import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../barra/cuentas/pesos.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/entrega_por_partes.dart';
import '../../eventos/services/lugares_pagos.dart';
import '../../eventos/services/retiro_entradas.dart';
import '../../eventos/services/salon_mesas.dart';
import '../cuentas/lugares_de_la_familia.dart';
import 'vender_a_pagar.dart';

/// Un alumno de la fiesta en VENDER, con todo lo que se ve de él ya contado
/// (se arma una vez por lectura, no en cada dibujo).
///
/// **Ninguna cuenta nueva**: lo que debe es `RetiroEntradas.deudaDe`, si puede
/// retirar es `RetiroEntradas.bloqueo`, el grupo del filtro es
/// `EntregaPorPartes.grupoDe`, cómo está la entrega es [EstadoDeLaEntrega] y lo
/// de A PAGAR, [APagarDeLaFamilia] con [LugaresDeLaFamilia].
class AlumnoDeVender {
  final ContratoAlumno alumno;
  final DeudaAlumno deuda;
  final BloqueoRetiro bloqueo;
  final GrupoDeRetiro grupo;
  final EstadoDeLaEntrega estado;
  final APagarDeLaFamilia aPagar;
  final LugaresDeLaFamilia lugares;

  const AlumnoDeVender({
    required this.alumno,
    required this.deuda,
    required this.bloqueo,
    required this.grupo,
    required this.estado,
    required this.aPagar,
    required this.lugares,
  });

  String get id => alumno.id;

  /// "5° A · mesa 12-13", o "sin mesa".
  String get divisionYMesa {
    final division = (alumno.cursoDivision ?? '').trim();
    final mesa = SalonMesas.textoMesasPuerta(alumno);
    return [
      if (division.isNotEmpty) division,
      mesa == null ? 'sin mesa' : 'mesa $mesa',
    ].join(' · ');
  }

  /// El estado, en el chip de su renglón: "Pagó todo", "Debe $ 70.000",
  /// "Revisar la cuenta", "✓ Retiró".
  ({String texto, Color color, IconData? icono}) get chip {
    final verde = Colors.green.shade700;
    final naranja = Colors.orange.shade800;
    switch (grupo) {
      case GrupoDeRetiro.yaRetiro:
        return (texto: '✓ Retiró', color: verde, icono: null);
      case GrupoDeRetiro.puedeRetirar:
        final parte = estado.pulseras.entregada
            ? ' · ✓ pulseras'
            : (estado.generales.entregada ? ' · ✓ generales' : '');
        return (texto: 'Pagó todo$parte', color: verde, icono: Icons.check);
      case GrupoDeRetiro.debe:
        return (
          texto: 'Debe ${pesos(deuda.total)}',
          color: Colors.red.shade700,
          icono: Icons.block,
        );
      case GrupoDeRetiro.revisar:
        return (
          texto: switch (bloqueo) {
            BloqueoRetiro.cuentaNoCoincide => 'Revisar la cuenta',
            BloqueoRetiro.sinMesa => 'Sin mesa',
            BloqueoRetiro.mesasNoCoinciden => 'Revisar sus mesas',
            BloqueoRetiro.noEntran => 'No entran',
            _ => 'Revisar',
          },
          color: naranja,
          icono: Icons.report_problem_outlined,
        );
    }
  }

  /// "3 VIP con cena + 5 generales · A pagar 8 con 50 % · 1 sin descuento": lo
  /// sin cargo que le toca y lo que **hoy** se le puede vender (solo lo pago
  /// entero; lo que espera el pago, "a confirmar").
  String resumen({required double descuentoPct}) {
    final vip = estado.pulseras.leToca;
    final generales = estado.generales.leToca;
    final sinCargo = generales > 0
        ? '$vip VIP con cena + $generales ${generales == 1 ? 'general' : 'generales'}'
        : '$vip VIP con cena';
    final l = lugares;
    final hoy = [
      if (l.quedan > 0) '${l.quedan} con ${porcentajeLegible(descuentoPct)} %',
      if (l.quedanSinDescuento > 0) '${l.quedanSinDescuento} sin descuento',
    ];
    final esperan = l.esperanElPago;
    final String aPagar;
    if (l.frenada != null && l.leCorresponden + l.sinDescuento > 0) {
      // Con la cuenta para revisar no se le vende nada: no es "nada a pagar".
      aPagar = 'A pagar: lo revisa el jefe';
    } else if (hoy.isEmpty) {
      aPagar = esperan > 0 ? 'A pagar: $esperan a confirmar' : 'nada a pagar';
    } else {
      aPagar = 'A pagar ${hoy.join(' · ')}${esperan > 0 ? ' · a confirmar $esperan' : ''}';
    }
    return '$sinCargo · $aPagar';
  }
}

/// El filtro de la lista de VENDER (pedido del usuario, 20-nov-2026: "filtrá muy
/// bien"). Abre en [puede].
enum FiltroDeVender {
  puede('vender_filtro_puede', 'Pagó todo: puede retirar'),
  debe('vender_filtro_debe', 'Debe: a caja'),
  revisar('vender_filtro_revisar', 'Revisar'),
  ya('vender_filtro_ya', 'Ya retiró'),
  todos('vender_filtro_todos', 'Todos');

  final String clave;
  final String nombre;
  const FiltroDeVender(this.clave, this.nombre);

  bool incluye(GrupoDeRetiro g) => switch (this) {
        FiltroDeVender.puede => g == GrupoDeRetiro.puedeRetirar,
        FiltroDeVender.debe => g == GrupoDeRetiro.debe,
        FiltroDeVender.revisar => g == GrupoDeRetiro.revisar,
        FiltroDeVender.ya => g == GrupoDeRetiro.yaRetiro,
        FiltroDeVender.todos => true,
      };
}

/// Los alumnos que se ven con [filtro] y lo escrito en [busqueda], en orden.
List<AlumnoDeVender> alumnosQueSeVen(
  Iterable<AlumnoDeVender> todos, {
  required FiltroDeVender filtro,
  required String busqueda,
}) {
  final q = busqueda.trim();
  return [
    for (final a in todos)
      if (filtro.incluye(a.grupo) &&
          (q.isEmpty || coincideTextoBusqueda([a.alumno.nombreAlumno], q)))
        a,
  ];
}

/// El buscador y el filtro, con cuántos hay en cada grupo **de lo que coincide
/// con lo escrito**. "Revisar" aparece solo si hay alguno.
class FiltrosDeVender extends StatelessWidget {
  const FiltrosDeVender({
    super.key,
    required this.todos,
    required this.filtro,
    required this.busqueda,
    required this.alBuscar,
    required this.alFiltrar,
  });

  final List<AlumnoDeVender> todos;
  final FiltroDeVender filtro;
  final TextEditingController busqueda;
  final VoidCallback alBuscar;
  final ValueChanged<FiltroDeVender> alFiltrar;

  @override
  Widget build(BuildContext context) {
    final q = busqueda.text.trim();
    final coinciden = alumnosQueSeVen(todos, filtro: FiltroDeVender.todos, busqueda: q);
    int cuantos(FiltroDeVender f) => coinciden.where((a) => f.incluye(a.grupo)).length;
    final hayParaRevisar = todos.any((a) => a.grupo == GrupoDeRetiro.revisar);
    final visibles = cuantos(filtro);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('vender_buscar'),
          controller: busqueda,
          decoration: InputDecoration(
            hintText: 'Apellido o nombre del egresado',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      busqueda.clear();
                      alBuscar();
                    },
                  ),
          ),
          onChanged: (_) => alBuscar(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in FiltroDeVender.values)
              if (f != FiltroDeVender.revisar || hayParaRevisar)
                ChoiceChip(
                  key: Key(f.clave),
                  label: Text('${f.nombre} (${cuantos(f)})'),
                  selected: filtro == f,
                  showCheckmark: false,
                  onSelected: (_) => alFiltrar(f),
                ),
          ],
        ),
        if (visibles == 0)
          Padding(
            key: const Key('vender_lista_vacia'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              q.isEmpty
                  ? 'Nadie en "${filtro.nombre}".'
                  : coinciden.isEmpty
                      ? 'Nadie con ese nombre.'
                      : 'Nadie con ese nombre en "${filtro.nombre}": '
                          'mirá los otros filtros o "Todos".',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }
}

/// Un alumno en la lista: nombre · división · mesa, el chip de su estado y lo
/// que le toca. Tocarlo lo elige.
class RenglonDeVender extends StatelessWidget {
  const RenglonDeVender({
    super.key,
    required this.info,
    required this.descuentoPct,
    required this.alElegir,
  });

  final AlumnoDeVender info;
  final double descuentoPct;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    final chip = info.chip;
    final gris = Colors.grey.shade700;
    return InkWell(
      key: Key('vender_familia_${info.id}'),
      onTap: alElegir,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: info.alumno.nombreAlumno.trim(),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: ' · ${info.divisionYMesa}',
                              style: TextStyle(color: gris),
                            ),
                          ],
                        ),
                      ),
                      ChipDeVender(
                        chip.texto,
                        key: Key('vender_estado_${info.id}'),
                        color: chip.color,
                        icono: chip.icono,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info.resumen(descuentoPct: descuentoPct),
                    key: Key('vender_resumen_${info.id}'),
                    style: TextStyle(fontSize: 13, color: gris),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
