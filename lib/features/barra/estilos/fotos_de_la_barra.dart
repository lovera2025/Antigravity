import '../services/productos_para_vender.dart' show paraBuscar;

/// Las fotos de los tragos que vienen **adentro de la app** (`assets/barra/`), y cuál
/// le toca a cada producto por su nombre.
///
/// Pedido del usuario (3 y 4-nov): "el jefe debería cargarlas, pero sé que no lo
/// hará". Así nadie carga nada: cuando el jefe da de alta "Fernet con coca", la tarjeta
/// sale con la foto del fernet, en todos los equipos y sin internet, porque la foto
/// viaja con la app, no por la base. Si el jefe quiere otra, la elige de esta
/// biblioteca o sube una propia (etapa 7): eso va en `ProductoBarra.imagenUrl`.
abstract final class FotoDeLaBarra {
  static const carpeta = 'assets/barra';

  /// `imagenUrl` que elige una foto de la biblioteca a mano: "biblioteca:fernet". Sin
  /// columna nueva: va en el mismo texto que la URL de una foto propia.
  static const prefijo = 'biblioteca:';

  /// Las fotos de la biblioteca: cada una es `assets/barra/<clave>.jpg`.
  static const claves = [
    'fernet',
    'gin_tonic',
    'vodka',
    'campari',
    'aperol',
    'whisky',
    'ron',
    'tequila',
    'trago_frutal',
    'cerveza_lata',
    'cerveza_porron',
    'cerveza_tirada',
    'vino_tinto',
    'vino_blanco',
    'champan',
    'agua',
    'agua_con_gas',
    'gaseosa',
    'jugo',
    'cafe',
  ];

  static String ruta(String clave) => '$carpeta/$clave.jpg';

  /// En el orden en que se miran: el primero que aparece en el nombre gana. Por eso
  /// "Fernet con coca" es fernet y no gaseosa, y "Speed con vodka", vodka.
  static const _reglas = <(List<String>, String)>[
    (['fernet', 'branca'], 'fernet'),
    (['campari'], 'campari'),
    (['aperol', 'spritz'], 'aperol'),
    (['gin', 'gintonic', 'ginebra'], 'gin_tonic'),
    (['vodka', 'speed', 'energizante', 'red bull', 'redbull'], 'vodka'),
    (['whisky', 'whiskey', 'scotch', 'bourbon'], 'whisky'),
    (['ron', 'cuba', 'cubalibre'], 'ron'),
    (['tequila', 'margarita'], 'tequila'),
    (['mojito', 'caipi', 'caipirinha', 'caipiroska', 'daiquiri', 'frutal', 'sex on the beach', 'tropical'], 'trago_frutal'),
    // Sin acentos ni ñ: "Champaña" llega como "champana".
    (['champan', 'champagne', 'champana', 'espumante', 'chandon', 'brut', 'sidra', 'prosecco'], 'champan'),
  ];

  /// La clave de la foto que le toca a un producto, o null si su nombre y su
  /// categoría no dicen nada conocido (la tarjeta muestra la inicial).
  static String? para(String nombre, [String categoria = '']) =>
      _porTexto(paraBuscar(nombre)) ?? _porCategoria(paraBuscar(categoria));

  static String? _porTexto(String t) {
    if (t.isEmpty) return null;
    final palabras = t.split(RegExp(r'[^a-z0-9ñ]+')).where((p) => p.isNotEmpty).toSet();
    bool hay(String w) => w.contains(' ') ? t.contains(w) : palabras.contains(w);
    bool algunaDe(List<String> ws) => ws.any(hay);

    for (final (palabrasDeLaRegla, clave) in _reglas) {
      if (algunaDe(palabrasDeLaRegla)) return clave;
    }
    // Antes que la cerveza y el agua: "Coca lata" y "agua tónica" son gaseosas.
    if (algunaDe(['tonica', 'gaseosa', 'coca', 'cocacola', 'sprite', 'fanta', 'pepsi', 'seven', '7up', 'pomelo', 'paso de los toros', 'schweppes'])) {
      return 'gaseosa';
    }
    if (algunaDe(['cerveza', 'birra', 'chopp', 'pinta', 'porron', 'quilmes', 'stella', 'heineken', 'brahma', 'corona', 'imperial', 'patagonia'])) {
      if (algunaDe(['tirada', 'chopp', 'pinta', 'vaso'])) return 'cerveza_tirada';
      if (algunaDe(['porron', 'botella', 'litro', 'corona'])) return 'cerveza_porron';
      return 'cerveza_lata';
    }
    if (algunaDe(['vino', 'malbec', 'cabernet', 'torrontes', 'chardonnay'])) {
      return algunaDe(['blanco', 'torrontes', 'chardonnay', 'rosado']) ? 'vino_blanco' : 'vino_tinto';
    }
    if (algunaDe(['agua', 'soda'])) {
      // "Agua sin gas" lleva la palabra gas: lo que cuenta es "con gas".
      final conGas = t.contains('con gas') || hay('soda') || hay('gasificada');
      return conGas ? 'agua_con_gas' : 'agua';
    }
    if (algunaDe(['jugo', 'exprimido', 'naranja', 'limonada'])) return 'jugo';
    if (algunaDe(['cafe', 'cafecito', 'cortado', 'expreso', 'espresso'])) return 'cafe';
    return null;
  }

  /// Si el nombre no dice nada: por la categoría que le puso el jefe.
  static String? _porCategoria(String c) {
    if (c.isEmpty) return null;
    final porNombre = _porTexto(c);
    if (porNombre != null) return porNombre;
    if (c.contains('cerveza')) return 'cerveza_lata';
    if (c.contains('trago') || c.contains('coctel') || c.contains('cocktail')) return 'gin_tonic';
    if (c.contains('espumante')) return 'champan';
    if (c.contains('vino')) return 'vino_tinto';
    if (c.contains('sin alcohol') || c.contains('bebida')) return 'agua';
    return null;
  }
}
