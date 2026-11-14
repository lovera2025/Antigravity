#!/bin/bash
# Corre la suite entera por tandas de 40 archivos, sin los tres tests que
# consultan la nube. Entera en un solo comando no entra; así tarda unos 5 minutos.
#
#   bash tool/suite_por_tandas.sh [carpeta de salida]
#
# Se corre desde la raíz del repositorio. Deja un registro por tanda en la
# carpeta de salida (si no se pasa, una temporal) y termina con
# "FIN fallo=0 total=N". Con algún fallo, lista los tests que fallaron.
#
# Mientras corre, no escribir en lib/ ni en test/: hay tests que leen carpetas
# enteras (por ejemplo lib/features/entradas/widgets) y un archivo a medio
# escribir los hace fallar.
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
rm -f "$OUT"/tanda_*.txt "$OUT"/tanda_*.log
find test -name "*_test.dart" | sort \
  | grep -vE "verify_supabase_content_test|query_supabase_id_test|search_supabase_broad_test" \
  > "$OUT/archivos.txt"
echo "archivos: $(wc -l < "$OUT/archivos.txt") · registros en $OUT"
split -l 40 -d "$OUT/archivos.txt" "$OUT/tanda_"
for f in "$OUT"/tanda_??; do mv "$f" "$f.txt"; done
fallo=0
total=0
for f in "$OUT"/tanda_??.txt; do
  n=$(basename "$f" .txt)
  flutter test --reporter=expanded $(tr '\n' ' ' < "$f") > "$OUT/$n.log" 2>&1
  codigo=$?
  ultima=$(grep -E "^[0-9]{2}:[0-9]{2} \+[0-9]+" "$OUT/$n.log" | tail -1)
  echo "$n (salida $codigo): $ultima"
  pasaron=$(echo "$ultima" | sed -E 's/^[0-9:]+ \+([0-9]+).*/\1/')
  total=$((total + ${pasaron:-0}))
  if [ $codigo -ne 0 ]; then
    fallo=1
    grep -E "\[E\]$" "$OUT/$n.log" | sed -E 's/^[0-9:]+ \+[0-9]+ -[0-9]+: //' | sort -u | head -8
  fi
done
echo "FIN fallo=$fallo total=$total"
