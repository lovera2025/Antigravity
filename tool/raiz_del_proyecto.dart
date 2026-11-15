// La carpeta del proyecto, para las ventanas de prueba (`tool/*_prueba.dart`).
import 'dart:io';

/// La carpeta del proyecto (la que tiene `pubspec.yaml`). Una ventana de prueba
/// compilada (`flutter build windows -t tool/…`) corre con la carpeta del exe como
/// la actual (`build\windows\x64\runner\Debug`): una ruta relativa como
/// `build/venta_entradas_prueba` caería ahí adentro. Se busca hacia arriba desde la
/// carpeta actual y desde la del exe; si no aparece, la actual.
Directory raizDelProyecto() {
  for (final inicio in [Directory.current, File(Platform.resolvedExecutable).parent]) {
    var d = inicio.absolute;
    for (var i = 0; i < 10; i++) {
      if (File('${d.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) return d;
      final padre = d.parent;
      if (padre.path == d.path) break;
      d = padre;
    }
  }
  return Directory.current;
}

/// Una carpeta adentro de `build/` del proyecto.
Directory carpetaEnBuild(String nombre) {
  final s = Platform.pathSeparator;
  return Directory('${raizDelProyecto().path}${s}build$s$nombre');
}
