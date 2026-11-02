// Ventana de prueba: la pantalla del plano de verdad (Personalizar, Acomodar, los
// avisos y el botón de guardar) con el plano real de Puerto Viejo, **sin tocar la
// base de la PC ni la nube**. Guardar se queda en esta ventana y al cerrarla se
// olvida todo.
//
//   flutter run -d windows -t tool/plano_prueba.dart
//
// No corre `main.dart`: no abre la base ni inicia sesión. Los 35 alumnos son
// inventados. Arriba, una barra para sentar a las familias (y ver que con sorteo
// ningún número cambia), deshacerlo, y volver al plano mezclado.

import 'package:flutter/material.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

import '../test/helpers/salon_puerto_viejo.dart';

void main() => runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: const PruebaDelPlano(),
      ),
    );

/// Los alumnos inventados, uno por mesa. [sentados]: cada uno con su mesa.
List<ContratoAlumno> alumnosDePrueba({required bool sentados}) => [
      for (var i = 1; i <= 35; i++)
        ContratoAlumno(
          id: 'alumno-$i',
          eventoId: 'prueba',
          nombreAlumno: 'ALUMNO $i, DE PRUEBA',
          cantidadAcompanantes: 3,
          montoTotalPactado: 300000,
          saldoDeudor: 0,
          numeroMesa:
              sentados ? MesasExtraUtils.formatearAsignacionMesas([i]) : null,
          cursoDivision: '5° A',
        ),
    ];

class PruebaDelPlano extends StatefulWidget {
  const PruebaDelPlano({super.key});

  @override
  State<PruebaDelPlano> createState() => _PruebaDelPlanoState();
}

class _PruebaDelPlanoState extends State<PruebaDelPlano> {
  ArmadoSalon _armado = armadoDePuertoViejo();
  ConfigPlano _config = ConfigPlano.vacia;
  bool _sentados = false;
  bool _conInternet = true;
  AvisoDelPlano? _aviso;

  /// Lo mismo que hace la pantalla de la app al tocar GUARDAR EL SALÓN, sobre lo
  /// que hay en esta ventana.
  void _guardarSalon(
    ArmadoSalon base,
    ArmadoSalon nuevo,
    Map<int, String> enUso,
    bool rehecho,
    double? lugarBarraM,
  ) {
    final cambio = EditarArmado.paraGuardar(
      base: base,
      nuevo: nuevo,
      fresco: _armado,
      config: _config,
      alumnos: alumnosDePrueba(sentados: _sentados),
      enUsoVisto: enUso,
      rehecho: rehecho,
      leidoDeLaNube: _conInternet,
      lugarBarraM: lugarBarraM,
    );
    setState(() {
      final config = cambio.config;
      final armado = cambio.armado;
      if (config == null || armado == null) {
        _aviso = AvisoDelPlano(cambio.problema ?? 'No se puede.', esError: true);
        return;
      }
      _config = config;
      _armado = armado;
      _aviso = AvisoDelPlano(
        EditarArmado.seRenumero(nuevo, armado)
            ? 'Guardado en esta ventana, con los números en orden: '
                '${armado.cortes.length} salto.'
            : 'Guardado en esta ventana. Los números no cambiaron.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final alumnos = alumnosDePrueba(sentados: _sentados);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventana de prueba: nada se guarda de verdad'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                _armado.cortes.length == 1
                    ? '1 salto'
                    : '${_armado.cortes.length} saltos',
              ),
            ),
          ),
          const Text('Familias con mesa'),
          Switch(
            key: const Key('prueba_sentados'),
            value: _sentados,
            onChanged: (v) => setState(() {
              _sentados = v;
              _aviso = null;
            }),
          ),
          const Text('Internet'),
          Switch(
            key: const Key('prueba_internet'),
            value: _conInternet,
            onChanged: (v) => setState(() => _conInternet = v),
          ),
          TextButton(
            key: const Key('prueba_volver'),
            onPressed: () => setState(() {
              _armado = armadoDePuertoViejo();
              _config = ConfigPlano.vacia;
              _sentados = false;
              _aviso = null;
            }),
            child: const Text('VOLVER AL MEZCLADO'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PlanoEventoCuerpo(
        plano: PlanoDeLaFiesta.desde(
          armado: _armado,
          config: _config,
          alumnos: alumnos,
        ),
        estilo: EstiloPlano.arquitecto,
        alumnos: alumnos,
        aviso: _aviso,
        acciones: AccionesPlano(
          onFijarEnMesa: (_) {},
          onFijar: (_, _) {},
          onQuitarFijadas: (_) {},
          onQuitarFijadaDeMesa: (_) {},
          onDejarLibre: (_) {},
          onVolverAUsar: (_) {},
          onCambiar: (_, _) {},
          onMover: (_, _) {},
          onGuardarArmado: _guardarSalon,
        ),
      ),
    );
  }
}
