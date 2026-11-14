#!/bin/bash
# Roturas a propósito: cambia una regla del código, corre su test (tiene que
# FALLAR) y deja el archivo exactamente como estaba (lo comprueba con sha256).
# Sirve para saber que un test de verdad vigila la regla que dice vigilar.
#
#   bash tool/romper_una_regla.sh <archivo con los casos>
#
# Se corre desde la raíz del repositorio. El archivo de casos lleva, por caso,
# cinco renglones y uno de "---":
#
#   el nombre del caso
#   el archivo a romper            (lib/features/.../algo.dart)
#   el test que tiene que fallar   (test/algo_test.dart)
#   el texto a buscar              (un solo renglón, tal cual está en el archivo)
#   el texto que lo reemplaza      (un solo renglón; vacío para borrarlo)
#   ---
#
# Cada caso dice "el test FALLA, como tiene que ser" o
# "ATENCION: el test sigue pasando con la regla rota".
TMP="$(mktemp -d)"

romper() {
  local nombre="$1" archivo="$2" prueba="$3"
  local antes
  antes=$(sha256sum "$archivo" | cut -d' ' -f1)
  cp "$archivo" "$TMP/respaldo.dart"
  BUSCA="$4" PONE="$5" perl -0pi -e 's/\Q$ENV{BUSCA}\E/$ENV{PONE}/' "$archivo"
  if cmp -s "$archivo" "$TMP/respaldo.dart"; then
    echo "[$nombre] NO SE APLICO la rotura (no encontro el texto)"
    return
  fi
  flutter test --reporter=expanded $prueba > "$TMP/rotura.log" 2>&1
  local codigo=$?
  cp "$TMP/respaldo.dart" "$archivo"
  local despues
  despues=$(sha256sum "$archivo" | cut -d' ' -f1)
  local fallaron
  fallaron=$(grep -E "\[E\]$" "$TMP/rotura.log" | sed -E 's/^.*_test\.dart: //; s/ \[E\]$//' | sort -u | head -3 | cut -c1-110 | tr '\n' '|')
  if [ "$codigo" -ne 0 ]; then
    echo "[$nombre] el test FALLA, como tiene que ser -> $fallaron"
  else
    echo "[$nombre] ATENCION: el test sigue pasando con la regla rota"
  fi
  [ "$antes" = "$despues" ] || echo "[$nombre] ATENCION: el archivo no quedo como estaba"
}

mapfile -t L < "$1"
i=0
while [ $i -lt ${#L[@]} ]; do
  romper "${L[$i]}" "${L[$((i+1))]}" "${L[$((i+2))]}" "${L[$((i+3))]}" "${L[$((i+4))]}"
  i=$((i+6))
done
echo "--- como quedo"
git status --short
