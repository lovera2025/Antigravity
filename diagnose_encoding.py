"""Diagnose CP-1252 mojibake patterns in finanzas_view.dart."""

with open("lib/features/mi_empresa/finanzas_view.dart", "rb") as f:
    raw = f.read()

text = raw.decode('utf-8')

# In CP-1252 mojibake, the 3-byte UTF-8 sequence E2 80 XX becomes:
# E2 -> U+00E2 (a-circumflex) as Latin-1, BUT
# 80 -> U+20AC (euro sign) in CP-1252 (vs control char in Latin-1)
# So "â€"" = a-circumflex + euro + right-double-quote (in CP-1252 reading)
# But we already decoded as UTF-8 successfully, meaning the file contains
# the CHARACTERS U+00E2, U+20AC, U+201D etc. as valid UTF-8 multi-byte sequences.

# The CP-1252 mojibake triplets that represent original 3-byte UTF-8 chars:
# Original E2 80 93 (en-dash) read as CP-1252: â (E2) + € (80) + " (93)
# BUT 93 in CP-1252 is U+201C (left double smart quote), not U+2013
# Hmm wait - let me re-check

# CP-1252 byte-to-char mapping for the 80-9F range:
cp1252_map = {
    0x80: '\u20ac',  # euro
    0x82: '\u201a',  # single low-9 quote
    0x83: '\u0192',  # f with hook
    0x84: '\u201e',  # double low-9 quote
    0x85: '\u2026',  # ellipsis (wait, this IS the correct char!)
    0x86: '\u2020',  # dagger
    0x87: '\u2021',  # double dagger
    0x88: '\u02c6',  # circumflex modifier
    0x89: '\u2030',  # per mille
    0x8a: '\u0160',  # S-caron
    0x8b: '\u2039',  # single left guillemet
    0x8c: '\u0152',  # OE ligature
    0x8e: '\u017d',  # Z-caron
    0x91: '\u2018',  # left single quote
    0x92: '\u2019',  # right single quote
    0x93: '\u201c',  # left double quote
    0x94: '\u201d',  # right double quote
    0x95: '\u2022',  # bullet
    0x96: '\u2013',  # en-dash
    0x97: '\u2014',  # em-dash
    0x98: '\u02dc',  # small tilde
    0x99: '\u2122',  # trademark
    0x9a: '\u0161',  # s-caron
    0x9b: '\u203a',  # single right guillemet
    0x9c: '\u0153',  # oe ligature
    0x9e: '\u017e',  # z-caron
    0x9f: '\u0178',  # Y-diaeresis
}

# So the mojibake for en-dash (E2 80 96 in CP1252 = E2 80 96... no)
# Wait: en-dash = U+2013 = UTF-8 bytes E2 80 93
# Byte E2 read as CP-1252 = â (U+00E2)
# Byte 80 read as CP-1252 = € (U+20AC) 
# Byte 93 read as CP-1252 = " (U+201C, left double smart quote)
# So en-dash mojibake = â€œ (3 chars)
# But that's also left-double-quote mojibake pattern!

# em-dash = U+2014 = E2 80 94
# 94 in CP-1252 = " (U+201D, RIGHT double smart quote)
# So em-dash mojibake = â€ followed by right-double-quote

# ellipsis = U+2026 = E2 80 A6
# A6 in CP-1252 = ¦ (U+00A6, broken bar) -- same as Latin-1
# So ellipsis mojibake = â€¦

# left-double-quote = U+201C = E2 80 9C
# 9C in CP-1252 = œ (U+0153, oe ligature)
# So left-dquote mojibake = â€œ -- SAME as en-dash! Can't distinguish by pattern alone.

# Let's find the actual patterns
# Search for â€" (a-circumflex + euro + em-dash-char-in-text)
# Actually the text has the Unicode chars, so let's search for triplets

mojibake_patterns = {
    # original -> mojibake triplet (as Unicode chars from CP-1252 reading)
    'en-dash (U+2013)': '\u00e2\u20ac\u201c',   # â + € + " (left)
    'em-dash (U+2014)': '\u00e2\u20ac\u201d',   # â + € + " (right) -- but this is 3 very common chars
    'ellipsis (U+2026)': '\u00e2\u20ac\u00a6',   # â + € + ¦
    'left-dquote (U+201C)': '\u00e2\u20ac\u0153', # â + € + œ
    'right-dquote (U+201D)': '\u00e2\u20ac\u009d', # â + € + control... hmm
    'bullet (U+2022)': '\u00e2\u20ac\u00a2',     # â + € + ¢
    'gte (U+2265)': '\u00e2\u2030\u00a5',        # â + ‰ + ¥ ... hmm
}

print("--- Searching for CP-1252 mojibake triplets ---")
for name, pat in mojibake_patterns.items():
    cnt = text.count(pat)
    if cnt > 0:
        idx = text.find(pat)
        context = text[max(0,idx-15):idx+15+len(pat)]
        print(f"  {name}: {cnt} occ, first context: ...{repr(context)}...")

# More practical: let's find all â€ sequences and categorize what follows
print()
print("--- All sequences starting with a-circumflex + euro ---")
import re
ae_pattern = '\u00e2\u20ac'
positions = [m.start() for m in re.finditer(re.escape(ae_pattern), text)]
print(f"  Total 'â€' occurrences: {len(positions)}")
following = {}
for pos in positions:
    if pos + 2 < len(text):
        ch = text[pos + 2]
        key = f"U+{ord(ch):04X} ({repr(ch)})"
        following[key] = following.get(key, 0) + 1
print("  Char following 'â€':")
for k, v in sorted(following.items(), key=lambda x: -x[1]):
    print(f"    {k}: {v}")

# Also find standalone Ã (A-tilde) which are leftover from 2-byte double encoding
print()
print("--- Remaining A-tilde (U+00C3) contexts ---")
for i, ch in enumerate(text):
    if ch == '\u00c3':
        ctx = text[max(0,i-5):i+10]
        print(f"  pos {i}: {repr(ctx)}")
