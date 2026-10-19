import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/plano_evento.dart';
import '../../../models/predio.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../modelo/armados_predefinidos.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import '../services/armar_a_medida.dart';
import '../services/medir_salon.dart';
import '../services/plano_de_la_fiesta.dart';
import '../services/predios_del_salon.dart';
import 'nombre_predio_dialog.dart';
import 'vista_plano.dart';

/// Lo que se eligió para el plano de la fiesta.
class EleccionPlano {
  final ArmadoSalon armado;
  final EstiloPlano estilo;
  final ModoSorteo modo;

  /// Se eligió un predio (6.1.0): sus medidas pasan a Medidas. Null: otro
  /// armado.
  final PlayonReal? playon;

  const EleccionPlano({
    required this.armado,
    required this.estilo,
    required this.modo,
    this.playon,
  });
}

/// Lo que dice la pantalla después de renombrar o borrar un predio: la lista
/// como quedó, y qué pasó en palabras.
typedef CambioDePredios = ({List<Predio> predios, String texto});

/// Renombrar y Borrar un predio desde el menú ⋯ de su tarjeta (6.1.0). Los
/// guarda la pantalla; el diálogo pregunta y muestra cómo quedó.
class AccionesPredios {
  final Future<CambioDePredios> Function(Predio predio, String nombre)
      onRenombrar;
  final Future<CambioDePredios> Function(Predio predio) onBorrar;

  const AccionesPredios({required this.onRenombrar, required this.onBorrar});
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
  List<Predio> predios = const [],
  AccionesPredios? accionesPredios,
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
        predios: predios,
        accionesPredios: accionesPredios,
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

  /// Los predios con nombre (6.1.0), sin los borrados: una tarjeta por predio,
  /// después de "Salón vacío".
  final List<Predio> predios;

  /// Renombrar y Borrar desde el menú ⋯ de cada predio. Null: sin menú.
  final AccionesPredios? accionesPredios;

  const ElegirPlanoDialog({
    super.key,
    required this.mesasNecesarias,
    required this.medidas,
    this.actual,
    this.ocupantes = const [],
    this.armadoTrabado,
    this.rearmar = false,
    this.predios = const [],
    this.accionesPredios,
  });

  @override
  State<ElegirPlanoDialog> createState() => _ElegirPlanoDialogState();
}

/// La opción "como está ahora": el armado que la fiesta ya tiene guardado, con
/// lo que se le haya acomodado a mano.
const _claveActual = '__actual__';

const double _separacionTarjetas = 10;

/// El ancho de cada tarjeta del armado, para que los renglones salgan parejos:
/// seis tarjetas van de a tres y siete de a cuatro y tres. Antes iban de a
/// cinco, y con el salón vacío (6.1.0) la sexta quedaba sola abajo. Ninguna
/// baja de 180 px.
double anchoTarjetaArmado(double disponible, int tarjetas) {
  const minimo = 180.0;
  const s = _separacionTarjetas;
  if (!disponible.isFinite || tarjetas < 1) return minimo;
  final porFila = ((disponible + s) / (minimo + s)).floor().clamp(1, tarjetas);
  final filas = (tarjetas / porFila).ceil();
  final enFila = (tarjetas / filas).ceil();
  // Para abajo: con un pelo de más, el Wrap pasaría la última al otro renglón.
  return ((disponible - s * (enFila - 1)) / enFila).floorToDouble();
}

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
    // Lo recomendado ya viene elegido: el armado que la fiesta tiene; si se
    // vino a armarlo de nuevo, el hecho a medida del playón; y la primera vez,
    // el salón vacío (6.1.0, "el salón primero": el jefe arma el espacio y
    // después pone las mesas; antes saltaban todas al tocar LISTO). Si ya hay
    // familias con mesa, el hecho a medida, que da las mesas justas.
    _armado = hoy != null && !rearmar
        ? _claveActual
        : rearmar || _vacioApagado != null
            ? ArmarAMedida.claveArmado
            : ArmarAMedida.claveVacio;
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

  /// El salón vacío, con el playón y la distancia de la fiesta.
  late final ArmadoSalon _vacio = ArmarAMedida.vacio(
    widget.medidas.playon,
    lugarM: widget.medidas.lugarMesaM,
  );

  /// Por qué no se puede elegir el salón vacío, o null si se puede. Con
  /// familias ya sentadas (un sorteo hecho sin plano), sus números serían de
  /// mesas que no existen. Si la fiesta ya tiene plano, el armado entero lo
  /// traba [ElegirPlanoDialog.armadoTrabado].
  String? get _vacioApagado => widget.ocupantes.isEmpty
      ? null
      : 'Ya hay familias con mesa: se quedarían sin la suya.';

  // ── Los predios con nombre (6.1.0) ──

  /// Los que se pueden elegir: renombrar o borrar uno la cambia.
  late List<Predio> _predios = [
    for (final p in widget.predios)
      if (!p.borrado && p.espacioONull != null) p,
  ];

  /// El salón de cada predio, con la distancia de la fiesta: se arma una vez.
  final _salones = <String, ArmadoSalon>{};

  ArmadoSalon _salonDe(Predio p) => _salones.putIfAbsent(
        p.id,
        () => PrediosDelSalon.salonDe(p, lugarM: widget.medidas.lugarMesaM)!,
      );

  Predio? get _predioElegido {
    for (final p in _predios) {
      if (ArmarAMedida.claveDePredio(p.id) == _armado) return p;
    }
    return null;
  }

  /// Lo que pasó con el último Renombrar o Borrar, debajo de las tarjetas.
  String? _avisoPredios;

  void _ponerPredios(List<Predio> predios) {
    _predios = [
      for (final p in predios)
        if (!p.borrado && p.espacioONull != null) p,
    ];
    _salones.clear();
    // El que estaba elegido se borró: vuelve a lo de la primera vez.
    if (_armado.startsWith(ArmarAMedida.prefijoPredio) &&
        _predioElegido == null) {
      _armado = _armadoActual != null
          ? _claveActual
          : _vacioApagado != null
              ? ArmarAMedida.claveArmado
              : ArmarAMedida.claveVacio;
    }
  }

  Future<void> _renombrar(Predio p) async {
    final acciones = widget.accionesPredios;
    if (acciones == null) return;
    final nombre = await pedirNombreDePredio(
      context: context,
      guardados: _predios,
      renombrando: p,
    );
    if (nombre == null || nombre == p.nombre || !mounted) return;
    final r = await acciones.onRenombrar(p, nombre);
    if (!mounted) return;
    setState(() {
      _ponerPredios(r.predios);
      _avisoPredios = r.texto;
    });
  }

  /// Borrar se pide dos veces: el menú y esta pregunta.
  Future<void> _borrar(Predio p) async {
    final acciones = widget.accionesPredios;
    if (acciones == null) return;
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar el predio "${p.nombre}"?'),
        content: const Text(
          'Deja de aparecer en Estilo y armado. Las fiestas que lo usaron '
          'siguen con su copia y no cambian.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            key: const Key('confirmar_borrar_predio'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('BORRAR'),
          ),
        ],
      ),
    );
    if (seguro != true || !mounted) return;
    final r = await acciones.onBorrar(p);
    if (!mounted) return;
    setState(() {
      _ponerPredios(r.predios);
      _avisoPredios = r.texto;
    });
  }

  ArmadoSalon get _elegido {
    if (_armado == _claveActual) return _armadoActual!;
    if (_armado == ArmarAMedida.claveVacio) return _vacio;
    if (_armado == ArmarAMedida.claveArmado) return _aMedida.armado;
    final predio = _predioElegido;
    if (predio != null) return _salonDe(predio);
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
      EleccionPlano(
        armado: _elegido,
        estilo: _estilo,
        modo: _modo,
        playon: _predioElegido?.playon,
      ),
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
                    if (_avisoPredios != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _avisoPredios!,
                        key: const Key('aviso_predios'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ],
                    if (_armado == ArmarAMedida.claveVacio) ...[
                      const SizedBox(height: 12),
                      _notaVacio(),
                    ],
                    if (_predioElegido != null) ...[
                      const SizedBox(height: 12),
                      _notaPredio(_predioElegido!),
                    ],
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
    final cuantas = (actual != null ? 1 : 0) +
        2 +
        _predios.length +
        ArmadosPredefinidos.todos.length;
    return LayoutBuilder(
      builder: (context, lugar) {
        final ancho = anchoTarjetaArmado(lugar.maxWidth, cuantas);
        return Wrap(
          spacing: _separacionTarjetas,
          runSpacing: _separacionTarjetas,
          children: [
            if (actual != null)
              _tarjetaArmado(
                clave: _claveActual,
                nombre: 'Como está ahora',
                armado: actual,
                necesarias: widget.mesasNecesarias,
                habilitada: true,
                ancho: ancho,
              ),
            _tarjetaVacio(ancho),
            for (final p in _predios) _tarjetaPredio(p, ancho),
            _tarjetaArmado(
              clave: ArmarAMedida.claveArmado,
              nombre: 'A medida del playón',
              armado: aMedida.armado,
              necesarias: _cantidad,
              habilitada: !trabado,
              ancho: ancho,
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
                ancho: ancho,
              ),
          ],
        );
      },
    );
  }

  Widget _tarjetaArmado({
    required String clave,
    required String nombre,
    required ArmadoSalon armado,
    required int necesarias,
    required bool habilitada,
    required double ancho,
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
      ancho: ancho,
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

  /// El salón vacío no dice si entra la fiesta: las mesas se ponen después.
  /// Apagado, dice por qué (lo que se traba se ve, con el motivo).
  Widget _tarjetaVacio(double ancho) {
    final trabado = widget.armadoTrabado != null;
    final apagado = trabado ? null : _vacioApagado;
    return _Tarjeta(
      key: const Key('armado_${ArmarAMedida.claveVacio}'),
      ancho: ancho,
      elegida: _armado == ArmarAMedida.claveVacio,
      onTap: trabado || apagado != null
          ? null
          : () => setState(() => _armado = ArmarAMedida.claveVacio),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Salón vacío',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            apagado ??
                'El playón y el escenario, para armar el espacio. Las mesas '
                    'se ponen después, desde Acomodar.',
            style: TextStyle(
              fontSize: 12,
              color: apagado != null
                  ? Colors.orange.shade800
                  : Colors.grey.shade700,
            ),
          ),
          if (apagado == null) ...[
            const SizedBox(height: 6),
            _Pastilla(texto: 'Mesas después', color: Colors.blueGrey.shade600),
          ],
        ],
      ),
    );
  }

  /// Un predio con nombre (6.1.0): su dibujo, lo que mide su playón y el menú
  /// ⋯ para renombrarlo o borrarlo. Se elige igual que el salón vacío: con
  /// familias sentadas, apagado con el motivo.
  Widget _tarjetaPredio(Predio p, double ancho) {
    final clave = ArmarAMedida.claveDePredio(p.id);
    final trabado = widget.armadoTrabado != null;
    final apagado = trabado ? null : _vacioApagado;
    final salon = _salonDe(p);
    final pl = p.playon;
    return _Tarjeta(
      key: Key('armado_$clave'),
      ancho: ancho,
      elegida: _armado == clave,
      onTap: trabado || apagado != null
          ? null
          : () => setState(() => _armado = clave),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.accionesPredios != null)
                SizedBox(
                  width: 28,
                  height: 22,
                  child: PopupMenuButton<String>(
                    key: Key('menu_predio_${p.id}'),
                    tooltip: 'Renombrar o borrar',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (accion) =>
                        accion == 'borrar' ? _borrar(p) : _renombrar(p),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        key: Key('renombrar_predio'),
                        value: 'renombrar',
                        child: Text('Renombrar…'),
                      ),
                      PopupMenuItem(
                        key: Key('borrar_predio'),
                        value: 'borrar',
                        child: Text('Borrar'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 60,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: IgnorePointer(
                child: VistaPlano(
                  key: Key('dibujo_predio_${p.id}'),
                  armado: salon,
                  hoja: salon.hojas.first.id,
                  tema: TemaPlano.de(_estilo),
                  estado: EstadoPlano.desde(armado: salon, ocupantes: const []),
                  animar: false,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            apagado ??
                '${MedirSalon.metros(pl.frenteM).replaceFirst(' m', '')} × '
                    '${MedirSalon.metros(pl.fondoM).replaceFirst(' m', '')} × '
                    '${MedirSalon.metros(pl.profundidadM)} · sin mesas',
            style: TextStyle(
              fontSize: 12,
              color: apagado != null
                  ? Colors.orange.shade800
                  : Colors.grey.shade700,
            ),
          ),
          if (apagado == null) ...[
            const SizedBox(height: 6),
            _Pastilla(texto: 'Mesas después', color: Colors.blueGrey.shade600),
          ],
        ],
      ),
    );
  }

  /// Con qué arranca el salón que sale del predio.
  Widget _notaPredio(Predio p) {
    final pl = p.playon;
    return Text(
      'Arranca con el espacio de ${p.nombre} (${MedirSalon.metros(pl.frenteM)} '
      'contra el escenario, ${MedirSalon.metros(pl.fondoM)} al fondo y '
      '${MedirSalon.metros(pl.profundidadM)} de profundidad), sin mesas, y '
      'sus medidas pasan a Medidas. Las mesas se ponen después con ACOMODAR '
      'LAS MESAS, a la distancia de esta fiesta. Si el predio cambia, esta '
      'fiesta no: se lleva una copia.',
      key: const Key('nota_predio'),
      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
    );
  }

  /// Con qué playón arranca el salón vacío, y dónde se cambia.
  Widget _notaVacio() {
    final p = widget.medidas.playon;
    final playon = p == PlayonReal.costaSurubi
        ? 'el playón de Costa Surubí'
        : 'el playón de la fiesta';
    return Text(
      'Arranca con $playon (${MedirSalon.metros(p.frenteM)} contra el '
      'escenario, ${MedirSalon.metros(p.fondoM)} al fondo y '
      '${MedirSalon.metros(p.profundidadM)} de profundidad), el escenario y el '
      'Ingreso. Si la fiesta es en otro predio, el espacio se cambia en '
      'Personalizar → Acomodar, y ahí se guarda como predio para la próxima.',
      key: const Key('nota_vacio'),
      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
