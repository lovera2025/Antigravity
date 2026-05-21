"""
fix_encoding.py  (v2)
Corrige TODA la doble-codificacion (mojibake) en archivos .dart del proyecto.
Cubre acentos, enie, signos, comillas tipograficas, guiones, puntos suspensivos,
simbolos matematicos, etc.
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "lib")

# ─── Mapa completo mojibake -> correcto ───────────────────────────────────────
# Patron: UTF-8 bytes leidos como Latin-1, luego re-guardados como UTF-8.
# Cada char original de 2 bytes (C3 xx) se expande a 4 bytes (C3 83 C2 xx).
# Chars de 3 bytes (E2 xx xx) se expanden a 6 bytes.
# Ordenamos de secuencias largas a cortas para evitar reemplazos parciales.
REPLACEMENTS = [
    # ── 3-byte chars (U+2000 range) doblemente codificados => 6 bytes ──
    # Puntos suspensivos
    ("\xc3\xa2\xc2\x80\xc2\xa6", "\u2026"),       # ...
    # Em-dash
    ("\xc3\xa2\xc2\x80\xc2\x94", "\u2014"),       # em-dash
    # En-dash
    ("\xc3\xa2\xc2\x80\xc2\x93", "\u2013"),       # en-dash
    # Left double quote
    ("\xc3\xa2\xc2\x80\xc2\x9c", "\u201c"),       # left dquote
    # Right double quote
    ("\xc3\xa2\xc2\x80\xc2\x9d", "\u201d"),       # right dquote
    # Left single quote
    ("\xc3\xa2\xc2\x80\xc2\x98", "\u2018"),       # left squote
    # Right single quote / apostrophe
    ("\xc3\xa2\xc2\x80\xc2\x99", "\u2019"),       # right squote
    # Bullet
    ("\xc3\xa2\xc2\x80\xc2\xa2", "\u2022"),       # bullet
    # Dagger
    ("\xc3\xa2\xc2\x80\xc2\xa0", "\u2020"),       # dagger
    # Arrows
    ("\xc3\xa2\xc2\x86\xc2\x92", "\u2192"),       # right arrow
    ("\xc3\xa2\xc2\x86\xc2\x90", "\u2190"),       # left arrow
    # Math
    ("\xc3\xa2\xc2\x89\xc2\xa5", "\u2265"),       # >=
    ("\xc3\xa2\xc2\x89\xc2\xa4", "\u2264"),       # <=
    # Checkmarks
    ("\xc3\xa2\xc2\x9c\xc2\x94", "\u2714"),       # heavy check
    ("\xc3\xa2\xc2\x9c\xc2\x97", "\u2717"),       # ballot x
    ("\xc3\xa2\xc2\x9c\xc2\x85", "\u2705"),       # white heavy check
    ("\xc3\xa2\xc2\x9d\xc2\x8c", "\u274c"),       # cross mark

    # ── 2-byte chars doblemente codificados => 4 bytes ──
    # Minusculas con tilde
    ("\xc3\x83\xc2\xa1", "\xe1"),   # a-aguda
    ("\xc3\x83\xc2\xa9", "\xe9"),   # e-aguda
    ("\xc3\x83\xc2\xad", "\xed"),   # i-aguda
    ("\xc3\x83\xc2\xb3", "\xf3"),   # o-aguda
    ("\xc3\x83\xc2\xba", "\xfa"),   # u-aguda
    # Mayusculas con tilde
    ("\xc3\x83\xc2\x81", "\xc1"),   # A-aguda
    ("\xc3\x83\xc2\x89", "\xc9"),   # E-aguda
    ("\xc3\x83\xc2\x8d", "\xcd"),   # I-aguda
    ("\xc3\x83\xc2\x93", "\xd3"),   # O-aguda
    ("\xc3\x83\xc2\x9a", "\xda"),   # U-aguda
    # Enie
    ("\xc3\x83\xc2\xb1", "\xf1"),   # n-tilde
    ("\xc3\x83\xc2\x91", "\xd1"),   # N-tilde
    # U-dieresis
    ("\xc3\x83\xc2\xbc", "\xfc"),   # u-dieresis
    ("\xc3\x83\xc2\x9c", "\xdc"),   # U-dieresis
    # Multiplication sign
    ("\xc3\x83\xc2\x97", "\xd7"),   # multiplication sign x
    # Signos de puntuacion
    ("\xc3\x82\xc2\xa1", "\xa1"),   # inverted excl
    ("\xc3\x82\xc2\xbf", "\xbf"),   # inverted question
    ("\xc3\x82\xc2\xb7", "\xb7"),   # middle dot
    ("\xc3\x82\xc2\xba", "\xba"),   # masculine ordinal
    ("\xc3\x82\xc2\xaa", "\xaa"),   # feminine ordinal
    ("\xc3\x82\xc2\xab", "\xab"),   # left guillemet
    ("\xc3\x82\xc2\xbb", "\xbb"),   # right guillemet
]

def fix_content_bytes(raw):
    """Work at byte level for accurate replacement."""
    changed = False
    for bad, good in REPLACEMENTS:
        bad_bytes = bad.encode('latin-1')  # raw bytes in the file
        good_bytes = good.encode('utf-8')  # correct UTF-8 bytes
        if bad_bytes in raw:
            raw = raw.replace(bad_bytes, good_bytes)
            changed = True
    return raw, changed

def process_file(path, dry_run=False):
    with open(path, "rb") as f:
        raw = f.read()

    fixed, changed = fix_content_bytes(raw)
    if not changed:
        return 0

    # Count how many replacements were made
    count = 0
    original = raw
    for bad, _ in REPLACEMENTS:
        bad_bytes = bad.encode('latin-1')
        count += original.count(bad_bytes)

    if not dry_run:
        with open(path, "wb") as f:
            f.write(fixed)

    return count

def main():
    dry_run = "--dry-run" in sys.argv
    if dry_run:
        print("=== MODO SIMULACION (--dry-run): no se escribe nada ===\n")

    fixed_files = []
    skipped = 0
    total_replacements = 0

    for dirpath, _, filenames in os.walk(ROOT):
        for fname in filenames:
            if not fname.endswith(".dart"):
                continue
            fpath = os.path.join(dirpath, fname)
            try:
                count = process_file(fpath, dry_run=dry_run)
                if count > 0:
                    rel = os.path.relpath(fpath, ROOT)
                    fixed_files.append(rel)
                    total_replacements += count
                    print("  OK {} ({} reemplazos)".format(rel, count))
                else:
                    skipped += 1
            except Exception as e:
                print("  ERROR en {}: {}".format(fpath, e))

    mode = "[SIMULACION] " if dry_run else ""
    print("\n{}Archivos corregidos: {}".format(mode, len(fixed_files)))
    print("{}Total de reemplazos: {}".format(mode, total_replacements))
    print("Archivos sin cambios: {}".format(skipped))

if __name__ == "__main__":
    main()
