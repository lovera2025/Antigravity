# -*- coding: utf-8 -*-
"""Parche RESUMEN DE CAJA — recuperado del .dill v3.6.0."""
from pathlib import Path

ROOT = Path(__file__).parent
TARGET = ROOT / "lib/features/mi_empresa/finanzas_view.dart"


def read_clean(name: str) -> str:
    text = (ROOT / name).read_text(encoding="utf-8-sig")
    return text.replace("\ufeff", "")


def indent_class_block(text: str) -> str:
    lines = []
    for line in text.rstrip().split("\n"):
        if line and not line[0].isspace():
            lines.append("  " + line)
        else:
            lines.append(line)
    return "\n".join(lines)


def build_helpers_only() -> str:
    saldo = read_clean("_rec_01_saldoPrincipalBlock.txt")
    saldo = saldo.split("  Widget _buildHudSectionDivider")[0].rstrip()

    divider_medio = read_clean("_rec_02_hudDivider_saldoPorMedio.txt")
    divider_medio = divider_medio.split("  Widget _buildOperacionHoySection")[0].rstrip()

    operacion = read_clean("_rec_03_operacionHoy.txt")
    operacion = operacion.split("  Widget _buildHUD(")[0].rstrip()

    helpers = read_clean("_rec_04_helpers.txt")
    helpers = helpers.split("  Widget _buildFiltroMeses")[0].rstrip()

    parts = [saldo, divider_medio, operacion, helpers]
    return "\n\n".join(indent_class_block(p) for p in parts) + "\n\n"


def build_hud_and_dialogs() -> str:
    hud_rest = read_clean("_rec_03_operacionHoy.txt").split("  Widget _buildHUD(", 1)[1]
    hud_rest = "  Widget _buildHUD(" + hud_rest.rstrip()
    if not hud_rest.rstrip().endswith("  }"):
        hud_rest = hud_rest.rstrip() + """
                ],
              ),
            );
          },
        );
      },
    );
  }
"""
    return indent_class_block(hud_rest) + "\n\n"


def build_hud_replacement() -> str:
    return build_helpers_only() + build_hud_and_dialogs()


def main():
    src = TARGET.read_text(encoding="utf-8")

    if "bolsillo_timeline.dart" not in src:
        src = src.replace(
            "import 'widgets/cobro_masivos_tab.dart';\nimport '../cierre_caja/models/turno_caja.dart';",
            "import 'widgets/cobro_masivos_tab.dart';\nimport 'widgets/bolsillo_timeline.dart';\nimport '../cierre_caja/models/turno_caja.dart';",
        )

    if "_hudHoyExpanded" not in src:
        src = src.replace(
            "  /// Scroll a secciones de la vista SALUD al tocar pilares del hero.",
            "  /// Operación del día en Resumen de caja (colapsada por defecto; el saldo principal queda arriba).\n"
            "  bool _hudHoyExpanded = false;\n\n"
            "  /// Caja fuerte colapsable en tab PERSONAL.\n"
            "  bool _cajaFuerteExpanded = true;\n\n"
            "  /// Scroll a secciones de la vista SALUD al tocar pilares del hero.",
        )

    src = src.replace(
        "  static Color _hudColorEstadoLiquidez(String status) {\n"
        "    if (status.contains('CRÍTICO')) return const Color(0xFFE74C3C);\n"
        "    return const Color(0xFF00B894);\n"
        "  }\n\n"
        "  bool _hudEsDiaCalendarioHoy",
        "  static Color _hudColorEstadoLiquidez(String status) {\n"
        "    if (status.contains('CRÍTICO')) return const Color(0xFFE74C3C);\n"
        "    if (status.contains('ADVERTENCIA')) return const Color(0xFFE67E22);\n"
        "    return const Color(0xFF00B894);\n"
        "  }\n\n"
        "  String _hudLiquidezBadgeLabel(FinanzasState state) {\n"
        "    final st = _hudEstadoLiquidezLocal(state);\n"
        "    if (st.contains('CRÍTICO')) return 'Liquidez crítica · 30 días';\n"
        "    if (st.contains('ADVERTENCIA')) return 'Liquidez ajustada · 30 días';\n"
        "    return 'Flujo positivo';\n"
        "  }\n\n"
        "  bool _hudEsDiaCalendarioHoy",
    )

    src = src.replace(
        "    required String bucket,\n"
        "    double? retirosTurno,\n"
        "  }) {\n"
        "    final retiros = retirosTurno ?? 0.0;\n"
        "    return Material(\n"
        "      color: Colors.transparent,\n"
        "      child: InkWell(\n"
        "        onTap: () => _abrirDetalleIngresosHoyPorMedio(context, isDark, state, bucket),",
        "    required String bucket,\n"
        "    String? contexto,\n"
        "    double? retirosTurno,\n"
        "  }) {\n"
        "    final retiros = retirosTurno ?? 0.0;\n"
        "    return Material(\n"
        "      color: Colors.transparent,\n"
        "      child: InkWell(\n"
        "        onTap: bucket.isEmpty ? null : () => _abrirDetalleIngresosHoyPorMedio(context, isDark, state, bucket),",
    )

    old_tile_label = (
        "                  Expanded(\n"
        "                    child: Text(\n"
        "                      label,\n"
        "                      style: TextStyle(\n"
        "                        fontSize: compact ? 9 : 11,\n"
        "                        fontWeight: FontWeight.w900,\n"
        "                        letterSpacing: 0.7,\n"
        "                        color: accent,\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        "                  Icon(Icons.playlist_add_check_rounded, size: compact ? 14 : 16, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.22)),"
    )
    new_tile_label = (
        "                  Expanded(\n"
        "                    child: Column(\n"
        "                      crossAxisAlignment: CrossAxisAlignment.start,\n"
        "                      children: [\n"
        "                        Text(\n"
        "                          label,\n"
        "                          style: TextStyle(\n"
        "                            fontSize: compact ? 9 : 11,\n"
        "                            fontWeight: FontWeight.w900,\n"
        "                            letterSpacing: 0.7,\n"
        "                            color: accent,\n"
        "                          ),\n"
        "                        ),\n"
        "                        if (contexto != null)\n"
        "                          Text(\n"
        "                            contexto,\n"
        "                            style: TextStyle(\n"
        "                              fontSize: compact ? 8 : 9,\n"
        "                              fontWeight: FontWeight.w700,\n"
        "                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45),\n"
        "                            ),\n"
        "                          ),\n"
        "                      ],\n"
        "                    ),\n"
        "                  ),\n"
        "                  Icon(Icons.playlist_add_check_rounded, size: compact ? 14 : 16, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.22)),"
    )
    if old_tile_label in src:
        src = src.replace(old_tile_label, new_tile_label, 1)

    start = src.find("  Widget _buildHudModoSelector(")
    keep_from = src.find("  List<IngresoDetallado> _ingresosHoyPorMedioBucket(")
    if start < 0 or keep_from < 0:
        raise SystemExit(f"HUD markers missing: {start}, {keep_from}")
    src = src[:start] + build_helpers_only() + src[keep_from:]
    mid2 = src.find("  Widget _buildHUD(")
    end2 = src.find("  Widget _buildFiltroMeses(")
    src = src[:mid2] + build_hud_and_dialogs() + src[end2:]

    bolsillo = read_clean("_rec_05_bolsilloMiniCard.txt").split("  /// Caja fuerte:")[0].rstrip()
    marker = "  Widget _buildCajaFuertePersonalSection("
    if "_buildTuBolsilloMiniCard" not in src:
        src = src.replace(marker, indent_class_block(bolsillo) + "\n\n" + marker)

    old_personal = """            children: [
              _buildCajaFuertePersonalSection(isDark, gold),
              const SizedBox(height: 28),
              if (personal.isEmpty)
                Center(child: _placeholderSinPagosPersonal(blue))
              else ...[
              // ── Banner total personal"""
    new_personal = """            children: [
              _buildTuBolsilloMiniCard(context, isDark, gold, state),
              const SizedBox(height: 16),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: _cajaFuerteExpanded,
                  onExpansionChanged: (v) => setState(() => _cajaFuerteExpanded = v),
                  title: Text(
                    'CAJA FUERTE · cofre físico',
                    style: GoogleFonts.oswald(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1),
                  ),
                  subtitle: const Text(
                    'Cuánto hay en el cofre según depósitos y retiros',
                    style: TextStyle(fontSize: 11),
                  ),
                  children: [
                    _buildCajaFuertePersonalSection(isDark, gold),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _sectionLabel('PAGOS DEL NEGOCIO A OPERADORES', Icons.engineering_outlined),
              const SizedBox(height: 12),
              if (personal.isEmpty)
                Center(child: _placeholderSinPagosPersonal(blue))
              else ...[
              // ── Banner total personal"""
    if "_buildTuBolsilloMiniCard(context" not in src.split("_buildPersonalTab", 1)[1][:900]:
        src = src.replace(old_personal, new_personal)

    TARGET.write_text(src, encoding="utf-8", newline="\n")
    print("OK")


if __name__ == "__main__":
    main()
