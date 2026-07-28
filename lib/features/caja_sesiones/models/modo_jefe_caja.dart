/// Operador sintético para cobros hechos en modo jefe (no es login de caja).
///
/// Debe ser un UUID válido de 36 chars: la cola de sync descarta ids
/// malformados y el sync engine rechaza campos `id` que no midan 36.
const String kOperadorModoJefeId = '00000000-0000-4000-8000-0000cafe0001';

/// Id inválido usado en 4.5.1 (38 chars, no-hex): nunca pudo sincronizar.
/// La migración v66 lo convierte a [kOperadorModoJefeId]; se mantiene acá
/// solo para reconocer datos aún no migrados.
const String kOperadorModoJefeIdLegacy = '00000000-0000-4000-8000-cafemodojefe01';

const String kOperadorModoJefeNombre = 'Modo jefe';

/// Etiqueta de sesión única del día (sin corte Mañana/Tarde).
const String kEtiquetaModoJefe = 'Modo jefe';

/// PIN no numérico: el role gate solo pide dígitos, así no se puede entrar como caja.
const String kOperadorModoJefePin = 'modo-jefe-sistema-no-login';

bool esOperadorModoJefeId(String? operadorId) =>
    operadorId != null &&
    (operadorId == kOperadorModoJefeId ||
        operadorId == kOperadorModoJefeIdLegacy);
