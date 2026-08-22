import '../../../models/contrato_alumno.dart';
import 'mora_cuota_calculator.dart';

/// Mora de un alumno, abierta en sus dos tipos.
///
/// Es la forma que devuelve
/// [MoraCuotaCalculator.moraPendienteOperativaDetallada]: se calcula una vez por
/// build de la grilla y la comparten el filtro, el chip, cada fila y la planilla.
typedef MoraDeAlumno = ({
  double total,
  List<MoraCuotaDetalle> desglose,
  double tracked,
});

/// Cómo se filtra la grilla de masivos por mora.
///
/// Los dos tipos van separados porque son dos cosas distintas: la de cuotas
/// vencidas impagas crece día a día, y la que quedó sin cobrar al pagar una
/// cuota está congelada en la ficha.
enum FiltroMora {
  todos('Todos', 'Sin filtro de mora'),
  conMora('Con mora', 'Deben mora de cualquier tipo'),
  soloVencida('Mora de cuotas vencidas', 'Cuotas vencidas impagas'),
  soloNoCobrada('Mora no cobrada al pagar', 'Quedó en ficha de cobros previos');

  const FiltroMora(this.label, this.ayuda);

  final String label;
  final String ayuda;

  bool get activo => this != FiltroMora.todos;
}

/// El alumno está en **baja temporal**: suspendido, con la mora congelada.
///
/// Es la única baja que sigue existiendo como fila: la definitiva borra el
/// contrato, así que esos alumnos no están en ninguna lista.
bool esBajaTemporal(ContratoAlumno a) =>
    a.nombreAlumno.trim().toUpperCase().startsWith('[BAJA]');

/// ¿Este alumno entra en [filtro]?
///
/// Las bajas temporales nunca entran: están suspendidas, su mora está congelada
/// y no se las llama para cobrar. Para la planilla se piden aparte, y quien
/// decide si salen o no es el operador.
bool cumpleFiltroMora(
  ContratoAlumno a,
  Map<String, MoraDeAlumno> mora,
  FiltroMora filtro,
) {
  if (filtro == FiltroMora.todos) return true;
  if (esBajaTemporal(a)) return false;
  final m = mora[a.id];
  if (m == null) return false;
  switch (filtro) {
    case FiltroMora.conMora:
      return m.total > 0.01;
    case FiltroMora.soloVencida:
      return moraVencidaDe(m) > 0.01;
    case FiltroMora.soloNoCobrada:
      return m.tracked > 0.01;
    case FiltroMora.todos:
      return true;
  }
}

/// Total de la mora de cuotas vencidas impagas (la que crece día a día).
double moraVencidaDe(MoraDeAlumno m) => double.parse(
  m.desglose.fold<double>(0, (s, d) => s + d.interesBruto).toStringAsFixed(2),
);
