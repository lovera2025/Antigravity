import '../services/productos_para_vender.dart' show paraBuscar;

/// Las fotos de los tragos y las marcas que vienen **adentro de la app**
/// (`assets/barra/`), y cuál le toca a cada producto por su nombre.
///
/// Pedido del usuario (3 y 4-nov): "el jefe debería cargarlas, pero sé que no lo
/// hará", y que estén las marcas que se venden en Argentina. Así nadie carga nada:
/// cuando el jefe da de alta "Quilmes lata", la tarjeta sale con la foto de la lata de
/// Quilmes, en todos los equipos y sin internet, porque la foto viaja con la app, no
/// por la base. Si el jefe quiere otra, la elige de esta biblioteca o sube una propia
/// (etapa 7): eso va en `ProductoBarra.imagenUrl`. De dónde salió cada foto y su
/// licencia: `docs/FOTOS_DE_LA_BARRA.md`.
abstract final class FotoDeLaBarra {
  static const carpeta = 'assets/barra';

  /// `imagenUrl` que elige una foto de la biblioteca a mano: "biblioteca:fernet". Sin
  /// columna nueva: va en el mismo texto que la URL de una foto propia.
  static const prefijo = 'biblioteca:';

  /// Las fotos de la biblioteca: cada una es `assets/barra/<clave>.jpg`.
  static const claves = [
    // Tragos
    'fernet', 'gin_tonic', 'gin_frutos_rojos', 'vodka', 'destornillador', 'campari', 'aperol',
    'cynar', 'gancia', 'vermut', 'whisky', 'ron', 'tequila', 'tequila_sunrise', 'shot',
    'mojito', 'caipirinha', 'daiquiri', 'pina_colada', 'trago_azul', 'trago_frutal', 'clerico',
    // Cervezas, por estilo y por cómo se sirve
    'cerveza_lata', 'cerveza_porron', 'cerveza_tirada', 'cerveza_rubia', 'cerveza_roja',
    'cerveza_negra', 'cerveza_ipa',
    // Cervezas, por marca
    'quilmes', 'quilmes_lata', 'brahma', 'andes', 'patagonia', 'imperial', 'imperial_golden', 'stella', 'heineken',
    'heineken_lata', 'corona', 'budweiser', 'amstel', 'miller', 'warsteiner', 'isenbeck',
    // Bebidas blancas, por marca
    'smirnoff', 'absolut', 'gordons', 'bombay', 'johnnie_walker', 'jack_daniels', 'chivas',
    'bacardi', 'havana_club', 'jagermeister', 'malibu', 'cinzano',
    // Vinos y espumantes
    'vino_tinto', 'vino_blanco', 'champan',
    // Sin alcohol
    'agua', 'agua_con_gas', 'villavicencio', 'gaseosa', 'coca_cola', 'sprite', 'fanta', 'pepsi',
    'speed', 'red_bull', 'monster', 'jugo', 'limonada', 'cafe',
  ];

  static String ruta(String clave) => '$carpeta/$clave.jpg';

  /// La clave de la foto que le toca a un producto, o null si su nombre y su
  /// categoría no dicen nada conocido (la tarjeta muestra la inicial).
  static String? para(String nombre, [String categoria = '']) =>
      _porTexto(paraBuscar(nombre)) ?? _porCategoria(paraBuscar(categoria));

  /// En tres pasadas, y en cada una gana lo primero que aparece:
  /// 1. **lo que se toma**: los tragos y las bebidas blancas (por marca o por tipo),
  ///    y las cervezas por marca. "Fernet con coca" es fernet, "Speed con vodka" es
  ///    vodka y "Gancia con Sprite" es Gancia: la gaseosa o el energizante es la mezcla;
  /// 2. **la cerveza sin marca**, por estilo (IPA, roja, negra, rubia) y por cómo se
  ///    sirve (tirada, porrón, lata);
  /// 3. **lo sin alcohol**: las gaseosas, los energizantes y el agua por marca, y si
  ///    no, por tipo.
  static String? _porTexto(String t) {
    if (t.isEmpty) return null;
    final palabras = t.split(RegExp(r'[^a-z0-9]+')).where((p) => p.isNotEmpty).toSet();
    bool hay(String w) => w.contains(' ') ? t.contains(w) : palabras.contains(w);
    bool algunaDe(List<String> ws) => ws.any(hay);

    // ── 1. Lo que se toma ──
    if (algunaDe(['fernet', 'branca'])) return 'fernet';
    if (algunaDe(['cuba', 'cubalibre'])) return 'ron';
    for (final (ws, clave) in _marcasDeBebidaBlanca) {
      if (algunaDe(ws)) return clave;
    }
    final esLata = hay('lata');
    if (hay('imperial')) return hay('golden') ? 'imperial_golden' : 'imperial';
    for (final (ws, clave, lata) in _marcasDeCerveza) {
      if (algunaDe(ws)) return esLata && lata != null ? lata : clave;
    }
    if (hay('sunrise')) return 'tequila_sunrise';
    if (algunaDe(['shot', 'shots', 'chupito', 'chupitos'])) return 'shot';
    if (hay('campari')) return 'campari';
    if (algunaDe(['aperol', 'spritz'])) return 'aperol';
    if (hay('cynar')) return 'cynar';
    if (algunaDe(['gancia', 'americano'])) return 'gancia';
    if (algunaDe(['vermut', 'vermu', 'vermouth', 'martini', 'carpano'])) return 'vermut';
    if (algunaDe(['gin', 'gintonic', 'ginebra'])) {
      return algunaDe(['frutos', 'frutilla', 'pink', 'rosa', 'berries', 'frambuesa', 'rojos'])
          ? 'gin_frutos_rojos'
          : 'gin_tonic';
    }
    if (algunaDe(['destornillador', 'screwdriver'])) return 'destornillador';
    if (hay('vodka')) return algunaDe(['naranja', 'jugo']) ? 'destornillador' : 'vodka';
    if (algunaDe(['whisky', 'whiskey', 'bourbon'])) return 'whisky';
    if (algunaDe(['ron', 'rum'])) return 'ron';
    if (algunaDe(['tequila', 'margarita'])) return 'tequila';
    if (algunaDe(['pina colada', 'colada'])) return 'pina_colada';
    if (algunaDe(['blue', 'azul', 'curacao', 'lagoon'])) return 'trago_azul';
    if (hay('mojito')) return 'mojito';
    if (algunaDe(['caipi', 'caipirinha', 'caipiroska', 'caipirissima'])) return 'caipirinha';
    if (algunaDe(['daiquiri', 'frozen'])) return 'daiquiri';
    if (algunaDe(['clerico', 'sangria', 'tinto de verano'])) return 'clerico';
    if (algunaDe(['frutal', 'tropical', 'sex on the beach', 'mocktail'])) return 'trago_frutal';
    // Sin acentos ni ñ: "Champaña" llega como "champana".
    if (algunaDe(['champan', 'champagne', 'champana', 'espumante', 'chandon', 'brut', 'sidra', 'prosecco'])) {
      return 'champan';
    }
    if (algunaDe(['vino', 'malbec', 'cabernet', 'torrontes', 'chardonnay'])) {
      return algunaDe(['blanco', 'torrontes', 'chardonnay', 'rosado']) ? 'vino_blanco' : 'vino_tinto';
    }

    // ── 2. La cerveza sin marca ──
    final estilo = <(List<String>, String)>[
      (['ipa', 'apa', 'pale'], 'cerveza_ipa'),
      (['negra', 'stout', 'porter', 'oscura'], 'cerveza_negra'),
      (['roja', 'red', 'amber', 'scottish', 'irish'], 'cerveza_roja'),
      (['rubia', 'golden', 'lager', 'pilsen', 'pils', 'honey', 'blonde', 'miel'], 'cerveza_rubia'),
    ];
    final esCerveza = algunaDe(['cerveza', 'cervezas', 'birra', 'chopp', 'pinta', 'porron']);
    for (final (ws, clave) in estilo) {
      // "IPA" o "Stout" solos ya son cerveza; "roja" o "rubia" solas, no.
      final solas = clave == 'cerveza_ipa' || clave == 'cerveza_negra' && algunaDe(['stout', 'porter']);
      if ((esCerveza || solas) && algunaDe(ws)) return clave;
    }
    if (esCerveza) {
      if (algunaDe(['tirada', 'chopp', 'pinta', 'vaso'])) return 'cerveza_tirada';
      if (algunaDe(['porron', 'botella', 'litro'])) return 'cerveza_porron';
      return 'cerveza_lata';
    }

    // ── 3. Lo sin alcohol ──
    if (hay('speed')) return 'speed';
    if (algunaDe(['red bull', 'redbull'])) return 'red_bull';
    if (hay('monster')) return 'monster';
    if (algunaDe(['energizante', 'energizantes', 'energy'])) return 'speed';
    if (algunaDe(['coca', 'cocacola', 'coca cola'])) return 'coca_cola';
    if (hay('sprite')) return 'sprite';
    if (hay('fanta')) return 'fanta';
    if (hay('pepsi')) return 'pepsi';
    // Antes que el agua: "agua tónica" es una gaseosa.
    if (algunaDe(['tonica', 'gaseosa', 'gaseosas', 'seven', '7up', 'pomelo', 'paso de los toros', 'schweppes', 'manaos'])) {
      return 'gaseosa';
    }
    if (hay('villavicencio')) return 'villavicencio';
    if (algunaDe(['agua', 'soda'])) {
      // "Agua sin gas" lleva la palabra gas: lo que cuenta es "con gas".
      final conGas = t.contains('con gas') || hay('soda') || hay('gasificada');
      return conGas ? 'agua_con_gas' : 'agua';
    }
    if (hay('limonada')) return 'limonada';
    if (algunaDe(['jugo', 'exprimido', 'naranja'])) return 'jugo';
    if (algunaDe(['cafe', 'cafecito', 'cortado', 'expreso', 'espresso'])) return 'cafe';
    return null;
  }

  static const _marcasDeBebidaBlanca = <(List<String>, String)>[
    (['smirnoff'], 'smirnoff'),
    (['absolut'], 'absolut'),
    (['gordon', 'gordons'], 'gordons'),
    (['bombay', 'sapphire'], 'bombay'),
    (['johnnie', 'walker', 'black label', 'red label'], 'johnnie_walker'),
    (['jack daniels', 'jack daniel', 'daniels'], 'jack_daniels'),
    (['chivas'], 'chivas'),
    (['bacardi'], 'bacardi'),
    (['havana'], 'havana_club'),
    (['jager', 'jagger', 'jaeger', 'jagermeister'], 'jagermeister'),
    (['malibu'], 'malibu'),
    (['cinzano'], 'cinzano'),
  ];

  /// La marca, su foto, y la de la lata si hay una aparte.
  static const _marcasDeCerveza = <(List<String>, String, String?)>[
    (['quilmes'], 'quilmes', 'quilmes_lata'),
    (['heineken'], 'heineken', 'heineken_lata'),
    (['brahma'], 'brahma', null),
    (['andes'], 'andes', null),
    (['patagonia'], 'patagonia', null),
    (['stella', 'artois'], 'stella', null),
    (['corona', 'coronita'], 'corona', null),
    (['budweiser'], 'budweiser', null),
    (['amstel'], 'amstel', null),
    (['miller'], 'miller', null),
    (['warsteiner'], 'warsteiner', null),
    (['isenbeck'], 'isenbeck', null),
    (['guinness'], 'cerveza_negra', null),
  ];

  /// Si el nombre no dice nada: por la categoría que le puso el jefe.
  static String? _porCategoria(String c) {
    if (c.isEmpty) return null;
    final porNombre = _porTexto(c);
    if (porNombre != null) return porNombre;
    if (c.contains('cerveza')) return 'cerveza_lata';
    if (c.contains('trago') || c.contains('coctel') || c.contains('cocktail')) return 'gin_tonic';
    if (c.contains('espumante')) return 'champan';
    if (c.contains('vino')) return 'vino_tinto';
    if (c.contains('energizante')) return 'speed';
    if (c.contains('sin alcohol') || c.contains('bebida')) return 'agua';
    return null;
  }
}
