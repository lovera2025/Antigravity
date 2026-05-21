"""Show exact characters around specified positions in finanzas_view.dart."""

with open("lib/features/mi_empresa/finanzas_view.dart", "r", encoding="utf-8") as f:
    text = f.read()

positions = [73615, 76115, 99328, 131624, 139787, 143362, 156070, 159443, 197623, 205676, 219448, 230026, 238992, 259436, 267363, 268249, 275206, 284487, 286745]

for pos in positions:
    if pos < len(text):
        ctx = text[max(0, pos-10):pos+15]
        print(f"Pos {pos}:")
        print(f"  String: {repr(ctx)}")
        print(f"  Codes:  {[ord(c) for c in ctx]}")
