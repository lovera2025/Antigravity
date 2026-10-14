import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import '../common/utils/cortes_pantalla.dart';
import 'providers/recepcion_provider.dart';
import 'repositories/invitados_repository.dart';
import 'services/puerta_del_evento.dart';
import 'widgets/panel_puerta.dart';
import 'widgets/vista_del_totem.dart';

class RecepcionUnifiedScreen extends ConsumerStatefulWidget {
  const RecepcionUnifiedScreen({super.key});

  @override
  ConsumerState<RecepcionUnifiedScreen> createState() => _RecepcionUnifiedScreenState();
}

class _RecepcionUnifiedScreenState extends ConsumerState<RecepcionUnifiedScreen> {
  static const _perla = Color(0xFFE2E2E2);

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ancho = MediaQuery.sizeOf(context).width;
    final selectedEventId = ref.watch(selectedEventProvider);
    // En el celular no hay vista del tótem: la paleta va arriba.
    final paletaArriba = CortesPantalla.esCelular(ancho) &&
        selectedEventId != null &&
        ref.watch(puedePersonalizarTotemProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.door_front_door_rounded, size: 20, color: _perla),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'RECEPCIÓN UNIFICADA',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.oswald(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: _perla,
                ),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (paletaArriba)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BotonPersonalizarTotem(eventoId: selectedEventId),
            ),
        ],
      ),
      body: SafeArea(
        child: _buildLayout(ancho, isDark, selectedEventId),
      ),
    );
  }

  /// Según la pantalla (`CortesPantalla`): en la PC, la lista y la vista del
  /// tótem lado a lado; en una tablet, en pestañas; en el celular, la lista
  /// sola.
  Widget _buildLayout(double ancho, bool isDark, String? selectedEventId) {
    if (CortesPantalla.esPc(ancho)) {
      return _buildSplitViewLayout(isDark, selectedEventId);
    }
    if (!CortesPantalla.esCelular(ancho)) {
      return _buildTabsLayout(isDark, selectedEventId);
    }
    return const OperadorViewContent();
  }

  // ── PC: lado a lado ────────────────────────────────────────────────────────

  Widget _buildSplitViewLayout(bool isDark, String? selectedEventId) {
    return Row(
      children: [
        // La lista se lleva el 60 %: la vista es la pantalla del salón en
        // chico.
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
            ),
            child: const OperadorViewContent(),
          ),
        ),
        Expanded(
          flex: 2,
          child: selectedEventId != null
              ? VistaDelTotem(eventoId: selectedEventId)
              : _buildNoEventSelected(),
        ),
      ],
    );
  }

  // ── Tablet: pestañas ───────────────────────────────────────────────────────

  Widget _buildTabsLayout(bool isDark, String? selectedEventId) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: 'RECEPCIÓN',
                  icon: Icons.door_front_door_rounded,
                  isSelected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _TabButton(
                  label: 'TÓTEM',
                  icon: Icons.tv_rounded,
                  isSelected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ),
            ],
          ),
        ),
        // La vista corre solo mientras su pestaña está abierta. Al volver, su
        // primera lectura va en silencio: los que entraron ya están en la
        // lista.
        Expanded(
          child: _selectedTab == 0
              ? const OperadorViewContent()
              : (selectedEventId != null
                  ? VistaDelTotem(eventoId: selectedEventId)
                  : _buildNoEventSelected()),
        ),
      ],
    );
  }

  Widget _buildNoEventSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_rounded,
            size: 80,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'Seleccioná un evento para comenzar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Button ─────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const perla = Color(0xFFE2E2E2);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? perla : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? perla : Colors.white38,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.oswald(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: isSelected ? perla : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── OperadorViewContent (sin AppBar) ───────────────────────────────────────

class OperadorViewContent extends ConsumerStatefulWidget {
  const OperadorViewContent({super.key});

  @override
  ConsumerState<OperadorViewContent> createState() => _OperadorViewContentState();
}

class _OperadorViewContentState extends ConsumerState<OperadorViewContent> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const perla = Color(0xFFE2E2E2);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Column(
      children: [
        _buildEventSelector(isDark, perla),
        if (selectedEventId != null)
          // Con la clave del evento, cambiar de evento arranca la búsqueda y
          // los filtros de cero.
          Expanded(
            child: PanelPuerta(
              key: ValueKey(selectedEventId),
              eventoId: selectedEventId,
              onActualizar: () => _refreshList(selectedEventId),
              onAgregar: () => _agregarInvitado(selectedEventId),
              onImportar: () => _importarArchivo(selectedEventId),
              onExportar: () => _exportarExcel(selectedEventId),
              onVaciar: () => _confirmarVaciarLista(selectedEventId, context),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 80,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Seleccioná un evento para comenzar',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEventSelector(bool isDark, Color gold) {
    final eventosAsync = ref.watch(eventosActivosProvider);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.01) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: eventosAsync.when(
        data: (eventos) {
          if (eventos.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No hay eventos activos disponibles',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }

          return DropdownButtonFormField<String>(
            key: ValueKey(selectedEventId),
            initialValue: selectedEventId,
            hint: Text(
              'Seleccionar evento activo...',
              style: GoogleFonts.outfit(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38),
            ),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: gold),
            dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.event_available_rounded, color: gold, size: 20),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.01),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: gold, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: eventos.map((evento) {
              // Con el tipo: Recepción muestra distinto un particular y un
              // masivo.
              final label = etiquetaEventoRecepcion(evento);

              return DropdownMenuItem<String>(
                value: evento.id,
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.oswald(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              ref.read(selectedEventProvider.notifier).select(value);
            },
            isExpanded: true,
          );
        },
        loading: () => LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          color: gold,
        ),
        error: (error, stack) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Error al cargar eventos: ${error.toString()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Vacía la lista de invitados del evento.
  ///
  /// No pide PIN: el operador que está en Recepción ya está autorizado y
  /// pedírselo cada vez sería fricción sin sentido. En cambio la fricción es
  /// **proporcional al daño**: si todavía no ingresó nadie —el caso común de
  /// "cargué la lista equivocada"— alcanza con confirmar. Si ya entró gente, hay
  /// que escribir la palabra, porque ahí se pierde también el registro de quién
  /// llegó y a qué hora (los `accesos` se van por cascada).
  Future<void> _confirmarVaciarLista(String eventoId, BuildContext context) async {
    // De la base de la PC y no de `statsEventoProvider`: ya nadie lo mira en
    // pantalla, y leído así daba "vacía" con la lista llena.
    final stats =
        await ref.read(invitadosRepositoryProvider).getEstadisticas(eventoId);
    if (!context.mounted) return;
    final total = stats['total'] ?? 0;
    final ingresados = stats['ingresados'] ?? 0;

    if (total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La lista ya está vacía.')),
      );
      return;
    }

    final exigeEscribir = ingresados > 0;
    final escrito = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final habilitado = !exigeEscribir ||
              escrito.text.trim().toUpperCase() == 'VACIAR';

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Vaciar toda la lista',
                style: TextStyle(color: Colors.redAccent)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se van a borrar los $total invitados de este evento.',
                  style: const TextStyle(color: Colors.white),
                ),
                if (ingresados > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '$ingresados ya ingresaron. También se pierde el registro '
                    'de su entrada.',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Es irreversible.',
                  style: TextStyle(color: Colors.white54),
                ),
                if (exigeEscribir) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Escribí VACIAR para confirmar:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: escrito,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'VACIAR',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.25),
                ),
                onPressed: habilitado ? () => Navigator.pop(ctx, true) : null,
                child: const Text('VACIAR LISTA'),
              ),
            ],
          );
        },
      ),
    );

    escrito.dispose();

    if (confirmar == true) {
      try {
        final repo = ref.read(invitadosRepositoryProvider);
        // El aviso al tótem lo hace `vaciarEvento` adentro del repositorio, para
        // que valga desde cualquier pantalla y no solo desde esta.
        await repo.vaciarEvento(eventoId);

        // Invalidar para que refresque stats y lista inmediatamente en el operador
        ref.invalidate(invitadosStreamProvider(eventoId));
        ref.invalidate(statsEventoProvider(eventoId));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se eliminaron todos los invitados. Lista vacía.'), backgroundColor: Colors.redAccent),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _refreshList(String eventoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.forceRefresh(eventoId);
      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));
      // En un masivo, también los alumnos de la base de la PC.
      ref.invalidate(alumnosDeLaPuertaProvider(eventoId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lista actualizada'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Agregar invitado manual ────────────────────────────────────────────────

  Future<void> _agregarInvitado(String eventoId) async {
    final nombreCtrl = TextEditingController();
    final dniCtrl = TextEditingController();
    final mesaCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Invitado'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dniCtrl,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'DNI *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                  helperText: 'Obligatorio para la seguridad del check-in',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mesaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Mesa (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.table_restaurant),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final nombre = nombreCtrl.text.trim();
              final dni = dniCtrl.text.trim();
              if (nombre.isEmpty || dni.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Nombre y DNI son obligatorios'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.agregar(
        eventoId: eventoId,
        nombreCompleto: nombreCtrl.text.trim(),
        dni: dniCtrl.text.trim(),
        numeroMesa: mesaCtrl.text.trim().isNotEmpty ? mesaCtrl.text.trim() : null,
      );
      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitado agregado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ── Importar archivo (Excel o CSV) ─────────────────────────────────────────

  Future<void> _importarArchivo(String eventoId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt'],
        dialogTitle: 'Seleccionar archivo (Excel o CSV) de invitados',
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path!;
      final isExcel = path.toLowerCase().endsWith('.xlsx');
      final file = File(path);
      
      List<List<dynamic>> rows = [];

      if (isExcel) {
        // Lectura de Excel Nativo
        final bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        // Usar la primera hoja que contenga datos
        var sheetName = excel.tables.keys.first;
        var sheet = excel.tables[sheetName]!;
        
        for (var row in sheet.rows) {
          // Convertir celdas a strings planos
          rows.add(row.map((cell) => cell?.value?.toString().trim() ?? "").toList());
        }
      } else {
        // Lectura de CSV Tradicional
        final content = await file.readAsString(encoding: utf8);
        String delimiter = ',';
        if (content.contains(';')) delimiter = ';';
        rows = CsvDecoder(fieldDelimiter: delimiter).convert(content);
      }

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El archivo está vacío'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Detectar headers (con soporte para nombres amigables de Excel)
      final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
      final nombreIdx = headers.indexWhere((h) => h.contains('nombre'));
      final dniIdx = headers.indexWhere((h) => h.contains('dni') || h.contains('documento'));
      final mesaIdx = headers.indexWhere((h) => h.contains('mesa'));

      if (nombreIdx == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se encontró la columna "Nombre". El archivo debe tener encabezados.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Parsear filas (saltar header)
      final invitados = <Map<String, String>>[];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final nombre = nombreIdx < row.length ? row[nombreIdx].toString().trim() : '';
        if (nombre.isEmpty) continue;

        String rawDni = dniIdx != -1 && dniIdx < row.length ? row[dniIdx].toString().trim() : '';
        if (rawDni.endsWith('.0')) rawDni = rawDni.substring(0, rawDni.length - 2);

        String rawMesa = mesaIdx != -1 && mesaIdx < row.length ? row[mesaIdx].toString().trim() : '';
        if (rawMesa.endsWith('.0')) rawMesa = rawMesa.substring(0, rawMesa.length - 2);

        invitados.add({
          'nombre_completo': nombre,
          'dni': rawDni,
          'numero_mesa': rawMesa,
        });
      }

      if (invitados.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontraron invitados válidos en el CSV'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Confirmar importación
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Importación'),
          content: Text('Se importarán ${invitados.length} invitados al evento.\n\n¿Confirmar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('IMPORTAR'),
            ),
          ],
        ),
      );

      if (confirmar != true) return;

      final repo = ref.read(invitadosRepositoryProvider);
      final count = await repo.agregarBatch(eventoId: eventoId, invitados: invitados);

      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Se importaron $count invitados correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Exportar Excel ─────────────────────────────────────────────────────────

  Future<void> _exportarExcel(String eventoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      final invitados = await repo.getByEvento(eventoId);

      // Obtener nombre del evento para el nombre del archivo
      final eventosAsync = ref.read(eventosActivosProvider);
      String nombreEvento = 'plantilla';
      
      eventosAsync.whenData((list) {
        final ev = list.firstWhere((e) => e.id == eventoId);
        final cliente = ev.cliente?.nombreCompleto ?? 'Invitados';
        nombreEvento = cliente.replaceAll(' ', '_').toLowerCase();
      });

      // Crear archivo Excel usando la librería 'excel'
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];
      
      // Estilo para el encabezado (negrita)
      CellStyle headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('#D4AF37'), // Color oro elegante
        fontColorHex: ExcelColor.fromHexString('#000000'),
      );

      // Encabezados
      var headers = ['Nombre y Apellido', 'DNI (Documento)', 'Nro de Mesa / Ubicación'];
      for (var i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // Datos
      for (int i = 0; i < invitados.length; i++) {
        final inv = invitados[i];
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(inv.nombreCompleto);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(inv.dni);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue(inv.numeroMesa ?? '');
      }

      // Auto-ajustar ancho de columnas
      sheetObject.setColumnWidth(0, 30);
      sheetObject.setColumnWidth(1, 15);
      sheetObject.setColumnWidth(2, 20);

      var fileBytes = excel.save();
      
      if (!mounted) return;

      // Diálogo nativo de Windows "Guardar como"
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '¿Dónde querés guardar la lista de invitados?',
        fileName: 'Invitados_$nombreEvento.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) return; // Usuario canceló

      // Si el archivo no tiene la extensión, se la agregamos
      if (!outputFile.toLowerCase().endsWith('.xlsx')) {
        outputFile += '.xlsx';
      }

      final file = File(outputFile);
      await file.writeAsBytes(fileBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                SizedBox(width: 12),
                Text('✅ Excel guardado correctamente en tu PC'),
              ],
            ),
            backgroundColor: Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
