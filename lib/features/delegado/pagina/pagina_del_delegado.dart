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
/// - **Enviar**, uno solo y abajo, le avisa a la empresa. **No cierra nada**
///   (6.9.2): se sigue corrigiendo hasta la fecha límite y se puede enviar de
///   nuevo.
/// - **Todos corrigen todo** (6.9.2): lo que cargó otro delegado y lo que ya
///   está en el programa se abren igual, con un aviso antes de dejar escribir.
/// - **Desde otro celular** se entra tocando el nombre con el que ya se entró.
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

  /// Ya dijo "sí, corregir" en el aviso de este alumno (lo cargó otro, o ya
  /// está en el programa).
  bool _confirmoCorregir = false;

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
    _confirmoCorregir = false;
    _errorForm = null;
  }

  // ── Entrar ────────────────────────────────────────────────────────────────

  /// Entra con lo escrito o, si viene [nombre], con el nombre que tocó: quien
  /// ya entró desde otro celular sigue con lo suyo.
  Future<void> _entrar([String? nombre]) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _errorEntrada = null;
    });
    try {
      final r = await widget.nube.entrar(widget.clave, nombre ?? _nombre.text);
      if (r.ok && r.sesion != null) {
        _sesion = r.sesion;
        await widget.sesiones.guardar(widget.clave, r.sesion!);
        await _cargar();
      } else if (r.motivo == 'nombre') {
        _errorEntrada = 'Escribí tu nombre y tu apellido.';
      } else if (r.motivo == 'sacado') {
        _errorEntrada = 'Con ese nombre ya no se puede entrar. Si te parece un '
            'error, avisale a Junior Eventos.';
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
      _confirmoCorregir = false;
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
          for (final c in [_ac1, _ac2])
            if (c.text.trim().isNotEmpty) c.text.trim().toUpperCase(),
        ],
        musica: _musica.text,
      );
      if (r.ok) {
        _cerrarAlumno();
        await _cargar();
      } else if (_porQueNo.containsKey(r.motivo)) {
        _errorForm = _porQueNo[r.motivo];
      } else {
        // El link venció o se cerró, o a este delegado lo sacaron: se muestra
        // cómo quedó.
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

  /// Enviar: le avisa a la empresa. **No cierra nada** (6.9.2), así que no
  /// pregunta antes: si después corrige algo, envía de nuevo.
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
    setState(() {
      _ocupado = true;
      _errorBarra = null;
    });
    try {
      final r = await widget.nube.entregar(widget.clave, _sesion ?? '');
      await _cargar();
      if (!mounted) return;
      if (r.ok && r.ya) {
        _errorBarra = 'No tenés nada nuevo para enviar.';
      } else if (r.ok) {
        _arriba();
      } else if (r.motivo == 'nada') {
        _errorBarra = 'Todavía no guardaste ningún alumno.';
      } else if (_lista?.ok == true && _lista?.soloLectura != true) {
        _errorBarra = 'No se pudo enviar. Probá de nuevo.';
      }
    } catch (_) {
      _errorBarra = 'No se pudo enviar. Revisá tu internet y probá de nuevo.';
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Lleva la lista arriba de todo: ahí dice que se envió.
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
          adentro && !lista.soloLectura ? _barraDeEnviar(lista) : null,
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
            'Ya no podés cargar en esta fiesta',
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
            ]),
            // Quien ya entró sigue con lo suyo desde cualquier celular.
            if (l.delegados.isNotEmpty) ...[
              const SizedBox(height: 12),
              _tarjeta([
                const Text(
                  '¿Ya entraste? Tocá tu nombre',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _tinta,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Sirve desde cualquier celular: seguís con lo que ya '
                  'cargaste.',
                  style: TextStyle(fontSize: 14, color: _suave),
                ),
                for (final (i, nombre) in l.delegados.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: Key('delegado_soy_$i'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _tinta,
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(color: _linea, width: 1.5),
                        ),
                        onPressed: _ocupado ? null : () => _entrar(nombre),
                        child: Text(
                          nombre,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (l.lleno)
                  _error(_errorEntrada, key: const Key('delegado_error_entrada')),
              ]),
            ],
            const SizedBox(height: 12),
            if (l.lleno)
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
            else
              _tarjeta([
                Text(
                  l.delegados.isEmpty
                      ? 'Tu nombre y apellido'
                      : '¿Es la primera vez? Tu nombre y apellido',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _tinta,
                  ),
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
        if (l.vencido)
          _cinta(
            'El plazo terminó el ${l.venceTexto}. Ya no se puede cargar ni '
            'corregir.',
            key: const Key('delegado_plazo'),
          )
        else
          _cinta(
            'Tenés hasta el ${l.venceTexto} para cargar y corregir.',
            key: const Key('delegado_plazo'),
          ),
        // Haber enviado no cierra nada: solo se le dice que llegó.
        if (l.yoEntregado)
          Container(
            key: const Key('delegado_gracias'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _okFondo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Gracias! Recibimos tu parte'
                  '${l.yoEnvioTexto == null ? '' : ' el ${l.yoEnvioTexto}'}.',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _okTinta,
                  ),
                ),
                if (!l.vencido) ...[
                  const SizedBox(height: 4),
                  Text(
                    l.yoSinEnviar > 0
                        ? 'Después corregiste '
                            '${_cuantos(l.yoSinEnviar, 'alumno', 'alumnos')}: '
                            'tocá Enviar otra vez para avisarnos.'
                        : 'Si corregís algo, tocá Enviar otra vez para '
                            'avisarnos.',
                    style: const TextStyle(fontSize: 15, color: _okTinta),
                  ),
                ],
              ],
            ),
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

  /// A la derecha de cada alumno: si falta, si es suyo y no lo envió, o listo.
  Widget _chip(AlumnoDelLink a) {
    final (texto, fondo, tinta) = switch (a.estado) {
      EstadoDeLaCarga.falta => ('Falta', _faltaFondo, _faltaTinta),
      EstadoDeLaCarga.sinEnviar when a.de == DeQuien.mio =>
        ('Sin enviar', _avisoFondo, _avisoTinta),
      _ => ('Cargado', _okFondo, _okTinta),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 13, color: tinta, fontWeight: FontWeight.w700),
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
                  style: const TextStyle(
                    fontSize: 16,
                    color: _tinta,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Con el formulario abierto no hace falta: está en los
                // casilleros. Mientras pregunta "¿Seguir?", sí: es lo que se
                // va a cambiar.
                if ((!abierto || (a.esDeOtro && !_confirmoCorregir)) &&
                    resumen.isNotEmpty)
                  Text(
                    resumen,
                    style: const TextStyle(fontSize: 13, color: _suave),
                  ),
                // Quién lo cargó y cuándo: todos ven lo de todos.
                if (a.cargado)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      a.rotuloDeCargado,
                      key: Key('delegado_quien_${a.id}'),
                      style: const TextStyle(fontSize: 12.5, color: _grisTinta),
                    ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _linea),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Todo se puede abrir. Lo único que cierra es la fecha límite.
          if (soloLectura)
            cara
          else
            InkWell(
              key: Key('delegado_abrir_${a.id}'),
              onTap: () => _tocar(a),
              child: cara,
            ),
          if (abierto && !soloLectura)
            a.esDeOtro && !_confirmoCorregir
                ? _elAvisoDeCorregir(a)
                : _elFormulario(a),
        ],
      ),
    );
  }

  /// Antes de dejar corregir lo que cargó otro (o lo que ya está en el
  /// programa): lo dice y pregunta. Lo vigente sigue a la vista arriba, en la
  /// cara del alumno.
  Widget _elAvisoDeCorregir(AlumnoDelLink a) => Container(
        key: const Key('delegado_cartel'),
        width: double.infinity,
        decoration:
            const BoxDecoration(border: Border(top: BorderSide(color: _linea))),
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _faltaFondo,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                switch (a.de) {
                  DeQuien.otro when a.cargo != null =>
                    'Vas a cambiar lo que cargó ${a.cargo}. ¿Seguir?',
                  DeQuien.programa =>
                    'Vas a cambiar lo que ya está cargado en el programa. '
                        '¿Seguir?',
                  _ => 'Vas a cambiar lo que ya estaba cargado. ¿Seguir?',
                },
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _faltaTinta,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('delegado_no_corregir'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _tinta,
                        backgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => setState(_cerrarAlumno),
                      child: const Text('No, volver'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('delegado_si_corregir'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _azul,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: () => setState(() => _confirmoCorregir = true),
                      child: const Text('Sí, corregir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

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
            if (a.progAcomp || a.progMusica)
              _fijo(
                'Lo que ya está en el programa cambia recién cuando Junior '
                'Eventos lo acepta. Un casillero vacío no borra nada.',
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

  Widget _barraDeEnviar(ListaDelDelegado l) => Container(
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
                        'Guardar no envía. Cuando termines, tocá Enviar: no '
                        'cierra nada, podés seguir corrigiendo.',
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
                        child: Text(
                          l.yoEntregado ? 'Enviar otra vez' : 'Enviar',
                          style: const TextStyle(
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
