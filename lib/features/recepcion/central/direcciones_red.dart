import 'dart:io';

/// En qué dirección encuentran los celulares a esta PC, en el wifi del
/// router del salón.
///
/// Una notebook suele tener varias: el wifi, el cable, y las que inventan los
/// programas de máquinas virtuales o de VPN, que un celular no alcanza nunca.
/// La primera de [direccionesParaCelulares] es la que va en el QR; las demás se
/// muestran por si esa no conecta.

/// Una dirección de la PC y el nombre de su conexión ("Wi-Fi", "Ethernet").
class DireccionDeLaPc {
  final String conexion;
  final String ip;
  const DireccionDeLaPc(this.conexion, this.ip);
}

/// Conexiones que un celular nunca alcanza: las de máquinas virtuales, VPN y
/// Bluetooth.
const _deMentira = [
  'vethernet',
  'virtualbox',
  'vmware',
  'hyper-v',
  'wsl',
  'docker',
  'loopback',
  'bluetooth',
  'vpn',
  'tailscale',
  'zerotier',
  'hamachi',
  'radmin',
];

bool _esDeMentira(String conexion) {
  final c = conexion.toLowerCase();
  return _deMentira.any(c.contains);
}

bool _esWifi(String conexion) {
  final c = conexion.toLowerCase();
  return c.contains('wi-fi') ||
      c.contains('wifi') ||
      c.contains('wlan') ||
      c.contains('inalámbrica') ||
      c.contains('inalambrica') ||
      c.contains('wireless');
}

/// Las de un router de casa o de salón: 192.168.x.x, 10.x.x.x y
/// 172.16 a 172.31.
bool esDireccionDeRouter(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return false;
  final n = p.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return false;
  if (n[0] == 192 && n[1] == 168) return true;
  if (n[0] == 10) return true;
  if (n[0] == 172 && n[1]! >= 16 && n[1]! <= 31) return true;
  return false;
}

/// Las direcciones que sirven, de la más probable a la menos: primero las de
/// un router, y entre ellas el wifi antes que el cable. Sin las de esta misma
/// PC (127.x), sin las que Windows se inventa cuando no hay router (169.254.x)
/// y sin las de máquinas virtuales.
List<String> direccionesParaCelulares(List<DireccionDeLaPc> todas) {
  final sirven = [
    for (final d in todas)
      if (!d.ip.startsWith('127.') &&
          !d.ip.startsWith('169.254.') &&
          d.ip.split('.').length == 4 &&
          !_esDeMentira(d.conexion))
        d,
  ];
  int puesto(DireccionDeLaPc d) {
    final router = esDireccionDeRouter(d.ip);
    final wifi = _esWifi(d.conexion);
    if (router && wifi) return 0;
    if (router) return 1;
    return 2;
  }

  final ordenadas = [...sirven];
  // `sort` no es estable en Dart: se desempata por la posición original.
  final orden = {for (var i = 0; i < sirven.length; i++) sirven[i]: i};
  ordenadas.sort((a, b) {
    final c = puesto(a).compareTo(puesto(b));
    return c != 0 ? c : orden[a]!.compareTo(orden[b]!);
  });
  final vistas = <String>{};
  return [
    for (final d in ordenadas)
      if (vistas.add(d.ip)) d.ip,
  ];
}

/// Las de esta PC, ya ordenadas. Vacía si no está conectada a nada.
Future<List<String>> direccionesDeEstaPc() async {
  try {
    final conexiones = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return direccionesParaCelulares([
      for (final c in conexiones)
        for (final a in c.addresses) DireccionDeLaPc(c.name, a.address),
    ]);
  } catch (_) {
    return const [];
  }
}
