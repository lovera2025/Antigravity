# Saca una copia de la base de esta PC sin tocarla, para correr los
# comparadores (`tool/rotulo_mora_antes_despues_test.dart` y los que siguen su
# modelo). Abre data.db en solo lectura y la copia con VACUUM INTO; al final
# comprueba que la base real quedó con el mismo SHA-256.
#
#   python -I tool/copiar_base_solo_lectura.py <archivo de la copia>
#
# Con el programa cerrado (se le pide al usuario). La copia lleva datos de
# alumnos: va fuera del repositorio.

import hashlib
import os
import sqlite3
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
src = Path(os.environ['USERPROFILE']) / 'Documents' / 'Junior Eventos' / 'data.db'
dst = Path(sys.argv[1]).resolve()
if dst == src.resolve():
    sys.exit('La copia no puede ser la base real.')
dst.parent.mkdir(parents=True, exist_ok=True)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


antes = sha(src)
if dst.exists():
    dst.unlink()
con = sqlite3.connect(src.as_uri() + '?mode=ro', uri=True)
con.execute('VACUUM INTO ?', (str(dst),))
con.close()
print('la base real quedó igual:', antes == sha(src))
c = sqlite3.connect(dst)
print('versión de la base', c.execute('pragma user_version').fetchone()[0])
print('pagos y el último', c.execute('select count(*), max(fecha_pago) from pagos_contrato_alumno').fetchone())
print('copia en', dst)
