import 'package:flutter/material.dart';

import '../../eventos/services/planilla_delegado.dart' show kMaxAcompanantes;
import '../datos/nube_del_delegado.dart';
import 'sesiones_del_delegado.dart';

/// La página que abre el delegado en el celular con su link (6.8.0): carga los
/// acompañantes y la música de los alumnos de su fiesta.
///
/// **No decide nada:** cada regla (quién puede tocar a quién, el límite, los
/// topes) la decide la nube, y acá solo se dice en palabras lo que contestó.
/// Tampoco usa el reloj del celular: el límite viene escrito por la nube.
///
/// - **Guardar**, en el lugar de cada alumno, guarda ese alumno y nada más.
/// - **Enviar**, uno solo y abajo, es el definitivo: pregunta antes y se hace
///   una sola vez.
class PaginaDelDelegado extends StatefulWidget {
  final String clave;
  final NubeDelDelegado nube;
  final SesionesDelDelegado sesiones;

  const PaginaDelDelegado({
    super.key,
    required this.clave,
    required this.nube,
    this.sesiones = const SesionesEnElCelular(),
  });

  @override
  State<PaginaDelDelegado> createState() => _PaginaDelDelegadoState();
}

const _fondo = Color(0xFFF3F5F9);
const _tinta = Color(0xFF17202E);
const _suave = Color(0xFF5A6678);
const _tenue = Color(0xFF9AA4B2);
const _linea = Color(0xFFD9DFE8);
const _azul = Color(0xFF1E57B8);
const _verde = Color(0xFF0E7A4B);
const _okFondo = Color(0xFFDDF3E4);
const _okTinta = Color(0xFF1B6B3A);
const _faltaFondo = Color(0xFFFBEBCB);
const _faltaTinta = Color(0xFF7A5200);
const _grisFondo = Color(0xFFE9EDF2);
const _grisTinta = Color(0xFF6B7685);
const _avisoFondo = Color(0xFFE4ECFA);
const _avisoTinta = Color(0xFF1B3F86);
const _rojo = Color(0xFFB3261E);

String _cuantos(int n, String uno, String varios) =>
    n == 1 ? '1 $uno' : '$n $varios';

String _sinAcentos(String s) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sin = 'aaaaaeeeeiiiiooooouuuun';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = con.indexOf(c);
    b.write(i >= 0 ? sin[i] : c);
  }
  return b.toString();
}

/// Lo que se le dice al delegado cuando la nube no deja guardar.
const _porQueNo = <String, String>{
  'vacio': 'Escribí al menos un acompañante o la música.',
  'tope': 'Son hasta $kMaxAcompanantes acompañantes.',
  'largo': 'Es demasiado largo. Acortalo un poco.',
  'formato': 'No se pudo leer lo que escribiste. Probá de nuevo.',
  'alumno': 'Este alumno ya no está en la lista.',
  'ya_cargado':
      'Eso ya está cargado en el programa y no se puede cambiar desde acá.',
};

class _PaginaDelDelegadoState extends State<PaginaDelDelegado> {
  final _nombre = TextEditingController();
  final _buscar = TextEditingController();
  final _ac1 = TextEditingController();
  final _ac2 = TextEditingController();
  final _musica = TextEditingController();
  final _scroll = ScrollController();

  String? _sesion;
  ListaDelDelegado? _lista;
  bool _sinRed = false;
  bool _ocupado = false;

  /// El alumno abierto, y si tiene algo escrito sin guardar.
  String? _abierto;
  bool _sucio = false;

  String? _errorEntrada;
  String? _errorForm;
  String? _errorBarra;

  @override
  void initState() {
    super.initState();
    _empezar();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _buscar, _ac1, _ac2, _musica]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _empezar() async {
    _sesion = await widget.sesiones.leer(widget.clave);
    await _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.nube.lista(widget.clave, _sesion);
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _sinRed = false;
        if (!lista.ok || lista.soloLectura) _cerrarAlumno();
      });
    } catch (_) {
      if (mounted) setState(() => _sinRed = true);
    }
  }

  void _cerrarAlumno() {
    _abierto = null;
    _sucio = false;
    _errorForm = null;
  }

  // ── Entrar ────────────────────────────────────────────────────────────────

  Future<void> _entrar() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _errorEntrada = null;
    });
    try {
      final r = await widget.nube.entrar(widget.clave, _nombre.text);
      if (r.ok && r.sesion != null) {
        _sesion = r.sesion;
        await widget.sesiones.guardar(widget.clave, r.sesion!);
        await _cargar();
      } else if (r.motivo == 'nombre') {
        _errorEntrada = 'Escribí tu nombre y tu apellido.';
      } else {
        await _cargar();
      }
    } catch (_) {
      _errorEntrada = 'No pudimos conectarnos. Probá de nuevo.';
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ── Un alumno ─────────────────────────────────────────────────────────────

  void _tocar(AlumnoDelLink a) {
    if (_abierto == a.id) {
      if (!_sucio) setState(_cerrarAlumno);
      return;
    }
    if (_sucio) {
      setState(() => _errorForm =
          'Tenés cambios sin guardar. Tocá Guardar, o Descartar.');
      return;
    }
    setState(() {
      _abierto = a.id;
      _sucio = false;
      _errorForm = null;
      _errorBarra = null;
      _ac1.text = a.acompanantes.isNotEmpty ? a.acompanantes[0] : '';
      _ac2.text = a.acompanantes.length > 1 ? a.acompanantes[1] : '';
      _musica.text = a.musica;
    });
  }

  void _escribio() {
    if (!_sucio || _errorForm != null) {
      setState(() {
        _sucio = true;
        _errorForm = null;
      });
    }
  }

  Future<void> _guardar(AlumnoDelLink a) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _errorForm = null;
      // El aviso de "cambios sin guardar" de abajo ya no corresponde.
      _errorBarra = null;
    });
    try {
      final r = await widget.nube.guardar(
        clave: widget.clave,
        sesion: _sesion ?? '',
        alumnoId: a.id,
        acompanantes: [
          if (!a.progAcomp)
            for (final c in [_ac1, _ac2])
              if (c.text.trim().isNotEmpty) c.text.trim().toUpperCase(),
        ],
        musica: a.progMusica ? '' : _musica.text,
      );
      if (r.ok) {
        _cerrarAlumno();
        await _cargar();
      } else if (r.motivo == 'otro') {
        _cerrarAlumno();
        await _cargar();
        _errorBarra = 'A ese alumno ya lo cargó ${r.cargo ?? 'otro delegado'}.';
      } else if (_porQueNo.containsKey(r.motivo)) {
        _errorForm = _porQueNo[r.motivo];
      } else {
        // El link venció, se apagó, o este celular ya envió: se muestra cómo
        // quedó.
        _cerrarAlumno();
        await _cargar();
      }
    } catch (_) {
      _errorForm = 'No se pudo guardar. Revisá tu internet y probá de nuevo: '
          'lo que escribiste sigue acá.';
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ── Enviar ────────────────────────────────────────────────────────────────

  Future<void> _quiereEnviar() async {
    if (_ocupado) return;
    final lista = _lista;
    if (lista == null) return;
    if (_abierto != null && _sucio) {
      final a = lista.alumnos.where((x) => x.id == _abierto).firstOrNull;
      setState(() => _errorBarra =
          'Tenés cambios sin guardar en ${a?.nombre ?? 'un alumno'}. '
          'Guardalos o descartalos antes de enviar.');
      return;
    }
    setState(() => _errorBarra = null);
    // Los números del aviso, recién leídos: otro delegado pudo cargar recién.
    await _cargar();
    final ahora = _lista;
    if (!mounted || ahora == null || !ahora.ok || ahora.soloLectura) return;
    if (ahora.mios == 0) {
      setState(() => _errorBarra = 'Todavía no guardaste ningún alumno.');
      return;
    }
    final confirmo = await showDialog<bool>(
      context: context,
      builder: (context) => _AvisoDeEnviar(faltan: ahora.faltan),
    );
    if (confirmo != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await widget.nube.entregar(widget.clave, _sesion ?? '');
      await _cargar();
      if (mounted && _lista?.yoEntregado != true) {
        _errorBarra = 'No se pudo enviar. Probá de nuevo.';
      } else if (mounted) {
        _arriba();
      }
    } catch (_) {
      _errorBarra = 'No se pudo enviar. Revisá tu internet y probá de nuevo.';
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Lleva la lista arriba de todo: ahí está el agradecimiento.
  ///
  /// Recién cuando la pantalla ya se acomodó, y otra vez en el cuadro que
  /// sigue: al aparecer el agradecimiento arriba de lo que se estaba mirando,
  /// la lista corrige sola su posición, y un salto dado antes quedaba corrido
  /// justo el alto de lo nuevo (se vio en la prueba de punta a punta).
  void _arriba([int veces = 2]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(0);
      if (veces > 1) _arriba(veces - 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  // ── Pantallas ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
    final adentro = lista != null && lista.ok;
    return Scaffold(
      backgroundColor: _fondo,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: lista == null
                ? (_sinRed
                    ? _mensaje(
                        'No pudimos conectarnos',
                        'Revisá tu internet y volvé a intentar.',
                        reintentar: true,
                      )
                    : const Center(child: CircularProgressIndicator()))
                : adentro
                    ? _laLista(lista)
                    : _afuera(lista),
          ),
        ),
      ),
      bottomNavigationBar:
          adentro && !lista.soloLectura ? _barraDeEnviar() : null,
    );
  }

  Widget _marca([String extra = '']) => Text(
        'JUNIOR EVENTOS$extra',
        style: const TextStyle(fontSize: 13, color: _suave, letterSpacing: 0.6),
      );

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: _tinta,
          ),
        ),
      );

  Widget _tarjeta(List<Widget> hijos) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _linea),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: hijos,
        ),
      );

  Widget _cinta(String texto, {Key? key}) => Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _avisoFondo,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 15, color: _avisoTinta),
        ),
      );

  Widget _error(String? texto, {Key? key, TextAlign? align}) => texto == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            texto,
            key: key,
            textAlign: align,
            style: const TextStyle(fontSize: 14, color: _rojo),
          ),
        );

  Widget _mensaje(String titulo, String texto, {bool reintentar = false}) =>
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _marca(),
          const SizedBox(height: 12),
          _tarjeta([
            Text(
              titulo,
              key: const Key('delegado_mensaje'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _tinta,
              ),
            ),
            const SizedBox(height: 6),
            Text(texto, style: const TextStyle(fontSize: 15, color: _suave)),
            if (reintentar) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ]),
        ],
      );

  Widget _afuera(ListaDelDelegado l) => switch (l.motivo) {
        'entrar' => _laEntrada(l),
        'apagado' => _mensaje(
            'Este link está cerrado',
            'Por ahora no se puede cargar. Cualquier duda, escribile a Junior '
                'Eventos.',
          ),
        'sacado' => _mensaje(
            'Este celular ya no puede cargar',
            'Si te parece un error, avisale a Junior Eventos.',
          ),
        _ => _mensaje(
            'Este link no es válido',
            'Pedile el link de nuevo a Junior Eventos.',
          ),
      };

  Widget _laEntrada(ListaDelDelegado l) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _marca(' · ACOMPAÑANTES Y MÚSICA'),
          _titulo(l.fiesta),
          const SizedBox(height: 14),
          if (l.vencido)
            _tarjeta([
              Text(
                'El plazo para cargar terminó el ${l.venceTexto}.',
                key: const Key('delegado_mensaje'),
                style: const TextStyle(fontSize: 17, color: _tinta),
              ),
              const SizedBox(height: 6),
              const Text(
                'Si necesitás más tiempo, escribile a Junior Eventos.',
                style: TextStyle(fontSize: 15, color: _suave),
              ),
            ])
          else if (l.lleno)
            _tarjeta(const [
              Text(
                'Ya entraron todos los delegados que esperábamos para esta '
                'fiesta.',
                key: Key('delegado_mensaje'),
                style: TextStyle(fontSize: 17, color: _tinta),
              ),
              SizedBox(height: 6),
              Text(
                'Si te falta entrar a vos, avisale a Junior Eventos.',
                style: TextStyle(fontSize: 15, color: _suave),
              ),
            ])
          else ...[
            _cinta('Hay tiempo hasta el ${l.venceTexto}.'),
            const SizedBox(height: 14),
            _tarjeta([
              Text(
                '¿Sos delegado de ${l.fiesta}?',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _tinta,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Si no lo sos, cerrá esta página: esta lista no es para vos.',
                style: TextStyle(fontSize: 15, color: _suave),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu nombre y apellido',
                style: TextStyle(fontWeight: FontWeight.w700, color: _tinta),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('delegado_nombre'),
                controller: _nombre,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _entrar(),
                decoration: _casillero('Nombre y apellido'),
              ),
              _error(_errorEntrada, key: const Key('delegado_error_entrada')),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('delegado_entrar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _azul,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _ocupado ? null : _entrar,
                  child: const Text('Soy delegado, entrar'),
                ),
              ),
            ]),
          ],
        ],
      );

  InputDecoration _casillero(String pista, {bool contador = false}) =>
      InputDecoration(
        hintText: pista,
        counterText: contador ? null : '',
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _linea),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _linea),
        ),
      );

  Widget _laLista(ListaDelDelegado l) {
    final q = _sinAcentos(_buscar.text.trim());
    final visibles = [
      for (final a in l.alumnos)
        if (q.isEmpty || _sinAcentos(a.nombre).contains(q)) a,
    ];
    String? division;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _marca(' · ACOMPAÑANTES Y MÚSICA'),
        _titulo(l.fiesta),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Text(
            'Hola, ${l.yoNombre}.',
            style: const TextStyle(fontSize: 15, color: _suave),
          ),
        ),
        if (l.yoEntregado) ...[
          Container(
            key: const Key('delegado_gracias'),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _okFondo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¡Listo, muchas gracias!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _okTinta,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Recibimos tu parte de ${l.fiesta}. Si necesitás corregir '
                  'algo, escribinos.',
                  style: const TextStyle(fontSize: 15, color: _okTinta),
                ),
                const SizedBox(height: 4),
                const Text(
                  '— Junior Eventos',
                  style: TextStyle(fontSize: 15, color: _okTinta),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Enviaste ${_cuantos(l.mios, 'alumno', 'alumnos')}. Ya no se '
              'puede cambiar.',
              style: const TextStyle(fontSize: 15, color: _suave),
            ),
          ),
        ] else if (l.vencido)
          _cinta(
            'El plazo terminó el ${l.venceTexto}. Ya no se puede cargar ni '
            'enviar.',
            key: const Key('delegado_plazo'),
          )
        else
          _cinta(
            'Tenés hasta el ${l.venceTexto}.',
            key: const Key('delegado_plazo'),
          ),
        const SizedBox(height: 14),
        Text(
          '${l.cargados} de ${l.total} alumnos cargados',
          key: const Key('delegado_avance'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _tinta,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: l.total == 0 ? 0 : l.cargados / l.total,
            minHeight: 8,
            color: _azul,
            backgroundColor: _linea,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('delegado_buscar'),
          controller: _buscar,
          onChanged: (_) => setState(() {}),
          decoration: _casillero('Buscar por apellido o nombre'),
        ),
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Ningún alumno con ese nombre. Probá con el apellido.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _suave),
            ),
          ),
        for (final a in visibles) ...[
          if (a.division != division)
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 2),
              child: Text(
                (division = a.division).isEmpty
                    ? 'SIN DIVISIÓN'
                    : a.division.toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  color: _suave,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          _elAlumno(a, l.soloLectura),
        ],
      ],
    );
  }

  Widget _chip(AlumnoDelLink a) {
    final (texto, fondo, tinta, borde) = switch (a.de) {
      DeQuien.programa => ('Ya cargado', Colors.transparent, _grisTinta, true),
      DeQuien.otro => (
          'Lo cargó ${a.cargo ?? 'otro delegado'}',
          Colors.transparent,
          _grisTinta,
          true,
        ),
      DeQuien.mio => ('Guardado', _okFondo, _okTinta, false),
      DeQuien.suelto => ('Para revisar', _faltaFondo, _faltaTinta, false),
      DeQuien.libre => ('Falta', _faltaFondo, _faltaTinta, false),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: borde ? Border.all(color: _tenue) : null,
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: tinta,
          fontWeight: borde ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
    );
  }

  Widget _elAlumno(AlumnoDelLink a, bool soloLectura) {
    final abierto = _abierto == a.id;
    final resumen = [
      if (a.acompanantes.isNotEmpty) a.acompanantes.join(' · '),
      if (a.musica.isNotEmpty) '♪ ${a.musica}',
    ].join('\n');
    final cara = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.nombre,
                  style: TextStyle(
                    fontSize: 16,
                    color: a.cerrado ? _tenue : _tinta,
                    fontWeight: a.cerrado ? FontWeight.w400 : FontWeight.w700,
                    decoration: a.cerrado ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (!a.cerrado && !abierto && resumen.isNotEmpty)
                  Text(
                    resumen,
                    style: const TextStyle(fontSize: 13, color: _suave),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _chip(a),
        ],
      ),
    );
    return Container(
      key: Key('delegado_alumno_${a.id}'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: a.cerrado ? _grisFondo : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: a.cerrado ? _grisFondo : _linea),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Lo cerrado no se toca: no es un botón.
          if (a.cerrado || soloLectura)
            cara
          else
            InkWell(
              key: Key('delegado_abrir_${a.id}'),
              onTap: () => _tocar(a),
              child: cara,
            ),
          if (abierto && !a.cerrado && !soloLectura) _elFormulario(a),
        ],
      ),
    );
  }

  Widget _fijo(String texto) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _grisFondo,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 14, color: _grisTinta),
        ),
      );

  Widget _elFormulario(AlumnoDelLink a) => Container(
        decoration:
            const BoxDecoration(border: Border(top: BorderSide(color: _linea))),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text.rich(
              TextSpan(
                text: 'Acompañantes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _tinta,
                ),
                children: [
                  TextSpan(
                    text: ' · hasta $kMaxAcompanantes, uno por casillero',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: _suave,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (a.progAcomp)
              _fijo('Ya están cargados en el programa.')
            else
              // Dos casilleros, ni uno más: no hay botón para agregar.
              for (final (i, c) in [_ac1, _ac2].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: Key('delegado_ac${i + 1}'),
                    controller: c,
                    maxLength: kMaxLetrasAcompananteDelegado,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => _escribio(),
                    decoration: _casillero('Apellido, nombre'),
                  ),
                ),
            const SizedBox(height: 4),
            const Text(
              'Música',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _tinta,
              ),
            ),
            const SizedBox(height: 6),
            if (a.progMusica)
              _fijo('Ya está cargada en el programa.')
            else
              TextField(
                key: const Key('delegado_musica'),
                controller: _musica,
                maxLength: kMaxLetrasMusicaDelegado,
                minLines: 3,
                maxLines: 5,
                onChanged: (_) => _escribio(),
                decoration: _casillero(
                  'Tema y artista, y todo el detalle que haga falta: versión, '
                  'desde qué minuto, un link…',
                  contador: true,
                ),
              ),
            _error(_errorForm, key: const Key('delegado_error_alumno')),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('delegado_guardar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _azul,
                      side: const BorderSide(color: _azul, width: 2),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _ocupado ? null : () => _guardar(a),
                    child: const Text(
                      'Guardar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('delegado_descartar'),
                  onPressed: _ocupado
                      ? null
                      : () => setState(() {
                            _cerrarAlumno();
                            _errorBarra = null;
                          }),
                  child: const Text(
                    'Descartar',
                    style: TextStyle(
                      color: _suave,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _barraDeEnviar() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _linea)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _error(
                      _errorBarra,
                      key: const Key('delegado_error_barra'),
                      align: TextAlign.center,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Guardar no envía. Cuando termines, tocá Enviar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: _suave),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('delegado_enviar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _verde,
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _ocupado ? null : _quiereEnviar,
                        child: const Text(
                          'Enviar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// El aviso de Enviar: una última revisión, con una casilla. Devuelve `true`
/// solo si tildó y confirmó.
class _AvisoDeEnviar extends StatefulWidget {
  final int faltan;
  const _AvisoDeEnviar({required this.faltan});

  @override
  State<_AvisoDeEnviar> createState() => _AvisoDeEnviarState();
}

class _AvisoDeEnviarState extends State<_AvisoDeEnviar> {
  bool _soy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final n = widget.faltan;
    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      title: const Text(
        'Antes de enviar, una última revisión',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 448,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gracias por completar la lista. Te pedimos que la revises con '
                'calma: con estos datos organizamos la entrada de cada alumno. '
                'El envío se hace una sola vez y, una vez confirmado, no se '
                'puede modificar.',
                style: TextStyle(fontSize: 15, color: _tinta),
              ),
              if (n > 0)
                Container(
                  key: const Key('delegado_faltan'),
                  margin: const EdgeInsets.only(top: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _faltaFondo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    n == 1
                        ? 'Todavía hay 1 alumno de la fiesta sin completar. Si '
                            'le toca a otro delegado, podés enviar igual.'
                        : 'Todavía hay $n alumnos de la fiesta sin completar. '
                            'Si les tocan a otro delegado, podés enviar igual.',
                    style: const TextStyle(fontSize: 15, color: _faltaTinta),
                  ),
                ),
              CheckboxListTile(
                key: const Key('delegado_soy'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _soy,
                onChanged: (v) => setState(() {
                  _soy = v == true;
                  _error = null;
                }),
                title: const Text(
                  'Soy delegado de esta fiesta y revisé lo que cargué.',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('delegado_error_aviso'),
                  style: const TextStyle(fontSize: 14, color: _rojo),
                ),
              const SizedBox(height: 14),
              // A todo el ancho y uno debajo del otro: en un celular, dos
              // botones lado a lado quedaban disparejos.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('delegado_seguir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _tinta,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Seguir revisando'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('delegado_confirmar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _verde,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () {
                    if (!_soy) {
                      setState(
                        () => _error = 'Tildá la casilla para confirmar.',
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text(
                    'Confirmar envío',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
