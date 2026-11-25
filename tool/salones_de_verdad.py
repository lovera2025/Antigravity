# Los salones de los eventos masivos de verdad, **sin nombres**, para probar el
# tótem en la tele con salones de verdad (25-nov-2026): 41 a 151 mesas.
#
#   python -I tool/copiar_base_solo_lectura.py build/copia_salones_tele.db
#   python -I tool/salones_de_verdad.py build/copia_salones_tele.db
#
# Lee la copia en solo lectura y deja build/salones_prueba/salones.json: por
# salón, el armado del plano (mesas, sectores y medidas: nada de personas) y qué
# mesas tiene cada familia (solo los números). Ningún nombre, ningún id.
#
# Lo usan `tool/tele_prueba.dart` (en la PC, y en el APK de prueba: Gradle lo
# copia con JUNIOR_APK_DE_PRUEBA=1) y `tool/tele_salones_de_verdad_test.dart`.
# Va en build/, fuera de git: es del negocio, aunque no tenga nombres.

import json
import re
import sqlite3
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
if len(sys.argv) < 2:
    sys.exit('uso: python -I tool/salones_de_verdad.py <copia de la base>')
copia = Path(sys.argv[1]).resolve()
if copia.name == 'data.db' and copia.parent.name == 'Junior Eventos':
    sys.exit('Esto se corre sobre una copia, nunca sobre la base de la PC.')

c = sqlite3.connect('file:' + copia.as_posix() + '?mode=ro', uri=True)
salones = []
for evento, armado_json in c.execute('select evento_id, armado_json from planos_evento'):
    armado = json.loads(armado_json or '{}')
    if not armado.get('mesas'):
        continue
    familias = []
    for (mesas,) in c.execute(
        "select numero_mesa from contratos_alumnos where evento_id = ? "
        "and coalesce(numero_mesa, '') <> ''",
        (evento,),
    ):
        nums = [int(x) for x in re.findall(r'\d+', mesas)]
        if nums:
            familias.append(nums)
    familias.sort(key=lambda f: f[0])
    salones.append({'armado': armado, 'familias': familias})

salones.sort(key=lambda s: -len(s['armado']['mesas']))
for i, s in enumerate(salones):
    s['nombre'] = f"Masivo {i + 1} · {len(s['armado']['mesas'])} mesas"

salida = Path(__file__).resolve().parent.parent / 'build' / 'salones_prueba' / 'salones.json'
salida.parent.mkdir(parents=True, exist_ok=True)
salida.write_text(json.dumps(salones, ensure_ascii=False), encoding='utf-8')
for s in salones:
    print(s['nombre'], '·', len(s['familias']), 'familias con mesa')
print('en', salida)
