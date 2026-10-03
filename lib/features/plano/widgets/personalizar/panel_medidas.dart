import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../modelo/medidas_salon.dart';
import '../../services/armar_a_medida.dart';
import '../../services/medir_salon.dart';

/// Personalizar → Medidas: los lados del playón como los da la cinta (el
/// frente, el fondo y un costado) y cuánto lugar pide cada mesa.
///
/// No guarda nada por su cuenta: mientras se escribe avisa lo que se va
/// probando ([onProbar]), para que el plano lo muestre, y recién con GUARDAR
/// llama a [onGuardar].
class PanelMedidas extends StatefulWidget {
  /// Las medidas guardadas de la fiesta.
  final MedidasPlano medidas;

  /// Las mesas que la fiesta necesita: si con lo que se escribe no entran, se
  /// dice.
  final int mesasNecesarias;
  final bool ocupado;
  final ValueChanged<MedidasPlano> onGuardar;

  /// Lo que se está escribiendo, si es válido y distinto de lo guardado. Null
  /// cuando vuelve a ser lo guardado o deja de ser válido.
  final ValueChanged<MedidasPlano?>? onProbar;

  /// Algo que conviene hacer después de cambiar las medidas ("El salón está
  /// armado a 2 m…"), con el botón que lleva a hacerlo.
  final String? aviso;
  final String? textoAccionAviso;
  final VoidCallback? onAccionAviso;

  const PanelMedidas({
    super.key,
    required this.medidas,
    required this.mesasNecesarias,
    required this.onGuardar,
    this.ocupado = false,
    this.onProbar,
    this.aviso,
    this.textoAccionAviso,
    this.onAccionAviso,
  });

  /// "39,8": con coma y sin ceros de más, para escribir en un casillero.
  static String numero(double v) {
    final t = v.toStringAsFixed(2);
    return t
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceFirst('.', ',');
  }

  /// Un número escrito con coma o con punto. Null si no es un número.
  static double? leer(String texto) {
    final v = double.tryParse(texto.trim().replaceFirst(',', '.'));
    return v == null || !v.isFinite ? null : v;
  }

  @override
  State<PanelMedidas> createState() => _PanelMedidasState();
}

class _PanelMedidasState extends State<PanelMedidas> {
  final _frente = TextEditingController();
  final _fondo = TextEditingController();
  final _costado = TextEditingController();
  final _lugar = TextEditingController();
  final _extra = TextEditingController();

  /// Lo que se escribió por última vez en los casilleros del playón al
  /// cargarlos: mientras no cambien, el playón es el guardado tal cual (el
  /// costado se muestra redondeado, y volver a calcular con él lo movería).
  late List<String> _playonCargado;

  @override
  void initState() {
    super.initState();
    _cargar(widget.medidas);
  }

  @override
  void didUpdateWidget(PanelMedidas old) {
    super.didUpdateWidget(old);
    // Se guardó (o bajó otra cosa de la otra PC): los casilleros muestran lo
    // que quedó.
    if (old.medidas != widget.medidas) _cargar(widget.medidas);
  }

  @override
  void dispose() {
    for (final c in [_frente, _fondo, _costado, _lugar, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  void _cargar(MedidasPlano m) {
    _frente.text = PanelMedidas.numero(m.playon.frenteM);
    _fondo.text = PanelMedidas.numero(m.playon.fondoM);
    _costado.text = PanelMedidas.numero(m.playon.costadoM);
    _lugar.text = PanelMedidas.numero(m.lugarMesaM);
    _extra.text = PanelMedidas.numero(m.extraPorSillaM);
    _playonCargado = [_frente.text, _fondo.text, _costado.text];
    _base = m;
  }

  /// De dónde salieron los casilleros: lo guardado, o las de fábrica si se
  /// tocó "volver a las de fábrica".
  late MedidasPlano _base;

  bool get _playonSinTocar =>
      _frente.text == _playonCargado[0] &&
      _fondo.text == _playonCargado[1] &&
      _costado.text == _playonCargado[2];

  /// Lo que dicen los casilleros, o por qué no sirve.
  ({MedidasPlano? medidas, String? problema}) _leer() {
    final lugar = PanelMedidas.leer(_lugar.text);
    final extra = PanelMedidas.leer(_extra.text);
    if (lugar == null ||
        lugar < MedidasPlano.lugarMinimoM ||
        lugar > MedidasPlano.lugarMaximoM) {
      return (
        medidas: null,
        problema: 'Entre mesas van de '
            '${MedirSalon.metros(MedidasPlano.lugarMinimoM)} a '
            '${MedirSalon.metros(MedidasPlano.lugarMaximoM)}.',
      );
    }
    if (extra == null || extra < 0 || extra > 1) {
      return (
        medidas: null,
        problema: 'Por silla extra va de 0 a 1 m.',
      );
    }
    final PlayonReal playon;
    if (_playonSinTocar) {
      playon = _base.playon;
    } else {
      final frente = PanelMedidas.leer(_frente.text);
      final fondo = PanelMedidas.leer(_fondo.text);
      final costado = PanelMedidas.leer(_costado.text);
      bool sirve(double? v) =>
          v != null &&
          v >= PlayonReal.ladoMinimoM &&
          v <= PlayonReal.ladoMaximoM;
      if (!sirve(frente) || !sirve(fondo) || !sirve(costado)) {
        return (
          medidas: null,
          problema: 'Cada lado del playón va de '
              '${MedirSalon.metros(PlayonReal.ladoMinimoM)} a '
              '${MedirSalon.metros(PlayonReal.ladoMaximoM)}.',
        );
      }
      final armado = PlayonReal.conCostado(
        frenteM: frente!,
        fondoM: fondo!,
        costadoM: costado!,
      );
      if (armado == null || armado.profundidadM < PlayonReal.ladoMinimoM) {
        return (
          medidas: null,
          problema: 'Con esas medidas el playón no cierra: el costado es '
              'muy corto para ese frente y ese fondo.',
        );
      }
      playon = armado;
    }
    return (
      medidas: MedidasPlano(
        lugarMesaM: lugar,
        extraPorSillaM: extra,
        playon: playon,
      ),
      problema: null,
    );
  }

  void _cambio() {
    final leido = _leer().medidas;
    widget.onProbar?.call(leido == widget.medidas ? null : leido);
    setState(() {});
  }

  void _deFabrica() {
    setState(() {
      const fabrica = MedidasPlano();
      final guardadas = widget.medidas;
      _cargar(fabrica);
      widget.onProbar?.call(fabrica == guardadas ? null : fabrica);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final leido = _leer();
    final medidas = leido.medidas;
    final cambio = medidas != null && medidas != widget.medidas;
    final gris = TextStyle(color: Colors.grey.shade700, fontSize: 12.5);

    Widget casillero(String clave, String rotulo, TextEditingController c) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(rotulo)),
              SizedBox(
                width: 104,
                child: TextField(
                  key: Key(clave),
                  controller: c,
                  enabled: !widget.ocupado,
                  textAlign: TextAlign.right,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'm',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  ),
                  onChanged: (_) => _cambio(),
                ),
              ),
            ],
          ),
        );

    Widget titulo(String texto) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.6,
            ),
          ),
        );

    final playon = medidas?.playon;
    final capacidad = medidas == null
        ? null
        : ArmarAMedida.capacidad(OpcionesAMedida(
            playon: medidas.playon,
            cantidad: 1,
            lugarM: medidas.lugarMesaM,
          ));
    final noEntran = capacidad != null && widget.mesasNecesarias > capacidad;

    final resultado = Container(
      key: const Key('medidas_resultado'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (leido.problema != null || noEntran ? Colors.red : Colors.green)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: leido.problema != null
          ? Text(
              leido.problema!,
              style: TextStyle(color: Colors.red.shade700),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Con estas medidas entran hasta $capacidad mesas',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'El playón tiene unos ${playon!.superficieM2.round()} m².',
                  style: gris,
                ),
                if (noEntran)
                  Text(
                    'La fiesta necesita ${widget.mesasNecesarias}: no entran.',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
              ],
            ),
    );

    // Lo que se escribe va en una lista que se puede correr; el resultado y
    // GUARDAR quedan siempre a la vista, también en una pantalla baja.
    return Column(
      key: const Key('panel_medidas'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              titulo('EL PLAYÓN, CON CINTA'),
              SizedBox(
                height: 88,
                child: CustomPaint(
                  painter: _DibujoPlayon(
                    playon: playon,
                    estilo: DefaultTextStyle.of(context).style.copyWith(
                          fontSize: 11.5,
                          color: tema.colorScheme.onSurface,
                        ),
                    relleno: tema.colorScheme.primary.withValues(alpha: 0.07),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              casillero(
                  'medida_frente', 'Frente (contra el escenario)', _frente),
              casillero('medida_fondo', 'Fondo', _fondo),
              casillero('medida_costado', 'Un costado', _costado),
              titulo('CADA MESA'),
              casillero('medida_lugar', 'De centro a centro', _lugar),
              casillero('medida_extra', 'Más, por cada silla extra', _extra),
              if (playon != null && playon.aproximado)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Medidas aproximadas, tomadas de la foto satelital. '
                    'Corregilas con cinta.',
                    key: const Key('medidas_aproximadas'),
                    style: gris,
                  ),
                ),
              if ((medidas ?? widget.medidas) != const MedidasPlano())
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('medidas_de_fabrica'),
                    onPressed: widget.ocupado ? null : _deFabrica,
                    child: const Text('VOLVER A LAS DE FÁBRICA'),
                  ),
                ),
              if (widget.aviso != null && !cambio) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('aviso_medidas'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.aviso!),
                      if (widget.onAccionAviso != null &&
                          widget.textoAccionAviso != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('accion_aviso_medidas'),
                            onPressed:
                                widget.ocupado ? null : widget.onAccionAviso,
                            child: Text(widget.textoAccionAviso!),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        resultado,
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('guardar_medidas'),
                onPressed: cambio && !widget.ocupado
                    ? () => widget.onGuardar(medidas)
                    : null,
                icon: const Icon(Icons.check, size: 18),
                label: Text(cambio ? 'GUARDAR MEDIDAS' : 'MEDIDAS GUARDADAS'),
              ),
            ),
            if (cambio) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('descartar_medidas'),
                onPressed: widget.ocupado
                    ? null
                    : () => setState(() {
                          _cargar(widget.medidas);
                          widget.onProbar?.call(null);
                        }),
                child: const Text('DESCARTAR'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// El trapecio del playón, a escala, con lo que mide cada lado.
class _DibujoPlayon extends CustomPainter {
  final PlayonReal? playon;

  /// La letra de la app: un texto pintado a mano no la hereda solo.
  final TextStyle estilo;
  final Color relleno;

  _DibujoPlayon({
    required this.playon,
    required this.estilo,
    required this.relleno,
  });

  Color get color => estilo.color ?? const Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    final p = playon;
    if (p == null) return;
    const margenX = 62.0;
    const margenY = 15.0;
    final ancho = math.max(p.frenteM, p.fondoM);
    final escala = math.min(
      (size.width - 2 * margenX) / ancho,
      (size.height - 2 * margenY) / p.profundidadM,
    );
    if (!(escala > 0) || !escala.isFinite) return;
    final cx = size.width / 2;
    final arriba = (size.height - p.profundidadM * escala) / 2;
    final abajo = arriba + p.profundidadM * escala;
    final camino = Path()
      ..moveTo(cx - p.frenteM * escala / 2, arriba)
      ..lineTo(cx + p.frenteM * escala / 2, arriba)
      ..lineTo(cx + p.fondoM * escala / 2, abajo)
      ..lineTo(cx - p.fondoM * escala / 2, abajo)
      ..close();
    canvas.drawPath(camino, Paint()..color = relleno);
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.75),
    );

    void texto(String t, Offset centro, {bool alaDerecha = false}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: estilo),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = alaDerecha ? centro.dx - tp.width : centro.dx - tp.width / 2;
      tp.paint(canvas, Offset(x, centro.dy - tp.height / 2));
    }

    texto(MedirSalon.metros(p.frenteM), Offset(cx, arriba - 9));
    texto(MedirSalon.metros(p.fondoM), Offset(cx, abajo + 9));
    final bordeIzq =
        cx - (p.frenteM + p.fondoM) / 4 * escala - 6;
    texto(
      MedirSalon.metros(p.costadoM),
      Offset(bordeIzq, (arriba + abajo) / 2),
      alaDerecha: true,
    );
  }

  @override
  bool shouldRepaint(_DibujoPlayon old) =>
      old.playon != playon || old.estilo != estilo || old.relleno != relleno;
}
