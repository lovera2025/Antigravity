"""Find all lines with remaining mojibake or euro sign in finanzas_view.dart."""

with open("lib/features/mi_empresa/finanzas_view.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "€" in line or "â" in line or "Ã" in line or "Ã¡" in line:
        print(f"Line {i+1}: {repr(line)}")
