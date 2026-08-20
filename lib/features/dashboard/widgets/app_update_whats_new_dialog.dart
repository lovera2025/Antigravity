import 'package:flutter/material.dart';

/// Aviso breve de novedades: notas del Release, ACEPTAR y sello By L.M.
class AppUpdateWhatsNewDialog extends StatelessWidget {
  const AppUpdateWhatsNewDialog({
    super.key,
    required this.version,
    required this.notes,
    this.showLater = false,
    this.alreadyInstalled = false,
  });

  final String version;
  final String notes;
  final bool showLater;
  final bool alreadyInstalled;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withValues(
          alpha: 0.45,
        );
    return AlertDialog(
      title: Text(
        alreadyInstalled
            ? 'Novedades · $version'
            : 'Hay una versión nueva',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!alreadyInstalled)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Junior Eventos $version',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Text(notes),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'By L.M',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.6,
                color: muted,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (showLater)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('MÁS TARDE'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ACEPTAR'),
        ),
      ],
    );
  }
}
