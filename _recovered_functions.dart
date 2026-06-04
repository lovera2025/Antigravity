
// ═══════════════════════ _buildOperacionHoySection ═══════════════════════
Widget _buildOperacionHoySection(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }

// ═══════════════════════ _buildSaldoPrincipalBlock ═══════════════════════
Widget _buildSaldoPrincipalBlock(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }

// ═══════════════════════ _medioChipMini ═══════════════════════
Widget _medioChipMini(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

// ═══════════════════════ _buildHudSectionDivider ═══════════════════════
Widget _buildHudSectionDivider(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
        ],
      ),
    );
  }

// ═══════════════════════ _empresaDetalleLinea ═══════════════════════
Widget _empresaDetalleLinea(String lbl, double monto, Color color, bool isDark, {bool negativo = false}

// ═══════════════════════ tarjetaSaldo ═══════════════════════
Widget tarjetaSaldo({
      required String titulo,
      required String subtitulo,
      required double monto,
      required Color accent,
      required VoidCallback onTap,
      List<Widget>? chips,
      Widget? trailing,
    }

// ═══════════════════════ _buildSaldoPorMedioSection ═══════════════════════
Widget _buildSaldoPorMedioSection(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }
