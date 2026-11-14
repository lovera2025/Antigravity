# Cruza lo que dio `tool/rotulo_mora_antes_despues_test.dart` en la 6.8.0 y en
# la 6.8.1 sobre la misma copia de la base, y arma el informe que el usuario lee
# antes de publicar (spec del 14-nov, sección 7.2, y Anexo D, sección 5).
#
#   python tool/comparar_rotulo_mora.py <salida>
#
# Lee <salida>/rotulo_mora_6.8.0.json y rotulo_mora_6.8.1.json y escribe
# <salida>/rotulo_mora.txt. Tiene nombres: la carpeta va fuera del repositorio.
# Termina con "FRENA" y código 1 si algo de lo que no puede pasar pasó.

import json
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

ESPERADAS = 5  # fichas que la spec espera que cambien (sección 5)
BOLSA = 'Mora por pagar fuera de término'


def cargar(carpeta, version):
    with open(Path(carpeta) / f'rotulo_mora_{version}.json', encoding='utf-8') as f:
        datos = json.load(f)
    return {c['id']: c for c in datos['contratos']}


def plata(v):
    s = f'{abs(v):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.')
    return ('-' if v < 0 else '') + '$' + s


def cuotas_ficha(f):
    if not f:
        return []
    return [(d['cuota'], round(d['monto'], 2)) for d in f['cuotas']]


def texto_ficha(f):
    if not f:
        return '(sin remanente)'
    return ' · '.join(
        f"C{d['cuota']} {d['mes'].split(' ')[0]} {d['dias']}d {plata(d['monto'])}"
        for d in f['cuotas']
    ) or '(nada atribuido)'


def numeros(texto):
    return sorted({int(n) for n in re.findall(r'cuotas?\s+([\d,\sy]+)', texto or '', re.I)
                   for n in re.findall(r'\d+', n)})


def numeros_arrastre_guardado(concepto):
    t = (concepto or '').replace(' (no cobrada al pagar)', '')
    m = re.search(r'mora pendiente cuotas?\s+([\d,\sy]+)$', t, re.I)
    return sorted({int(n) for n in re.findall(r'\d+', m.group(1))}) if m else []


def numeros_arrastre_del_titulo(titulo):
    t = titulo or ''
    if '+ mora' in t:
        t = t.split('+ mora', 1)[1]
    return sorted({int(n) for n in re.findall(r'cuota (\d+)', t)})


def main():
    carpeta = sys.argv[1]
    antes = cargar(carpeta, '6.8.0')
    despues = cargar(carpeta, '6.8.1')
    frena = []
    out = []
    w = out.append

    w('El rótulo de la mora y el recibo reimpreso: 6.8.0 → 6.8.1, sobre la misma copia de la base')
    w('=' * 96)
    w('')

    # 1. Las fichas.
    cambian = []
    for cid, d in despues.items():
        a = antes.get(cid)
        if a is None:
            frena.append(f'{d["alumno"]}: está en la 6.8.1 y no en la 6.8.0')
            continue
        fa, fd = a['ficha'], d['ficha']
        if (fa is None) != (fd is None):
            frena.append(f'{d["alumno"]}: una versión tiene remanente y la otra no')
            continue
        if fa is None:
            continue
        if abs(fa['suma'] - fd['suma']) > 0.01:
            frena.append(f'{d["alumno"]}: la suma del remanente cambió '
                         f'({plata(fa["suma"])} → {plata(fd["suma"])})')
        if abs(fa['sin_explicar'] - fd['sin_explicar']) > 0.01:
            frena.append(f'{d["alumno"]}: lo que no se explica cambió')
        if cuotas_ficha(fa) != cuotas_ficha(fd):
            cambian.append((d, fa, fd))
    con_remanente = sum(1 for d in despues.values() if d['ficha'])
    w(f'1. LAS FICHAS: {con_remanente} con remanente; cambian {len(cambian)} '
      f'(la spec esperaba {ESPERADAS}). La suma no cambia en ninguna.')
    w('')
    for d, fa, fd in sorted(cambian, key=lambda x: (x[0]['institucion'], x[0]['alumno'])):
        w(f'   {d["alumno"]} ({d["institucion"]}) · remanente {plata(fd["tracked"])}')
        w(f'      hoy:          {texto_ficha(fa)}')
        w(f'      con la 6.8.1: {texto_ficha(fd)}')
    if len(cambian) > ESPERADAS:
        frena.append(f'cambian {len(cambian)} fichas, más que las {ESPERADAS} esperadas: mirar las que sobran')
    w('')

    # 2. Las filas del Estado de cuenta.
    filas_cambian = []
    distintas_de_la_reimpresion = []
    total_arrastre = 0
    for cid, d in despues.items():
        a = antes[cid]
        titulos_antes = {e['id']: e['titulo'] for e in a['estado']}
        cobro_de = {}
        for cobro in d['cobros']:
            for i in cobro['ids']:
                cobro_de[i] = cobro
        for e in d['estado']:
            t_antes = titulos_antes.get(e['id'])
            es_arrastre = re.search(r'no cobrada al pagar|\+ mora pendiente', e['concepto'] or '', re.I)
            if es_arrastre:
                total_arrastre += 1
            if t_antes != e['titulo']:
                filas_cambian.append((d, e, t_antes))
            if not es_arrastre:
                continue
            cobro = cobro_de.get(e['id'])
            if not cobro:
                continue
            moras = [l for l in cobro['lineas'] if l['mora']]
            filas_mora_del_cobro = [x for x in d['estado'] if x['id'] in cobro['ids']]
            if len(filas_mora_del_cobro) != 1:
                continue  # dos filas de mora en un cobro: no se puede atribuir
            reimpresas = sorted({l['previa'] for l in moras if l['previa'] is not None}
                                | {n for l in moras for n in (l.get('previas') or [])})
            del_titulo = numeros_arrastre_del_titulo(e['titulo'])
            if reimpresas and del_titulo and reimpresas != del_titulo:
                distintas_de_la_reimpresion.append((d, e, del_titulo, reimpresas))
    nombran_otras = [x for x in filas_cambian
                     if numeros_arrastre_del_titulo(x[1]['titulo']) != numeros_arrastre_guardado(x[1]['concepto'])]
    w(f'2. EL ESTADO DE CUENTA: {total_arrastre} filas del arrastre. Cambia el título de {len(filas_cambian)} '
      f'(casi todas, solo porque ahora dicen el mes). Nombran otras cuotas que el texto guardado: {len(nombran_otras)}.')
    w('')
    for d, e, t_antes in nombran_otras:
        w(f'   {d["alumno"]} · {e["fecha"][:10]} · {plata(e["monto"])}')
        w(f'      guardado:     {e["concepto"]}')
        w(f'      hoy dice:     {t_antes}')
        w(f'      con la 6.8.1: {e["titulo"]}')
    w('')
    w(f'   El Estado de cuenta y la reimpresión nombran distintas cuotas en {len(distintas_de_la_reimpresion)} filas.')
    for d, e, t, r in distintas_de_la_reimpresion[:40]:
        w(f'      {d["alumno"]} · {e["fecha"][:10]} · {e["concepto"]} · estado {t} · recibo {r}')
    if distintas_de_la_reimpresion:
        frena.append(f'{len(distintas_de_la_reimpresion)} filas nombran en el Estado de cuenta otras cuotas que en el recibo')
    w('')

    # 3. Los recibos reimpresos.
    cobros_total = 0
    no_cierran = []
    bolsa_renglon_antes = 0
    bolsa_cobro_antes = 0
    bolsa_cobro_despues = 0
    verde_cambia = []
    for cid, d in despues.items():
        a = antes[cid]
        cobros_antes = {tuple(sorted(c['ids'])): c for c in a['cobros']}
        for cobro in d['cobros']:
            cobros_total += 1
            if abs(cobro['suma_lineas'] - cobro['suma_filas']) > 0.01:
                no_cierran.append((d, cobro))
            ca = cobros_antes.get(tuple(sorted(cobro['ids'])))
            bolsa_cobro_despues += sum(1 for f in cobro['verde'] if f['rotulo'] == BOLSA)
            if ca:
                bolsa_cobro_antes += sum(1 for f in ca['verde'] if f['rotulo'] == BOLSA)
                for r in ca['renglones']:
                    if r['mora']:
                        bolsa_renglon_antes += sum(1 for f in r['verde'] if f['rotulo'] == BOLSA)
                va = [(f['rotulo'], round(f['monto'], 2)) for f in ca['verde']]
                vd = [(f['rotulo'], round(f['monto'], 2)) for f in cobro['verde']]
                if va != vd:
                    verde_cambia.append((d, cobro, ca))
    w(f'3. LOS RECIBOS REIMPRESOS: {cobros_total} cobros.')
    w(f'   Reimpreso desde el renglón (REIMPRIMIR del Estado de cuenta): en la 6.8.0 la mora caía '
      f'{bolsa_renglon_antes} veces en "{BOLSA}", sin cuota; con la 6.8.1 sale el cobro entero.')
    w(f'   Reimpreso el cobro entero: "{BOLSA}" {bolsa_cobro_antes} veces en la 6.8.0 y {bolsa_cobro_despues} con la 6.8.1.')
    w(f'   Recuadros verdes que cambian (cobro entero): {len(verde_cambia)}.')
    for d, cobro, ca in verde_cambia[:60]:
        w(f'      {d["alumno"]} · {cobro["fecha"][:10]}')
        w(f'         6.8.0: ' + ' · '.join(f"{f['rotulo']} {plata(f['monto'])}" for f in ca['verde']))
        w(f'         6.8.1: ' + ' · '.join(f"{f['rotulo']} {plata(f['monto'])}" for f in cobro['verde']))
    if len(verde_cambia) > 60:
        w(f'      … y {len(verde_cambia) - 60} más')
    # Spec 7.2, último punto: el recibo reimpreso nombra las cuotas del texto
    # guardado no menos veces que hoy (cobros con una sola fila de mora del
    # arrastre).
    def coincidencias(datos):
        si = no = 0
        lista_no = []
        for c in datos.values():
            ids_mora = {e['id']: e for e in c['estado']}
            for cobro in c['cobros']:
                filas = [ids_mora[i] for i in cobro['ids'] if i in ids_mora]
                if len(filas) != 1:
                    continue
                g = numeros_arrastre_guardado(filas[0]['concepto'])
                if not g:
                    continue
                r = sorted({l['previa'] for l in cobro['lineas'] if l['mora'] and l['previa'] is not None}
                           | {n for l in cobro['lineas'] if l['mora'] for n in (l.get('previas') or [])})
                if r == g:
                    si += 1
                else:
                    no += 1
                    lista_no.append((c['alumno'], cobro['fecha'][:10], filas[0]['concepto'], r))
        return si, no, lista_no
    si_a, no_a, _ = coincidencias(antes)
    si_d, no_d, lista_d = coincidencias(despues)
    w(f'   El recibo reimpreso nombra las mismas cuotas del arrastre que el texto guardado: '
      f'{si_a} de {si_a + no_a} en la 6.8.0 y {si_d} de {si_d + no_d} con la 6.8.1.')
    for alumno, fecha, concepto, r in lista_d:
        w(f'      {alumno} · {fecha} · guardado "{concepto}" · recibo {r}')
    if si_d < si_a:
        frena.append('con la 6.8.1 el recibo coincide menos veces con el texto guardado que con la 6.8.0')
    w(f'   Cobros cuyo recibo no suma lo cobrado: {len(no_cierran)}.')
    for d, cobro in no_cierran[:20]:
        w(f'      {d["alumno"]} · {cobro["fecha"][:10]} · filas {plata(cobro["suma_filas"])} · recibo {plata(cobro["suma_lineas"])}')
    if no_cierran:
        frena.append(f'{len(no_cierran)} recibos reimpresos no suman lo cobrado')
    if bolsa_cobro_despues > bolsa_cobro_antes:
        frena.append('con la 6.8.1 hay más mora sin cuota en los recibos que con la 6.8.0')
    w('')

    w('-' * 96)
    if frena:
        w('FRENA:')
        for f in frena:
            w(f'   - {f}')
    else:
        w('Todo en orden: ninguna suma se movió y no apareció nada de lo que frena.')
    texto = '\n'.join(out) + '\n'
    (Path(carpeta) / 'rotulo_mora.txt').write_text(texto, encoding='utf-8')
    print(texto)
    sys.exit(1 if frena else 0)


if __name__ == '__main__':
    main()
