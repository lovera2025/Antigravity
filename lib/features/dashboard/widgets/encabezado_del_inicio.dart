import 'package:flutter/material.dart';

import '../../common/widgets/animated_brand_logo.dart';

/// El título de la barra de arriba del inicio: el logo, "JUNIOR EVENTOS" y cómo se
/// entró (MODO JEFE, o CAJA · el operador).
///
/// **En un celular no entra todo** (6.5.0, lo mandó el usuario el 10-nov con una foto de
/// su Android: el título y los botones salían uno encima del otro). Ahí va el logo y
/// cómo se entró, sin el nombre; y si aun así no entra, el cartel se acorta con puntos
/// suspensivos en vez de pisar lo de al lado.
class TituloDelInicio extends StatelessWidget {
  final bool enCelular;
  final bool modoJefe;

  /// El nombre de quien entró a la caja, si entró como operador. Null: no es caja.
  final String? cajaDe;

  const TituloDelInicio({
    super.key,
    required this.enCelular,
    required this.modoJefe,
    this.cajaDe,
  });

  static const _oro = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final caja = cajaDe;
    Widget? cartel;
    if (modoJefe) {
      cartel = _Cartel(
        key: const Key('inicio_modo_jefe'),
        texto: 'MODO JEFE',
        corto: 'JEFE',
        color: _oro,
        letra: _oro,
      );
    } else if (caja != null) {
      cartel = _Cartel(
        key: const Key('inicio_caja_de'),
        texto: 'CAJA · ${caja.toUpperCase()}',
        color: Colors.teal,
        letra: isDark ? Colors.tealAccent : Colors.teal.shade800,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBrandLogo(height: enCelular ? 24 : 28),
        if (!enCelular) ...[
          const SizedBox(width: 10),
          const Text(
            'JUNIOR EVENTOS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
        if (cartel != null) ...[
          SizedBox(width: enCelular ? 6 : 10),
          Flexible(child: cartel),
        ],
      ],
    );
  }
}

class _Cartel extends StatelessWidget {
  final String texto;

  /// Lo que dice si [texto] no entra entero ("JEFE" por "MODO JEFE"). Sin esto, se
  /// acorta con puntos suspensivos.
  final String? corto;
  final Color color;
  final Color letra;

  const _Cartel({
    super.key,
    required this.texto,
    this.corto,
    required this.color,
    required this.letra,
  });

  static const _borde = 18.0;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      color: letra,
    );
    return LayoutBuilder(
      builder: (context, caja) {
        var mostrar = texto;
        final corto = this.corto;
        if (corto != null && caja.maxWidth.isFinite) {
          final medida = TextPainter(
            text: TextSpan(
              text: texto,
              style: DefaultTextStyle.of(context).style.merge(estilo),
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          if (medida.width + _borde > caja.maxWidth) mostrar = corto;
          medida.dispose();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Text(
            mostrar,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: estilo,
          ),
        );
      },
    );
  }
}

/// En un celular, lo que en la PC son tres botones sueltos (Actualizar, Cambiar tema,
/// Cerrar sesión) va en un solo menú: sueltos no entran al lado del estado de la caja.
class MasDelInicio extends StatelessWidget {
  final bool temaOscuro;
  final VoidCallback onActualizar;
  final VoidCallback onCambiarTema;
  final VoidCallback onCerrarSesion;

  const MasDelInicio({
    super.key,
    required this.temaOscuro,
    required this.onActualizar,
    required this.onCambiarTema,
    required this.onCerrarSesion,
  });

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<VoidCallback> opcion(String clave, IconData icono, String texto, VoidCallback hacer) =>
        PopupMenuItem<VoidCallback>(
          key: Key(clave),
          value: hacer,
          child: Row(
            children: [
              Icon(icono, size: 20),
              const SizedBox(width: 12),
              Text(texto),
            ],
          ),
        );
    return PopupMenuButton<VoidCallback>(
      key: const Key('inicio_mas'),
      tooltip: 'Más',
      icon: const Icon(Icons.more_vert, size: 22),
      onSelected: (hacer) => hacer(),
      itemBuilder: (_) => [
        opcion('inicio_mas_actualizar', Icons.refresh, 'Actualizar', onActualizar),
        opcion(
          'inicio_mas_tema',
          temaOscuro ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          temaOscuro ? 'Tema claro' : 'Tema oscuro',
          onCambiarTema,
        ),
        opcion('inicio_mas_salir', Icons.logout_rounded, 'Cerrar sesión', onCerrarSesion),
      ],
    );
  }
}
