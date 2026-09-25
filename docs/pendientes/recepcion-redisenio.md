# Recepción más amigable, en PC, tablet y celular

**Estado:** pendiente
**Postergado el:** 2026-09-24

## Por qué se postergó

El usuario priorizó el sorteo de noviembre. La Recepción nueva es para las fiestas de diciembre. El diseño se aprobó
con una maqueta interactiva el 24-sep: "más amigable, más profesional, más intuitivo, más cómodo".

## Qué se decidió

**Panel del operador** (`OperadorViewContent` en `recepcion_unified_screen.dart`):

- **Evento:** una tarjeta con nombre, fecha y tipo, que abre el selector.
- **Progreso:** "2 de 5 adentro", con barra y "faltan 3". Reemplaza las tres tarjetas de números (`_buildStats`).
- **Búsqueda grande,** por nombre o por número de mesa. Con **Enter**, si queda un solo pendiente, lo ingresa: es lo
  más rápido en la puerta.
- **Filtros:** Todos, Faltan y Adentro. Quién ya entró se ve acá: el tótem no necesita "Ya llegaron".
- **Botones:** "Agregar" visible, y "Más" (⋯) con Importar lista, Exportar, Actualizar y "Vaciar lista…". Hoy son
  cuatro botones de colores distintos (`_buildActionBar`).
- **Cada invitado:** iniciales, nombre y mesa.
  - Si falta, un botón verde **"Ingresar"**.
  - Si ya entró, "Adentro · 22:41" con deshacer al lado.
  - Editar y eliminar van a un menú ⋮. Hoy el tacho está a la vista en cada fila (`_buildInvitadoCard`) y se toca sin
    querer.
- **"Ya ingresó a las 22:41"**, si se busca a alguien que ya está adentro. Ver
  [totems-vinculados.md](totems-vinculados.md).

**Vista del tótem:**

- Arriba, "Vista del tótem · Neón", con la apariencia del evento.
- **Solo la paleta** (Personalizar), porque la apariencia, la foto, los textos y el color cambian con cada evento.
- **No va "Abrir en el salón"** (decisión del usuario): en la PC el tótem se sigue abriendo desde el tablero, y su
  ventana tiene sus botones.
- **Salen todos los demás botones flotantes** de `_buildTotemWithModeButtons`:
  - los modos panel, pantalla completa y foco (`TotemPanelMode`);
  - cerrar, maximizar y minimizar. Maximizar y minimizar no hacían nada: la ventana del tótem no atiende esos
    mensajes.

**Según la pantalla**, con cortes en un solo lugar: celular menor a 600, tablet de 600 a 1024, PC mayor a 1024. Hoy
están en 800 y 1400 (`_buildLayout`).

- **Celular:** solo la lista para buscar e ingresar, con la paleta arriba, en la barra. Sin vista del tótem
  (decisión del usuario).
- **Tablet:** dos pestañas, Recepción y Tótem.
- **PC:** las dos cosas lado a lado.
- **En celular y tablet,** botones de al menos 44 px.

**Personalizar tótem** (`totem_config_sheet.dart`):

- **Arriba, la apariencia:** cuatro tarjetas con vista previa en vivo y "Ver una llegada". Ver
  [totem-apariencias.md](totem-apariencias.md).
- **Abajo:** foto, textos y color.
- **Cómo se abre:** en PC, como diálogo centrado, con la vista previa grande a la izquierda. En celular y tablet, como
  hoja de abajo a pantalla completa.
- **No va** el QR para "llevar el tótem a otra pantalla": el usuario lo descartó.

## Ojo

Los celulares y tablets usan la app web, porque la de Android nunca se publicó. Lo que cambie en Recepción les llega
**cuando se publique la web**, que es aparte y con OK del usuario.

## Cómo probarlo

- **Tests de widgets** a 360, 800 y 1366 px, sin desbordes:
  - lista sola, pestañas o lado a lado;
  - sobre la vista del tótem, solo la paleta.
- **Tests de la búsqueda:**
  - Enter ingresa solo si queda un pendiente;
  - los filtros;
  - eliminar pide confirmación desde el menú.
- **En la app, sin marcar ingresos**, porque es producción.
