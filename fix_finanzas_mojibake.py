"""Robust script to fix remaining mojibake in finanzas_view.dart by direct string and character replacements."""

with open("lib/features/mi_empresa/finanzas_view.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Let's perform a dictionary of character replacements for the CP1252 and Latin1 mojibakes.
# We will also clean up common words that got corrupted.
replacements = {
    # ── Word / Phrase level fixes ──
    "MAÑANA, TARDE y DA": "MAÑANA, TARDE y DÍA",
    "en qu tramo": "en qué tramo",
    "Si necesits": "Si necesitás",
    "maana\x9d": "mañana”",
    "solo maana\x9d": "“solo mañana”",
    "tarde\x9d": "tarde”",
    "solo tarde\x9d": "“solo tarde”",
    "us la": "usá la",
    "ah el": "ahí el",
    "turno s acota": "turno sí acota",
    "Efectivo: ${ef.toCurrency()}  Transferencia:": "Efectivo: ${ef.toCurrency()} · Transferencia:",
    "Prximos avisos": "Próximos avisos",
    "AVISOS  Toca para": "AVISOS · Toca para",
    "ancho til": "ancho útil",
    "pantalla vaca\x9d": "pantalla vacía”",
    "media pantalla vaca\x9d": "“media pantalla vacía”",
    "hay bsqueda": "hay búsqueda",
    "de “aire\x9d": "de “aire”",
    "B–F  Pulso": "B–F · Pulso",
    "categoras": "categorías",
    "Últimos 30 das": "Últimos 30 días",
    "DEL DA": "DEL DÍA",
    "movimiento del da": "movimiento del día",
    "Alertas de Gestin": "Alertas de Gestión",
    "ltimos 6 meses": "últimos 6 meses",
    "una conversin": "una conversión",
    "us PDF": "usá PDF",
    "prstamo": "préstamo",
    "categora": "categoría",
    "recepcin": "recepción",
    "pago(s)  Último:": "pago(s) · Último:",
    "Se borrar el": "Se borrará el",
    "Dilogo": "Diálogo",
    
    # ── Character level generic fixes ──
    "ltimos": "últimos",
    "bsqueda": "búsqueda",
    "vaca": "vacía",
    "til": "útil",
    "necesits": "necesitás",
    "us": "usá",
    "ah": "ahí",
    "s": "sí",
    "qu": "qué",
    "da": "día",
    "DA": "DÍA",
    "corrindose": "corriéndose",
    "gestin": "gestión",
    "Gestin": "Gestión",
    "operacin": "operación",
    "Operacin": "Operación",
    " liquidacin": " liquidación",
    "Liquidacin": "Liquidación",
    "conversin": "conversión",
    "": "·", # Fallback for remaining single unrecognized tokens
}

# Apply all replacements
for bad, good in replacements.items():
    content = content.replace(bad, good)

# Also replace any remaining sequences starting with U+20AC (Euro) and U+00E2 (a-circumflex)
# which are hallmarks of double CP1252 encoding.
content = content.replace("€â€”", "—")
content = content.replace("â€œ", "“")
content = content.replace("â€\x9d", "”")
content = content.replace("â€¦", "…")
content = content.replace("â€¢", "•")
content = content.replace("â€“", "–")
content = content.replace("â€”", "—")

with open("lib/features/mi_empresa/finanzas_view.dart", "w", encoding="utf-8") as f:
    f.write(content)

print("Robust mojibake fix completed!")
