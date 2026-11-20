# La huella de la base de esta PC, para comprobar que una ventana de prueba
# (`tool/*_prueba.dart`) no la tocó. NUNCA abre la base con SQLite: abrirla ya
# la puede cambiar. Lee los bytes del archivo y nada más.
#
#   python -I tool/huella_de_la_base.py build/huella_antes.txt
#   python -I tool/huella_de_la_base.py build/huella_antes.txt --solo-version
#   python -I tool/huella_de_la_base.py build/huella_despues.txt --comparar build/huella_antes.txt
#
# Anota, de data.db (y de sus -wal, -shm y -journal si existen): el SHA-256, el
# tamaño, la fecha, la versión (user_version, bytes 60-63 del encabezado) y el
# contador de cambios (bytes 24-27); el SHA-256 de las preferencias del
# programa instalado; y la lista de Documentos\Junior Eventos\PDFs.
#
# Con --comparar termina en "IGUAL" (código 0) o en "CAMBIÓ: ..." (código 1).
# Si el programa instalado está abierto, la base y las preferencias pueden
# cambiar sin culpa de la prueba: lo que decide entonces es la versión.
#
# Con --solo-version solo dice la versión y sale con código 1 si no es la que
# tienen las PCs (VERSION_DE_LAS_PCS).

import ctypes
import hashlib
import json
import os
import subprocess
import sys
from ctypes import wintypes
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

# La versión de la base que tienen las PCs (la de la 6.9.x). La rama va por la
# 81: si la base de esta PC da otra cosa, una prueba la migró.
VERSION_DE_LAS_PCS = 80


def documentos():
    """La carpeta de Documentos, como la busca la app (getApplicationDocumentsDirectory)."""
    try:
        class GUID(ctypes.Structure):
            _fields_ = [('Data1', wintypes.DWORD), ('Data2', wintypes.WORD),
                        ('Data3', wintypes.WORD), ('Data4', ctypes.c_ubyte * 8)]

        # FOLDERID_Documents = {FDD39AD0-238F-46AF-ADB4-6C85480369C7}
        g = GUID(0xFDD39AD0, 0x238F, 0x46AF,
                 (ctypes.c_ubyte * 8)(0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7))
        ruta = ctypes.c_wchar_p()
        if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(g), 0, None,
                                                      ctypes.byref(ruta)) == 0:
            valor = ruta.value
            ctypes.windll.ole32.CoTaskMemFree(ruta)
            if valor:
                return Path(valor)
    except Exception:
        pass
    return Path(os.environ['USERPROFILE']) / 'Documents'


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for trozo in iter(lambda: f.read(1 << 20), b''):
            h.update(trozo)
    return h.hexdigest()


def encabezado(p):
    with open(p, 'rb') as f:
        cabeza = f.read(100)
    if len(cabeza) < 64 or not cabeza.startswith(b'SQLite format 3\x00'):
        return None, None
    return int.from_bytes(cabeza[60:64], 'big'), int.from_bytes(cabeza[24:28], 'big')


def archivo(p):
    st = p.stat()
    return {'sha256': sha(p), 'tamaño': st.st_size, 'fecha': int(st.st_mtime)}


def programa_abierto():
    """Los arguello_events.exe que no corren desde build\\windows (el programa instalado)."""
    try:
        salida = subprocess.run(
            ['powershell', '-NoProfile', '-Command',
             'Get-Process arguello_events -ErrorAction SilentlyContinue | '
             'ForEach-Object { $_.Path }'],
            capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return []
    return [r.strip() for r in salida.splitlines()
            if r.strip() and '\\build\\windows\\' not in r.lower().replace('/', '\\')]


def huella():
    docs = documentos()
    carpeta = docs / 'Junior Eventos'
    base = carpeta / 'data.db'
    h = {'documentos': str(docs), 'base': None, 'extras': {}, 'preferencias': None, 'pdfs': {}}
    if base.exists():
        version, cambios = encabezado(base)
        h['base'] = dict(archivo(base), version=version, cambios=cambios)
    for sufijo in ('-wal', '-shm', '-journal'):
        p = carpeta / ('data.db' + sufijo)
        if p.exists():
            h['extras'][sufijo] = archivo(p)
    prefs = Path(os.environ.get('APPDATA', '')) / 'Junior Eventos' / 'Junior Eventos' / 'shared_preferences.json'
    if prefs.exists():
        h['preferencias'] = archivo(prefs)
    pdfs = carpeta / 'PDFs'
    if pdfs.exists():
        for p in sorted(pdfs.iterdir()):
            if p.is_file():
                st = p.stat()
                h['pdfs'][p.name] = [st.st_size, int(st.st_mtime)]
    return h


def comparar(antes, ahora):
    cambios = []
    a, b = antes['base'], ahora['base']
    if (a is None) != (b is None):
        cambios.append('la base apareció o desapareció')
    elif a is not None:
        if a['version'] != b['version']:
            cambios.append(f"la versión de la base pasó de {a['version']} a {b['version']}")
        if a['sha256'] != b['sha256']:
            cambios.append('la base cambió (SHA-256 distinto)')
        if a['cambios'] != b['cambios']:
            cambios.append(f"el contador de cambios de la base pasó de {a['cambios']} a {b['cambios']}")
    for sufijo in set(antes['extras']) | set(ahora['extras']):
        if antes['extras'].get(sufijo) != ahora['extras'].get(sufijo):
            cambios.append(f'data.db{sufijo} cambió')
    if antes['preferencias'] != ahora['preferencias']:
        cambios.append('las preferencias del programa instalado cambiaron')
    nuevos = sorted(set(ahora['pdfs']) - set(antes['pdfs']))
    tocados = sorted(n for n in set(ahora['pdfs']) & set(antes['pdfs'])
                     if ahora['pdfs'][n] != antes['pdfs'][n])
    if nuevos:
        cambios.append('PDF nuevos en la carpeta del programa: ' + ', '.join(nuevos))
    if tocados:
        cambios.append('PDF cambiados en la carpeta del programa: ' + ', '.join(tocados))
    return cambios


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__ or 'falta el archivo de la huella')
    salida = Path(args[0])
    h = huella()
    base = h['base']
    print('Documentos:', h['documentos'])
    if base is None:
        print('No hay base en esta PC.')
    else:
        print(f"Base: versión {base['version']}, {base['tamaño']} bytes, "
              f"contador {base['cambios']}, sha {base['sha256'][:16]}…")
    abiertos = programa_abierto()
    if abiertos:
        print('OJO: el programa instalado está abierto:', ', '.join(abiertos))
    if '--solo-version' in args:
        if base is None or base['version'] != VERSION_DE_LAS_PCS:
            print(f'CAMBIÓ: la base no está en la versión {VERSION_DE_LAS_PCS}')
            sys.exit(1)
        print(f'IGUAL: la base está en la versión {VERSION_DE_LAS_PCS}')
        return
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(h, ensure_ascii=False, indent=1), encoding='utf-8')
    print('Huella en', salida.resolve())
    if '--comparar' in args:
        antes = json.loads(Path(args[args.index('--comparar') + 1]).read_text(encoding='utf-8'))
        cambios = comparar(antes, h)
        if cambios:
            print('CAMBIÓ: ' + '; '.join(cambios))
            if abiertos:
                print('(el programa instalado está abierto: mirar sobre todo la versión)')
            sys.exit(1)
        print('IGUAL')


if __name__ == '__main__':
    main()
