# Contexto — Junior Eventos v4.7.3 (12 de agosto de 2026)

> **Referencia:** `CONTEXTO_v4.7.3` · `paneles gemelos de MI EMPRESA` · `el [pendiente] que se imprimía` · `el +100% que no medía nada` · `auditoría de mora limpia` · `baja de PERSONAL y CAJA FUERTE`
> Si en un chat futuro decís *"leé el contexto de 4.7.3"*, *"por qué el papel decía pendiente"*,
> *"por qué el puntaje bajó de 85 a 60"*, *"dónde fue la pestaña PERSONAL"* o
> *"por qué la auditoría de mora marca 33 desviados"*, apuntá a este archivo.

**Estado:** código completo, `flutter analyze` sin errores, **330 tests verdes** (eran 289),
build Windows generado y recorrido en la app real.
**Rama:** `feature/v4.6-cierre-por-sesiones`

**Sin migración de base.** No se toca ni una columna ni un dato. Los prefijos de bolsa
siguen guardados igual que antes; lo que cambia es qué se muestra y desde dónde se lee.

---

## Por qué se hizo

En FINANZAS había dos tarjetas: **SALDO DEL NEGOCIO** ($47,2M) y **MI BOLSILLO** ($0). La
de bolsillo abría un panel completo — monto, chips, registrar gasto, historial editable.
La del negocio abría un modal de solo lectura: mirá y salí.

Estaba al revés. La pantalla daba poder sobre la cuenta chica y lo negaba sobre la grande.
Y para pagarle a un operador o cargar un gasto había que irse a otra pestaña.

---

## Auditoría de mora (lo primero que se hizo)

Antes de tocar una línea se corrió `tool/auditoria_mora_masivos_test.dart` contra la base
real. **642 contratos, 9 instituciones:**

| Verificación | Resultado |
|---|---|
| Mora cobrada de más | **0** |
| Mora sobre contratos ya saldados (fantasmas) | **0** |
| Mora sin pagos que la respalden (huérfanas) | **0** |
| Saldos descuadrados contra los pagos | **0** |
| Cuotas pagadas mal contadas | **0** |

**Nadie está pagando de más ni de menos.** Los datos de pago están sanos.

### Los 33 "desviados" son un falso positivo de la herramienta

`reconciliar_mora_masivos_test` marca 33 contratos, y son exactamente los que cobraron
mora **después del 04/08/2026** — el 100% de los posteriores, ninguno de los anteriores.

Dos causas, ninguna es data corrupta:

1. **v4.6.6 habilitó el pago parcial de mora** ese mismo día, y el replay de
   `objetivoDesdeHistorial` no lo modela.
2. **La fecha de alta se movió a mano.** El cronograma se ancla en `created_at` (la cuota
   N vence a fin del mes `alta + N`). En su momento se perdonó mora corriendo esa fecha y
   después se normalizaron casi todas al 30/03/2026. De 639 contratos activos:

   ```
   249 con hora real de creación (11:15:41.213926) →  7 desviados  (2,8%)
   390 con alta redonda 03:00:00.000, o sea a mano → 26 desviados  (6,7%)
   las 390 editadas caen todas el mismo día: 2026-03-30
   ```

   Un alumno que pagó en mayo lo hizo bajo un cronograma que hoy ya no existe, y el replay
   recalcula ese cobro con el alta actual: **compara contra una historia que nunca pasó.**
   La fecha vieja no quedó guardada en ningún lado.

**No correr `APPLY=1`.** Aplicarlo le reclamaría a seis familias mora que ya pagaron —
ZARATE (GUEMEZ DE TEJADA) pagó $38.500 el 06/08 y volvería a deber $18.550.

Para que esto sea auditable haría falta **guardar el desglose de mora aplicado en cada
cobro**, o **perdonar sin tocar el alta** (ya existe `mora_exenta_hasta` para eso, que es
explícito y fechado). Correr el alta logra lo mismo pero deja la contabilidad sin forma de
reconstruirse.

Queda el aviso al tope de la herramienta y `test/mora_offset_pago_parcial_test.dart` con
seis casos de caracterización.

---

## El `[pendiente]` que se imprimía

`[pendiente]` y `[empresa]` son marcas internas en `Egreso.proveedor` que dicen de qué
bolsa salió un gasto personal. `[pendiente]` significa *"ya se pagó, con lo que el dueño
había apartado para sí"* — lo contrario de lo que se lee.

`proveedorGastoPersonalVisible()`, que existe para sacarlas, se llamaba en **2** lugares.
Los otros **12** imprimían el campo crudo, incluidas **4 celdas del cierre de caja
impreso**. En la pantalla de egresos salía en mayúsculas: `[PENDIENTE] SUPERMERCADO`.

La causa de fondo: el origen del gasto se guarda adentro del campo cuyo único trabajo es
que lo lea una persona. Los prefijos pasan al modelo junto con `Egreso.proveedorVisible`,
que devuelve el texto limpio y `null` cuando no queda nada, para que cada pantalla conserve
su propio respaldo.

> **Deuda anotada:** lo correcto de fondo es una columna `origen_gasto` y dejar `proveedor`
> limpio. Es migración sobre producción y merece su propia pasada.

---

## Los dos paneles gemelos

Un solo widget (`panel_movimientos_sheet.dart`) instanciado dos veces.

**SALDO DEL NEGOCIO** — `REGISTRAR GASTO` · `PAGAR OPERADOR`
- Desglose **EN QUÉ SE FUE** por categoría. Medido el 11/08: `Personal $29.505.512,41` ·
  **`Retiro de caja $2.525.500`** · `Impuestos/Servicios $403.000` ·
  `Gasto empresa $269.445,18` · `Aparté para mí $13.232.537,59`.
- `Retiro de caja` lleva su propia nota: *"salió del cajón del turno, no se gastó; hoy
  resta igual"*. **Queda pendiente decidir si tiene que seguir restando del saldo** — ahora
  se sabe que son $2,5M, no una fortuna.
- **LIQUIDACIÓN POR OPERADOR**: 48 operadores · $29.505.512,41, con el detalle de cada pago
  y su edición.

**MI BOLSILLO** — `TRAER DEL NEGOCIO` · `REGISTRAR GASTO`
- La raya visible: *apartaste X y gastaste Y*, y el monto grande es lo que queda.
- Lo que salió directo del negocio se muestra aparte, nunca sumado.

Apartar plata es **una transferencia**: se registra una vez y se ve de los dos lados, con
el rótulo según dónde estés parado.

### La raya del bolsillo ahora frena

`GastoPersonalDialog` ofrecía como máximo el bolsillo **más** todo el saldo del negocio, y
al pasarte partía el gasto solo, sin avisar: apartabas $500.000, cargabas $800.000 y
$300.000 salían de la empresa en silencio. Ahora avisa por cuánto te pasás y hay que
confirmarlo a propósito; sin eso el botón no guarda.

### El calendario

Filtra por día, mes o todo, con los días con movimientos marcados. Compara sobre el día ya
convertido a hora argentina y **no** vía `ArTime.mismoDia`, que aplica el offset a los dos
lados: un gasto de las 22:00 pertenece a su día y no al siguiente. Reemplaza también los 6
chips de meses de arriba, que solo llegaban 6 meses atrás y escondían datos en silencio.

---

## Salud financiera y deuda

### El `+100%` no medía nada

`calcularMesData` leía de `state.ingresos`, que ya viene recortado al mes del filtro. Pedir
el mes anterior era buscar julio en una lista que solo tenía agosto: siempre cero. Y con
`prev.ingresos <= 0` el score escribe `deltaPct = 1.0`. **Nunca comparó dos meses.**

Como el momentum pesa 25 de los 100 puntos, el puntaje venía inflado: **bajó de 85 a 60**,
y eso es lo correcto.

Había dos copias de la función con el mismo error. La segunda alimenta el gráfico de
últimos meses, que mostraba todas las barras en cero salvo la del mes filtrado.

### Escuelas y particulares

El mapa se armaba solo por cliente: un cliente con un masivo y una recepción aparecía en un
renglón con los dos saldos sumados. La clave pasa a ser **cliente + modalidad** y el panel
se parte en dos bloques con su propio subtotal. El total no cambia.

"12 instituciones" era cierto para la mitad — ahora dice `9 escuelas · 4 particulares`. Y
"por vencer" pasa a "con próxima cuota", porque el cálculo corta en la primera.

Las tarjetas de escuela ahora son **tocables** y abren `CarteraEscuelasDialog` posicionado
en esa institución: alumno por alumno con su saldo. Ese diálogo estaba escrito y sin
enganchar a ningún lado.

### Control de datos nuevo

Regla del negocio: **nadie recibe pulseras sin haber pagado todo**, así que un evento
Finalizado con saldo es imposible. La consulta de deuda filtra por Confirmado/Planificacion,
con lo que esos casos quedaban invisibles. Se agrega un aviso aparte — **no entra en TOTAL
EN LA CALLE**, porque no es deuda cobrable sino dato sucio. Si da cero, no se muestra.

---

## Diálogos que estaban escritos y sin enganchar

Tres, y explican por qué "faltaban" funciones que en realidad ya existían:

| Diálogo | Qué hace | Estado antes |
|---|---|---|
| `RetiroBolsilloPersonalDialog` | Único código que crea `Retiro dueño` | Sin botón: el bolsillo solo se podía vaciar |
| `CarteraEscuelasDialog` | Deuda alumno por alumno | Sin botón |
| `RegistrarEgresoGlobalDialog` | Gasto del negocio | Exigía vincular a un evento activo |

El de retiro además traía un selector *"¿Qué tipo de retiro es?"* con la opción "Del
negocio", que no era un retiro sino un gasto de empresa: dos diálogos disfrazados de uno.
Se sacó — quien llega ahí ya eligió, y el gasto del negocio tiene su propio botón con ocho
categorías reales.

---

## Bajas

- **Pestaña PERSONAL.** Leía `state.egresos` (recortado al mes) y decía "SIN PAGOS
  REGISTRADOS" con **67 pagos y $29.505.512,41** detrás — el último fue el 30/06 y el
  filtro mostraba agosto. No estaba al pepe: estaba ciega. Su contenido único, la
  liquidación por operador, vive ahora en el panel del negocio leyendo el histórico.
- **CAJA FUERTE.** Un segundo libro llevado a mano, en su propia tabla y sin relación con
  los egresos, sobre la misma plata que ya informa el saldo del negocio. El modelo, el repo
  y la tabla quedan por si hay datos que rescatar; se retira la UI.
- **`bolsillo_timeline.dart`**, reemplazado por el panel.

Los historiales dejan de consultar la base: el provider ya armaba esa lista para los
totales del HUD y la descartaba.

---

## Qué mirar en la app

Recorrido hecho el 12/08 sobre el build real. Verificado: arranca, 4 pestañas, el selector
de período, el panel del negocio entero, el desglose, la liquidación, el calendario, y que
tocar el día 6 filtra a *"6 de agosto de 2026 · 1 movimiento · $4.000,00"* con la fecha de
la fila coincidiendo.

**Falta probar:** tocar un día **sin** movimientos en el calendario (debería filtrar y decir
"No hubo movimientos el …"), el panel MI BOLSILLO completo, el selector de período
desplegado, y la deuda partida en escuelas/particulares.

---

## Archivos

**Nuevos:** `widgets/panel_movimientos_sheet.dart` · `widgets/calendario_filtro_movimientos.dart`

**Tests nuevos:** `mora_offset_pago_parcial_test` · `egreso_proveedor_visible_test` ·
`calendario_filtro_movimientos_test` · `panel_movimientos_ambito_test` ·
`health_score_comparativa_test` · `deuda_por_modalidad_test`

**Modificados:** `models/egreso.dart` · `mi_empresa/finanzas_view.dart` ·
`mi_empresa/providers/finanzas_provider.dart` · `dashboard/providers/dashboard_provider.dart` ·
`common/services/pdf_service.dart` · `cierre_caja/cierre_caja_screen.dart` ·
`egresos/egresos_screen.dart` · `egresos/widgets/registrar_egreso_global_dialog.dart` ·
`mi_empresa/bolsa_personal_helpers.dart` y los diálogos del bolsillo.

**Borrado:** `mi_empresa/widgets/bolsillo_timeline.dart`
