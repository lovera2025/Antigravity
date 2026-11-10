import '../../../core/utils/uuid_utils.dart';
import '../../../models/plano_evento.dart';
import '../../plano/modelo/reserva_de_mesa.dart';

/// Quien se sienta en una mesa reservada del plano, para la puerta (6.5.0).
///
/// El 10-nov-2026 el usuario pidió que los profesores (la mesa que les regala
/// la empresa, `ReservaDeMesa`) aparezcan en el buscador de Recepción y que el
/// tótem los salude con su mesa encendida, "igual que los alumnos". No son
/// alumnos: no tienen contrato, pagos, entradas ni sillas de la noche. Salen
/// del plano de la fiesta, de las mesas libres que dicen para quién son y
/// quiénes se sientan.
class ReservadoPuerta {
  /// El id de su fila en la lista de la puerta ([idInvitadoReserva]): fijo,
  /// exista o no la fila. La fila se crea al marcar su ingreso.
  final String id;
  final String nombre;
  final int mesa;

  /// Para quién es la mesa ("Profes"): la distinción que lleva al lado.
  final String para;

  const ReservadoPuerta({
    required this.id,
    required this.nombre,
    required this.mesa,
    required this.para,
  });
}

/// El id fijo de la fila de la puerta de quien se sienta en una mesa
/// reservada. Sale de la fiesta, la mesa y el nombre (sin mayúsculas, acentos
/// ni espacios de más): corregir una letra del nombre es otra persona, y quien
/// ya había entrado con el nombre viejo queda en la lista como cargado a mano
/// (no se esconde a nadie).
String idInvitadoReserva(String eventoId, int mesa, String nombre) =>
    UuidUtils.lineaIdDeterministic(
      'puerta-reserva',
      eventoId,
      _clave(nombre),
      mesa,
    );

String _clave(String nombre) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sin = 'aaaaaeeeeiiiiooooouuuun';
  final b = StringBuffer();
  for (final r in nombre.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = con.indexOf(c);
    b.write(i < 0 ? c : sin[i]);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

/// Quiénes se sientan en las mesas reservadas de [plano], por mesa y en el
/// orden en que se cargaron. Solo las reservadas con nombres: una mesa "para
/// los profes" sin la lista no pone a nadie en la puerta. Una mesa que el
/// armado ya no tiene, tampoco. Un nombre repetido en la misma mesa va una vez.
List<ReservadoPuerta> reservadosDeLaPuerta(String eventoId, PlanoEvento? plano) {
  final armado = plano?.armadoONull;
  if (plano == null || armado == null) return const [];
  final mesas = plano.config.libres.keys.toList()..sort();
  final out = <ReservadoPuerta>[];
  for (final mesa in mesas) {
    if (!armado.existe(mesa)) continue;
    final reserva = ReservaDeMesa.deMotivo(plano.config.libres[mesa]?.motivo);
    if (reserva == null) continue;
    final vistos = <String>{};
    for (final nombre in reserva.quienes) {
      final clave = _clave(nombre);
      if (clave.isEmpty || !vistos.add(clave)) continue;
      out.add(
        ReservadoPuerta(
          id: idInvitadoReserva(eventoId, mesa, nombre),
          nombre: nombre,
          mesa: mesa,
          para: reserva.para,
        ),
      );
    }
  }
  return out;
}
