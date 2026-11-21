import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/entradas_retiro.dart' show TramoTalonario;
import '../../barra/cuentas/pesos.dart';
import '../../common/utils/cortes_pantalla.dart';
import '../../common/utils/texto_busqueda.dart';
import '../cuentas/para_rendir.dart';
import '../datos/entradas_repositorio.dart';
import 'para_rendir_comun.dart';

/// Lo que eligió el jefe en DAR ENTRADAS PARA RENDIR: a quién, cuántas, qué
/// números y a qué precio (el de hoy, que queda fijo).
class PedidoDeDarParaRendir {
  final String personaNombre;
  final String? personaContacto;

  /// Si es un alumno de la fiesta. Solo para mostrar y agrupar: lo que rinda
  /// **nunca** va a su familia.
  final String? contratoAlumnoId;
  final int cantidad;
  final List<TramoTalonario> numeros;
  final double precio;
  final String nombrePrecio;
  final String? nota;

  const PedidoDeDarParaRendir({
    required this.personaNombre,
    required this.personaContacto,
    required this.contratoAlumnoId,
    required this.cantidad,
    required this.numeros,
    required this.precio,
    required this.nombrePrecio,
    required this.nota,
  });
}

/// DAR ENTRADAS PARA RENDIR (21-nov-2026, sección 5 de la SPEC): **un alumno de
/// la fiesta** (se elige de la lista: el nombre viene del alumno) **o alguien
/// de afuera** (nombre y apellido escritos, y un contacto si se quiere); la
/// cantidad y los números del talonario, **obligatorios**; el precio de hoy, a
/// la vista y sin poder cambiarlo; y una nota. Se confirma antes de dar.
///
/// **Solo las entradas, sin pulseras**: la pulsera no se vende (lo aclaró el
/// usuario el 20-nov), así que no hay nada que tildar.
///
/// **No escribe nada**: devuelve lo elegido (o null si se canceló) y PARA
/// RENDIR guarda, con la llave del modo jefe (`_dar`). Qué falta para poder
/// dar lo dice `ParaRendir.errorAlDar`; el precio, `ParaRendir.precioParaDar`.
///
/// [alumnos]: los de la fiesta sin baja. [cuenta]: lo de la fiesta, para no
/// dar un número vendido o que ya tiene otro. En la PC es una ventana al
/// centro; en el celular, una hoja desde abajo.
Future<PedidoDeDarParaRendir?> mostrarDarParaRendir(
  BuildContext context, {
  required ParaRendir cuenta,
  required List<ContratoAlumno> alumnos,
  required ConfigEntradas? config,
  required DateTime hoyAr,
}) {
  final hoja = DarParaRendirHoja(
    cuenta: cuenta,
    alumnos: alumnos,
    config: config,
    hoyAr: hoyAr,
  );
  if (CortesPantalla.esCelular(MediaQuery.sizeOf(context).width)) {
    return showModalBottomSheet<PedidoDeDarParaRendir>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => hoja,
    );
  }
  return showDialog<PedidoDeDarParaRendir>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: hoja),
    ),
  );
}

class DarParaRendirHoja extends StatefulWidget {
  const DarParaRendirHoja({
    super.key,
    required this.cuenta,
    required this.alumnos,
    required this.config,
    required this.hoyAr,
  });

  final ParaRendir cuenta;
  final List<ContratoAlumno> alumnos;
  final ConfigEntradas? config;
  final DateTime hoyAr;

  @override
  State<DarParaRendirHoja> createState() => _DarParaRendirHojaState();
}

class _DarParaRendirHojaState extends State<DarParaRendirHoja> {
  /// Como en la maqueta: viene en "Alguien de afuera".
  bool _deAfuera = true;
  ContratoAlumno? _alumno;
  final _buscar = TextEditingController();
  final _nombre = TextEditingController();
  final _contacto = TextEditingController();
  final _cuantas = TextEditingController(text: '20');
  final _del = TextEditingController();
  final _al = TextEditingController();
  final _del2 = TextEditingController();
  final _nota = TextEditingController();
  bool _dosTramos = false;

  @override
  void dispose() {
    for (final c in [_buscar, _nombre, _contacto, _cuantas, _del, _al, _del2, _nota]) {
      c.dispose();
    }
    super.dispose();
  }

  ({double precio, String nombre})? get _precio =>
      ParaRendir.precioParaDar(widget.config, widget.hoyAr);

  int get _cantidad => int.tryParse(_cuantas.text.trim()) ?? 0;

  /// El nombre como se guarda: el del alumno, o el escrito, en mayúsculas y sin
  /// espacios de más ("PÉREZ, JUAN").
  String get _persona => _deAfuera
      ? _nombre.text.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase()
      : (_alumno?.nombreAlumno.trim() ?? '');

  /// Los números escritos. Con un solo tramo, el "al" sale solo.
  List<TramoTalonario> get _tramos {
    final cantidad = _cantidad;
    final del = int.tryParse(_del.text.trim());
    if (del == null || cantidad < 1) return const [];
    if (!_dosTramos) return [TramoTalonario(del, del + cantidad - 1)];
    final al = int.tryParse(_al.text.trim());
    if (al == null) return [TramoTalonario(del, del)];
    final primero = TramoTalonario(del, al);
    final resto = cantidad - primero.cantidad;
    final del2 = int.tryParse(_del2.text.trim());
    if (del2 == null || resto < 1) return [primero];
    return [primero, TramoTalonario(del2, del2 + resto - 1)];
  }

  String? get _error => ParaRendir.errorAlDar(
        config: widget.config,
        hoyAr: widget.hoyAr,
        deAfuera: _deAfuera,
        contratoAlumnoId: _alumno?.id,
        personaNombre: _persona,
        cantidad: _cantidad,
        tramos: _tramos,
        ocupados: widget.cuenta.ocupados,
      );

  void _sumar(int n) {
    final nueva = (_cantidad + n).clamp(1, 9999);
    setState(() => _cuantas.text = '$nueva');
  }

  Future<void> _confirmar() async {
    final precio = _precio;
    if (_error != null || precio == null) return;
    final cantidad = _cantidad;
    final tramos = _tramos;
    final nombre = nombreDelPrecioParaRendir(precio.nombre).toLowerCase();
    final entradas = cantidad == 1 ? '1 entrada' : '$cantidad entradas';
    final si = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Dar $entradas?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'A '),
                    TextSpan(
                      text: _persona,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: ', del ${TramoTalonario.legible(tramos)}, a '
                          '${pesos(precio.precio)} cada una ($nombre, queda fijo).',
                    ),
                  ],
                ),
                key: const Key('dar_confirmar_texto'),
              ),
              const SizedBox(height: 8),
              Text(
                'Si las vende todas, rinde ${pesos(precio.precio * cantidad)}. Las que '
                'no venda, las devuelve. Sin pulseras.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('dar_confirmar_volver'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('VOLVER'),
          ),
          FilledButton(
            key: const Key('dar_confirmar_si'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('DAR ${entradas.toUpperCase()}'),
          ),
        ],
      ),
    );
    if (si != true || !mounted) return;
    // Lo vacío va en null, nunca en '' (el modelo también lo cuida).
    String? oNull(String s) => s.trim().isEmpty ? null : s.trim();
    Navigator.of(context).pop(PedidoDeDarParaRendir(
      personaNombre: _persona,
      personaContacto: _deAfuera ? oNull(_contacto.text) : null,
      contratoAlumnoId: _deAfuera ? null : _alumno?.id,
      cantidad: cantidad,
      numeros: tramos,
      precio: precio.precio,
      nombrePrecio: precio.nombre,
      nota: oNull(_nota.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final cantidad = _cantidad;
    // Mientras falta a quién es una guía, no un error.
    final sinQuien = _deAfuera ? _nombre.text.trim().isEmpty : _alumno == null;
    final colorError =
        sinQuien ? Colors.grey.shade700 : Theme.of(context).colorScheme.error;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          key: const Key('dar_hoja'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Dar entradas para rendir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                key: const Key('dar_a_quien'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Un alumno de la fiesta')),
                  ButtonSegment(value: true, label: Text('Alguien de afuera')),
                ],
                selected: {_deAfuera},
                onSelectionChanged: (s) => setState(() => _deAfuera = s.first),
              ),
            ),
            const SizedBox(height: 12),
            ...(_deAfuera ? _deAfueraCampos() : _alumnoCampos()),
            const SizedBox(height: 14),
            _rotulo('Cuántas'),
            Row(
              children: [
                IconButton(
                  key: const Key('dar_cuantas_menos'),
                  tooltip: 'Una menos',
                  onPressed: cantidad <= 1 ? null : () => _sumar(-1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                // Con el relleno del tema, en 64 px "20" se veía "2" (muestras
                // del 21-nov-2026).
                SizedBox(
                  width: 84,
                  child: TextField(
                    key: const Key('dar_cuantas'),
                    controller: _cuantas,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  key: const Key('dar_cuantas_mas'),
                  tooltip: 'Una más',
                  onPressed: () => _sumar(1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _rotulo('Números del talonario (obligatorios)'),
            _numeros(),
            const SizedBox(height: 14),
            _elPrecio(),
            const SizedBox(height: 6),
            Text(
              'Se lleva solo las entradas: sin pulseras. Rinde toda la plata.',
              key: const Key('dar_sin_pulseras'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('dar_nota'),
              controller: _nota,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: 12),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error,
                  key: const Key('dar_error'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colorError,
                  ),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('dar_cancelar'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CANCELAR'),
                ),
                FilledButton(
                  key: const Key('dar_dar'),
                  onPressed: error == null ? _confirmar : null,
                  child: Text(
                    cantidad == 1
                        ? 'DAR 1 ENTRADA'
                        : (cantidad < 1 ? 'DAR ENTRADAS' : 'DAR $cantidad ENTRADAS'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rotulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      );

  List<Widget> _deAfueraCampos() => [
        LayoutBuilder(
          builder: (context, caja) {
            final nombre = TextField(
              key: const Key('dar_nombre'),
              controller: _nombre,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nombre y apellido de quien se las lleva',
                hintText: 'PÉREZ, JUAN',
              ),
              onChanged: (_) => setState(() {}),
            );
            final contacto = TextField(
              key: const Key('dar_contacto'),
              controller: _contacto,
              // El rótulo largo se cortaba al lado del nombre: va corto, y lo
              // que se pide, como ayuda.
              decoration: const InputDecoration(
                labelText: 'Contacto (opcional)',
                hintText: 'Teléfono o DNI',
              ),
            );
            if (caja.maxWidth < 460) {
              return Column(children: [nombre, const SizedBox(height: 8), contacto]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: nombre),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: contacto),
              ],
            );
          },
        ),
      ];

  List<Widget> _alumnoCampos() {
    final elegido = _alumno;
    if (elegido != null) {
      final verde = Colors.green.shade700;
      final division = (elegido.cursoDivision ?? '').trim();
      return [
        Container(
          key: const Key('dar_alumno_elegido'),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            color: verde.withValues(alpha: 0.10),
            border: Border.all(color: verde.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  division.isEmpty
                      ? elegido.nombreAlumno.trim()
                      : '${elegido.nombreAlumno.trim()} · $division',
                  style: TextStyle(fontWeight: FontWeight.w700, color: verde),
                ),
              ),
              TextButton(
                key: const Key('dar_alumno_cambiar'),
                onPressed: () => setState(() => _alumno = null),
                child: const Text('CAMBIAR'),
              ),
            ],
          ),
        ),
      ];
    }
    final q = _buscar.text.trim();
    final encontrados = q.length < 2
        ? const <ContratoAlumno>[]
        : [
            for (final a in widget.alumnos)
              if (coincideTextoBusqueda([a.nombreAlumno], q)) a,
          ];
    return [
      TextField(
        key: const Key('dar_buscar_alumno'),
        controller: _buscar,
        decoration: const InputDecoration(
          labelText: 'Buscar alumno de la fiesta',
          hintText: 'Escribí el apellido',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 6),
      if (q.length >= 2 && encontrados.isEmpty)
        Text(
          'Ningún alumno de la fiesta con ese nombre.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
      if (encontrados.isNotEmpty)
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, a) in encontrados.take(8).indexed) ...[
                if (i > 0) const Divider(height: 1),
                InkWell(
                  key: Key('dar_alumno_${a.id}'),
                  onTap: () => setState(() {
                    _alumno = a;
                    _buscar.text = a.nombreAlumno.trim();
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: a.nombreAlumno.trim()),
                          if ((a.cursoDivision ?? '').trim().isNotEmpty)
                            TextSpan(
                              text: ' · ${a.cursoDivision!.trim()}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _numeros() {
    Widget campo(String clave, TextEditingController c, String rotulo) => SizedBox(
          width: 110,
          child: TextField(
            key: Key(clave),
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: rotulo, isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        );
    final tramos = _tramos;
    final ultimo = tramos.isEmpty ? null : tramos.last;
    final al = Text(
      ultimo == null || (_dosTramos && tramos.length < 2) ? 'al …' : 'al ${ultimo.hasta}',
      key: const Key('dar_al_calculado'),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        campo('dar_del', _del, 'Del'),
        if (!_dosTramos) al,
        if (_dosTramos) ...[
          campo('dar_al', _al, 'Al'),
          campo('dar_del_2', _del2, 'Del'),
          al,
        ],
        TextButton(
          key: const Key('dar_dos_tramos'),
          onPressed: () => setState(() {
            _dosTramos = !_dosTramos;
            _al.clear();
            _del2.clear();
          }),
          child: Text(_dosTramos ? 'Un solo tramo' : 'El talonario salta: dos tramos'),
        ),
      ],
    );
  }

  /// El precio de hoy, fijo: "A $ 8.000 cada una · Entrada anticipada · el
  /// precio de hoy (PRECIOS), queda fijo".
  Widget _elPrecio() {
    final precio = _precio;
    const oro = Color(0xFF6D5A10);
    return Container(
      key: const Key('dar_precio'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x26D4AF37),
        border: Border.all(color: const Color(0xB3D4AF37)),
        borderRadius: BorderRadius.circular(10),
      ),
      // Sin precio, al jefe (DAR es suyo) se le dice dónde cargarlo.
      child: precio == null
          ? const Text(
              ParaRendir.kSinPrecioParaDar,
              style: TextStyle(fontWeight: FontWeight.w700, color: oro),
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'A ${pesos(precio.precio)} cada una · '
                        '${nombreDelPrecioParaRendir(precio.nombre)} · el precio de hoy '
                        '(PRECIOS), ',
                  ),
                  const TextSpan(
                    text: 'queda fijo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              key: const Key('dar_precio_texto'),
              style: const TextStyle(fontWeight: FontWeight.w600, color: oro),
            ),
    );
  }
}
