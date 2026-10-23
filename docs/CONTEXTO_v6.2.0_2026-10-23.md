# La 6.2.0 (23-oct-2026): "Tu fondo"

**Publicada el 23-oct** (el SQL, el release y la web), con el OK del usuario: "corre el sql y publica". **Sin
instalar todavía**: las PCs las actualiza él y avisa ("mediante voy y confirmo que todas están actualizadas te lo voy a
decir").

## Qué lleva

**"Tu fondo", la quinta apariencia del tótem.** El jefe carga una imagen y el tótem entero sale de ella: la animación de
la imagen, los efectos que van encima, los tres colores y las letras. Todo el detalle, las decisiones y cómo se prueba
están en `docs/PLAN_TU_FONDO_2026-10-23.md`. El diseño está en Claude Design:
https://claude.ai/artifact/7QwqMNZtr44HMbBrkqJPor.

- Commits `b6368f7` (F1) a `6304dca` (F7), en la rama `feature/totem-tu-fondo`, unida a la principal sin merge
  (avance directo). La versión es `5e8957b`: 6.2.0+60, en `pubspec.yaml` y en el instalador.
- **Tests:** 2.801 pasan. Falla 1, `recepcion_suelta_canal_test` ("sigue emitiendo la lista cuando cambia algo"):
  solo con la PC cargada (base cerrada), y solo pasa 3 de 3. No tiene que ver con el tótem.
- **`flutter analyze`:** 312, los mismos de la 6.1.1; ninguno en lo nuevo.

## La publicación

1. **El SQL (15:13):** `apply_migration` `totem_config_tu_fondo`, con
   `supabase/migrations/20261023120000_totem_config_tu_fondo.sql`: once columnas vacías en `totem_config`.
   - Conteos iguales antes y después: 643 contratos, 4.280 pagos, 27 notas, 11 invitados, 30 eventos y 3 filas de
     `totem_config`.
   - Las 3 filas, con la misma huella (md5 de sus columnas de antes): no se tocó ninguna.
   - Las once columnas con su tipo y vacías; `totem_config` sigue fuera de Realtime.
2. **El instalador:** `installer/dist/Setup Junior Eventos v6.2.0.exe`, 38.130.756 bytes, SHA-256
   `FDBAB245…E9F051F8`. Lleva compilado `shaders/totem_tu_fondo.frag`.
   - **Ojo al armarlo desde acá:** correr `installer\build_installer.ps1` como un proceso aparte (`powershell -File`).
     Con la salida redirigida dentro de PowerShell (`*>`), el aviso "Wasm dry run findings" de Flutter se toma como
     error y corta el script.
3. **El release (15:20):** `tool/publish_windows_release.ps1 -SoloNotas -NotesFile build/novedades_6.2.0.md`.
   - **Las novedades dicen "Nuevas características y detalles"**: lo pidió el usuario.
   - `/releases/latest` da `v6.2.0` (etiqueta en `5e8957b`).
   - El instalador descargado de GitHub tiene el mismo tamaño y el mismo SHA-256 que el armado.
4. **La web (15:23):** `flutter build web --release`, a `.vercel/output/static`, y
   `npx vercel deploy --prebuilt --prod`.
   - Publicada `arguello-events-forbuzmsh`. Para volver atrás, la de antes es `arguello-events-9hkokyqvi` (6.1.0).
   - Comprobado: `version.json` da `6.2.0`/`60`; `/`, `/lista` y `?cotizar` responden; `?cotizar` abre el catálogo;
     el shader nuevo se sirve.

## Con las versiones de antes

- Las PCs con la 6.1.1 (o la 6.0.0) siguen igual. No conocen las columnas nuevas, no las leen y, al guardar
  Personalizar, no las pisan.
- Si un evento tiene "Tu fondo", en esas PCs el tótem muestra la apariencia del tipo.
- **No elegir "Tu fondo" en un evento cuyo tótem se proyecte desde una PC sin la 6.2.0:** se vería la del tipo.

## Falta

1. **Instalar las PCs** (lo hace el usuario y avisa).
2. **La prueba con un evento de verdad, desde una PC con la 6.2.0:**
   - elegir un fondo en Personalizar, guardar, y ver el tótem de la ventana y el de `?totem`;
   - "Lista para trabajar sin internet" y cortar la red.

   Hasta ahora se probó con tests, con las muestras y con el arnés en el navegador.
