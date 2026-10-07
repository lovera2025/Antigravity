import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/plano_evento.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../modelo/armados_predefinidos.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import '../services/armar_a_medida.dart';
import '../services/medir_salon.dart';
import '../services/plano_de_la_fiesta.dart';
import 'vista_plano.dart';

/// Lo que se eligió para el plano de la fiesta.
class EleccionPlano {
  final ArmadoSalon armado;
  final EstiloPlano estilo;
  final ModoSorteo modo;

  const EleccionPlano({
    required this.armado,
    required this.estilo,
    required this.modo,
  });
}

/// Abre "Estilo y armado": el armado del salón, el estilo y cómo se sortea,
/// en una sola hoja y con todo ya elegido. Devuelve null si se cancela.
Future<EleccionPlano?> mostrarElegirPlano({
  required BuildContext context,
  required int mesasNecesarias,
  required MedidasPlano medidas,
  PlanoEvento? actual,
  List<OcupantePlano> ocupantes = const [],
  String? armadoTrabado,
  bool rearmar = false,
}) =>
    showDialog<EleccionPlano>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ElegirPlanoDialog(
        mesasNecesarias: mesasNecesarias,
        medidas: medidas,
        actual: actual,
        ocupantes: ocupantes,
        armadoTrabado: armadoTrabado,
        rearmar: rearmar,
      ),
    );

/// Los tres pasos del plano de una fiesta: armado, estilo y sorteo.
///
/// No lee ni guarda nada: recibe lo que la fiesta necesita y devuelve la
/// elección con `Navigator.pop`. Así se prueba sin base.
class ElegirPlanoDialog extends StatefulWidget {
  /// Las mesas que tienen cargadas las familias de la fiesta.
  final int mesasNecesarias;
  final MedidasPlano medidas;

  /// El plano que la fiesta ya tiene. Null la primera vez.
  final PlanoEvento? actual;

  /// Las familias con mesa, para que la vista previa se vea como va a quedar.
  final List<OcupantePlano> ocupantes;

  /// Si no es null, el armado no se puede cambiar y este es el motivo, en
  /// palabras (ya hay familias con mesa). El estilo se cambia siempre.
  final String? armadoTrabado;

  /// Se llega desde Medidas, para armar el salón de nuevo con las medidas
  /// recién guardadas: abre con "A medida del playón" ya elegido, con las
  /// mesas y la pasarela que el salón tiene hoy. Antes abría en "Como está
  /// ahora", y LISTO no rearmaba nada. Con el armado trabado no cambia nada.
  final bool rearmar;

  const ElegirPlanoDialog({
    super.key,
    required this.mesasNecesarias,
    required this.medidas,
    this.actual,
    this.ocupantes = const [],
    this.armadoTrabado,
    this.rearmar = false,
  });

  @override
  State<ElegirPlanoDialog> createState() => _ElegirPlanoDialogState();
}

/// La opción "como está ahora": el armado que la fiesta ya tiene guardado, con
/// lo que se le haya acomodado a mano.
const _claveActual = '__actual__';

class _ElegirPlanoDialogState extends State<ElegirPlanoDialog> {
  static const double _lugarMaximo = 4.0;

  late String _armado;
  late EstiloPlano _estilo;
  late ModoSorteo _modo;

  late int _cantidad;
  late double _lugar;
  bool _pasarela = true;
  late final TextEditingController _cantidadCtrl;

  ArmadoSalon? get _armadoActual => widget.actual?.armadoONull;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.mesasNecesarias < 1 ? 1 : widget.mesasNecesarias;
    _lugar = widget.medidas.lugarMesaM
        .clamp(MedidasPlano.lugarMinimoM, _lugarMaximo)
        .toDouble();
    final hoy = _armadoActual;
    final rearmar =
        widget.rearmar && widget.armadoTrabado == null && hoy != null;
    if (rearmar) {
      // Las mesas que ya tiene (si se agregaron a mano, no se pierden) y la
      // pasarela, si tenía.
      if (hoy.cantidadComunes > _cantidad) _cantidad = hoy.cantidadComunes;
      _pasarela = ArmarAMedida.pasarelaDe(hoy) > 0;
    }
    _cantidadCtrl = TextEditingController(text: '$_cantidad');
    // Lo recomendado ya viene elegido: el armado que la fiesta tiene o, la
    // primera vez (o si se vino a armarlo de nuevo), el hecho a medida del
    // playón, que siempre da las mesas justas.
    _armado =
        hoy != null && !rearmar ? _claveActual : ArmarAMedida.claveArmado;
    _estilo = widget.actual?.estiloPlano ?? EstiloPlano.arquitecto;
    _modo = widget.actual?.modoSorteo ?? ModoSorteo.bloques;
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  OpcionesAMedida get _opciones => OpcionesAMedida(
        playon: widget.medidas.playon,
        cantidad: _cantidad,
        lugarM: _lugar,
        pasarelaM: _pasarela ? 2.1 : 0,
      );

  // El mismo armado se pide varias veces en cada dibujo: se rehace solo si
  // cambió lo que lo define.
  (int, double, bool)? _claveMemo;
  ArmadoAMedida? _memo;

  ArmadoAMedida get _aMedida {
    final clave = (_cantidad, _lugar, _pasarela);
    if (_claveMemo != clave || _memo == null) {
      _claveMemo = clave;
      _memo = ArmarAMedida.armar(_opciones);
    }
    return _memo!;
  }

  ArmadoSalon get _elegido {
    if (_armado == _claveActual) return _armadoActual!;
    if (_armado == ArmarAMedida.claveArmado) return _aMedida.armado;
    return ArmadosPredefinidos.porClave(_armado)!;
  }

  void _usarTodoElPlayon() {
    final holgado = ArmarAMedida.lugarMasHolgado(_opciones);
    if (holgado == null) return;
    // La barra va de a 10 cm: se baja al escalón que seguro entra.
    final escalon = (holgado * 10).floor() / 10;
    setState(() {
      _lugar =
          escalon.clamp(MedidasPlano.lugarMinimoM, _lugarMaximo).toDouble();
    });
  }

  void _listo() {
    Navigator.of(context).pop(
      EleccionPlano(armado: _elegido, estilo: _estilo, modo: _modo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final elegido = _elegido;
    final estado = EstadoPlano.desde(
      armado: elegido,
      ocupantes: widget.ocupantes,
    );
    final n = widget.mesasNecesarias;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estilo y armado', style: tema.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '${n == 1 ? 'La fiesta necesita 1 mesa' : 'La fiesta necesita $n mesas'}. '
                          'Ya viene todo elegido: cambiá lo que quieras y tocá LISTO.',
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tema.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Paso(numero: 1, titulo: 'Armado del salón'),
                    if (widget.armadoTrabado != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 18, color: Colors.orange.shade800),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.armadoTrabado!,
                                style: TextStyle(color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _armados(),
                    if (_armado == ArmarAMedida.claveArmado) ...[
                      const SizedBox(height: 12),
                      _panelAMedida(estado),
                    ],
                    const SizedBox(height: 20),
                    const _Paso(numero: 2, titulo: 'Estilo'),
                    _estilos(elegido, estado),
                    const SizedBox(height: 20),
                    const _Paso(numero: 3, titulo: 'Cómo se sortea'),
                    _modos(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_nombreArmado(elegido)} · ${_estilo.nombre} · '
                      '${_modo == ModoSorteo.bloques ? 'por división' : 'toda la escuela junta'}',
                      style: tema.textTheme.bodyMedium?.copyWith(
                        color: tema.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('CANCELAR'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('listo'),
                    onPressed: _listo,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('LISTO'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nombreArmado(ArmadoSalon a) =>
      _armado == _claveActual ? 'Como está ahora (${a.nombre})' : a.nombre;

  // ── Paso 1: el armado ───────────────────────────────────────────────────

  Widget _armados() {
    final actual = _armadoActual;
    final aMedida = _aMedida;
    final trabado = widget.armadoTrabado != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (actual != null)
          _tarjetaArmado(
            clave: _claveActual,
            nombre: 'Como está ahora',
            armado: actual,
            necesarias: widget.mesasNecesarias,
            habilitada: true,
          ),
        _tarjetaArmado(
          clave: ArmarAMedida.claveArmado,
          nombre: 'A medida del playón',
          armado: aMedida.armado,
          necesarias: _cantidad,
          habilitada: !trabado,
          detalle: '${aMedida.puestas} '
              '${aMedida.puestas == 1 ? 'mesa' : 'mesas'} a '
              '${MedirSalon.metros(_lugar)}',
        ),
        for (final a in ArmadosPredefinidos.todos)
          _tarjetaArmado(
            clave: a.clave,
            nombre: a.nombre,
            armado: a,
            necesarias: widget.mesasNecesarias,
            habilitada: !trabado,
          ),
      ],
    );
  }

  Widget _tarjetaArmado({
    required String clave,
    required String nombre,
    required ArmadoSalon armado,
    required int necesarias,
    required bool habilitada,
    String? detalle,
  }) {
    final comunes = armado.cantidadComunes;
    final pasto = armado.cantidadPasto;
    final faltan = necesarias - comunes - pasto;
    final conPasto = faltan <= 0 && necesarias > comunes;
    final ocupa = MedirSalon.ocupa(armado, lugarM: widget.medidas.lugarMesaM);
    final texto = detalle ??
        [
          pasto > 0 ? '$comunes mesas y $pasto de pasto' : '$comunes mesas',
          if (ocupa.isNotEmpty) PlanoDeLaFiesta.textoOcupa(ocupa),
        ].join(' · ');
    final (etiqueta, color) = faltan > 0
        ? (faltan == 1 ? 'Falta 1 mesa' : 'Faltan $faltan mesas', Colors.red.shade700)
        : conPasto
            ? ('Entra con el pasto', Colors.orange.shade800)
            : ('Entra', Colors.green.shade700);
    return _Tarjeta(
      key: Key('armado_$clave'),
      // Cinco entran en un renglón: las cuatro del jefe y la hecha a medida.
      ancho: 188,
      elegida: _armado == clave,
      onTap: habilitada ? () => setState(() => _armado = clave) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            texto,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          _Pastilla(texto: etiqueta, color: color),
        ],
      ),
    );
  }

  Widget _panelAMedida(EstadoPlano estado) {
    final r = _aMedida;
    final entran = r.faltan == 0;
    final playon = widget.medidas.playon;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 330,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Mesas')),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        key: const Key('cantidad'),
                        controller: _cantidadCtrl,
                        textAlign: TextAlign.end,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (t) {
                          final v = int.tryParse(t);
                          if (v != null && v > 0) setState(() => _cantidad = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    text: 'Distancia entre mesas: ',
                    children: [
                      TextSpan(
                        text: MedirSalon.metros(_lugar),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Slider(
                  key: const Key('distancia'),
                  value: _lugar,
                  min: MedidasPlano.lugarMinimoM,
                  max: _lugarMaximo,
                  divisions: ((_lugarMaximo - MedidasPlano.lugarMinimoM) * 10).round(),
                  label: MedirSalon.metros(_lugar),
                  onChanged: (v) =>
                      setState(() => _lugar = (v * 10).round() / 10),
                ),
                SwitchListTile(
                  key: const Key('pasarela'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Con pasarela'),
                  value: _pasarela,
                  onChanged: (v) => setState(() => _pasarela = v),
                ),
                OutlinedButton.icon(
                  key: const Key('todo_el_playon'),
                  onPressed: entran ? _usarTodoElPlayon : null,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Usar todo el playón'),
                ),
                const SizedBox(height: 12),
                Text(
                  entran
                      ? 'Entran las $_cantidad (hasta ${r.capacidad})'
                      : 'Entran ${r.capacidad}: '
                          '${r.faltan == 1 ? 'falta 1' : 'faltan ${r.faltan}'}',
                  key: const Key('resultado_medida'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: entran ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Playón de ${MedirSalon.metros(playon.frenteM)} contra el '
                  'escenario, ${MedirSalon.metros(playon.fondoM)} al fondo y '
                  '${MedirSalon.metros(playon.profundidadM)} de profundidad'
                  '${playon.aproximado ? ' (medidas aproximadas: corregilas con cinta en Personalizar).' : '.'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: VistaPlano(
                  armado: r.armado,
                  hoja: r.armado.hojas.first.id,
                  tema: TemaPlano.de(_estilo),
                  estado: estado,
                  animar: false,
                  mostrarMedidas: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Paso 2: el estilo ───────────────────────────────────────────────────

  Widget _estilos(ArmadoSalon armado, EstadoPlano estado) {
    return Row(
      children: [
        for (final e in EstiloPlano.values) ...[
          Expanded(
            child: _Tarjeta(
              key: Key('estilo_${e.name}'),
              elegida: _estilo == e,
              onTap: () => setState(() => _estilo = e),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 2.1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: IgnorePointer(
                        child: VistaPlano(
                          armado: armado,
                          hoja: armado.hojas.first.id,
                          tema: TemaPlano.de(e),
                          estado: estado,
                          animar: false,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(e.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    e.descripcion,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          if (e != EstiloPlano.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  // ── Paso 3: cómo se sortea ──────────────────────────────────────────────

  Widget _modos() {
    Widget tarjeta(ModoSorteo m, String titulo, String detalle) => Expanded(
          child: _Tarjeta(
            key: Key('modo_${m.clave}'),
            elegida: _modo == m,
            onTap: () => setState(() => _modo = m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tarjeta(
          ModoSorteo.bloques,
          'Por división',
          'Cada división en su bloque de mesas seguidas',
        ),
        const SizedBox(width: 10),
        tarjeta(
          ModoSorteo.entera,
          'Toda la escuela junta',
          'Las divisiones mezcladas, como se sortea hoy',
        ),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;

  const _Paso({required this.numero, required this.titulo});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: tema.colorScheme.primary,
            child: Text(
              '$numero',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tema.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(titulo, style: tema.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Una opción que se elige tocándola. Sin [onTap] queda gris: no se puede.
class _Tarjeta extends StatelessWidget {
  final bool elegida;
  final VoidCallback? onTap;
  final Widget child;
  final double? ancho;

  const _Tarjeta({
    super.key,
    required this.elegida,
    required this.onTap,
    required this.child,
    this.ancho,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Opacity(
      opacity: onTap == null && !elegida ? 0.45 : 1,
      child: Material(
        color: elegida
            ? tema.colorScheme.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: elegida ? tema.colorScheme.primary : tema.dividerColor,
            width: elegida ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: ancho,
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  final String texto;
  final Color color;

  const _Pastilla({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}
