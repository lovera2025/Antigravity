/// Operador sintético para cobros hechos en modo jefe (no es login de caja).
const String kOperadorModoJefeId = '00000000-0000-4000-8000-cafemodojefe01';

const String kOperadorModoJefeNombre = 'Modo jefe';

/// Etiqueta de sesión única del día (sin corte Mañana/Tarde).
const String kEtiquetaModoJefe = 'Modo jefe';

/// PIN no numérico: el role gate solo pide dígitos, así no se puede entrar como caja.
const String kOperadorModoJefePin = 'modo-jefe-sistema-no-login';

bool esOperadorModoJefeId(String? operadorId) =>
    operadorId != null && operadorId == kOperadorModoJefeId;
