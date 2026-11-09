// La misma ventana de prueba de la barra (`tool/barra_prueba.dart`: la cajera a la
// izquierda, el jefe a la derecha, sobre la misma barra en memoria), **para el navegador**:
// los papeles se ven como texto (PAPEL, arriba), sin impresora. Sirve para recorrerla con
// el navegador de la app cuando no se puede manejar la ventana de Windows.
//
//   flutter build web -t tool/barra_prueba_web.dart --no-web-resources-cdn --output build/barra_prueba_web
//   python -I -m http.server 8793 --directory build/barra_prueba_web
//
// Entre los PIN está Romi 7777, la Encargada de barra (6.4.0): vende con su caja y además
// ve LAS CAJAS y anula cualquier venta, con motivo.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'barra_prueba.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  runApp(PruebaDeLaBarra(armarLados(papelEnPantalla: true)));
}
