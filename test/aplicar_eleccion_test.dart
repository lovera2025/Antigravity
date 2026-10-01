// Qué se guarda después de "Estilo y armado": siempre a partir del plano que
// la nube tiene en ese momento.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/aplicar_eleccion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/models/plano_evento.dart';

void main() {
  const evento = 'e0000000-0000-4000-8000-000000000001';
  final antes = DateTime.utc(2026, 10, 1, 12);
  final ahora = DateTime.utc(2026, 10, 2, 9);
  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
  ).armado;
  final pagina3 = ArmadosPredefinidos.normal2aPagina3();

  /// El plano que ya tiene la fiesta, con cosas cargadas a mano.
  PlanoEvento guardado() => PlanoEvento.nuevo(
        eventoId: evento,
        armado: pagina3,
        estilo: EstiloPlano.gala,
        modo: ModoSorteo.entera,
        hechoPor: 'Jefe',
        ahora: antes,
      ).copyWith(
        config: const ConfigPlano(
          fijadas: {10: MesaFijada(alumnoId: 'a', motivo: 'Silla de ruedas')},
          libres: {78: MesaLibre()},
          colores: {'5A': 3},
          titulo: 'Promoción 2026',
          medidas: MedidasPlano(lugarMesaM: 2.2),
        ),
        ahora: antes,
      );

  test('la primera vez es un plano nuevo, con el id fijo de la fiesta', () {
    final r = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: null,
      armado: aMedida,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.bloques,
      hayFamiliasConMesa: false,
      hechoPor: 'Operador',
      ahora: ahora,
    );
    expect(r.conservoArmado, isFalse);
    final p = r.plano;
    expect(p.id, UuidUtils.planoEventoId(evento));
    expect(p.tieneIdFijo, isTrue);
    expect(p.armadoClave, ArmarAMedida.claveArmado);
    expect(p.armado.mesas.length, 132);
    expect(p.estiloPlano, EstiloPlano.arquitecto);
    expect(p.modoSorteo, ModoSorteo.bloques);
    expect(p.hechoPor, 'Operador');
    expect((p.createdAt, p.updatedAt), (ahora, ahora));
    // Las medidas de fábrica no se guardan: quedan las del programa.
    expect(p.config.medidas, const MedidasPlano());
  });

  test('aunque ya haya familias con mesa: es la primera vez del plano', () {
    // Se sorteó sin plano y ahora se arma: no hay armado que conservar.
    final r = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: null,
      armado: pagina3,
      estilo: EstiloPlano.neon,
      modo: ModoSorteo.entera,
      hayFamiliasConMesa: true,
      hechoPor: null,
      ahora: ahora,
    );
    expect(r.conservoArmado, isFalse);
    expect(r.plano.armadoClave, pagina3.clave);
  });

  test('sin familias sentadas se cambia el armado y se conserva lo demás', () {
    final previo = guardado();
    final r = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: previo,
      armado: aMedida,
      estilo: EstiloPlano.neon,
      modo: ModoSorteo.bloques,
      hayFamiliasConMesa: false,
      hechoPor: 'Operador',
      ahora: ahora,
    );
    expect(r.conservoArmado, isFalse);
    final p = r.plano;
    expect(p.id, previo.id);
    expect(p.armadoClave, ArmarAMedida.claveArmado);
    expect(p.estiloPlano, EstiloPlano.neon);
    expect(p.modoSorteo, ModoSorteo.bloques);
    // Lo cargado a mano sigue: fijadas, libres, colores, título y medidas.
    expect(p.config.toJson(), previo.config.toJson());
    expect(p.config.fijadas[10]!.motivo, 'Silla de ruedas');
    expect(p.config.medidas.lugarMesaM, 2.2);
    expect(p.createdAt, antes);
    expect(p.updatedAt, ahora);
    expect(p.hechoPor, 'Operador');
  });

  test('con familias sentadas el armado no se toca; estilo y sorteo, sí', () {
    final previo = guardado();
    final r = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: previo,
      armado: aMedida,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.bloques,
      hayFamiliasConMesa: true,
      hechoPor: 'Operador',
      ahora: ahora,
    );
    expect(r.conservoArmado, isTrue);
    expect(r.plano.armadoClave, pagina3.clave);
    expect(r.plano.armadoJson, previo.armadoJson);
    expect(r.plano.estiloPlano, EstiloPlano.arquitecto);
    expect(r.plano.modoSorteo, ModoSorteo.bloques);
  });

  test('un armado guardado que no se lee se reemplaza aunque haya familias',
      () {
    final roto = PlanoEvento.fromMap(guardado().toMap()..['armado_json'] = '{');
    expect(roto.armadoONull, isNull);
    final r = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: roto,
      armado: pagina3,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.entera,
      hayFamiliasConMesa: true,
      hechoPor: null,
      ahora: ahora,
    );
    expect(r.conservoArmado, isFalse);
    expect(r.plano.armadoONull, isNotNull);
    expect(jsonDecode(r.plano.armadoJson)['clave'], pagina3.clave);
    // Sin nombre nuevo, queda el de quien lo había armado.
    expect(r.plano.hechoPor, 'Jefe');
  });

  test('la fila que sale no deja vacía ninguna columna obligatoria', () {
    final m = aplicarEleccionAlPlano(
      eventoId: evento,
      fresco: null,
      armado: aMedida,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.bloques,
      hayFamiliasConMesa: false,
      hechoPor: null,
      ahora: ahora,
    ).plano.toMap();
    for (final c in const [
      'id', 'evento_id', 'armado', 'armado_json', 'estilo', 'modo_sorteo',
      'config', 'created_at', 'updated_at',
    ]) {
      expect(m[c], isNotNull, reason: c);
    }
  });
}
