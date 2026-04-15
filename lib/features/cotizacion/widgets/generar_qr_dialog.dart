import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../public_selection_screen.dart';

class GenerarQRDialog extends StatefulWidget {
  const GenerarQRDialog({super.key});

  @override
  State<GenerarQRDialog> createState() => _GenerarQRDialogState();
}

class _GenerarQRDialogState extends State<GenerarQRDialog> {
  bool _isImageLoaded = false;
  final TextEditingController _hostController = TextEditingController(text: "arguello-eventos.web.app");
  String _currentUrl = "https://arguello-eventos.web.app/cotizar";

  @override
  void initState() {
    super.initState();
    _loadLogo();
    _updateUrl();
  }

  void _updateUrl() {
    setState(() {
      var host = _hostController.text.trim();
      
      // Si es una IP local y NO tiene puerto, le clavamos el :8080 de prepo
      final isIp = host.contains(RegExp(r'^[0-1]?[0-9]?[0-9]\.'));
      if (isIp && !host.contains(':')) {
        host = "$host:8080";
      }

      final protocol = (isIp || host.contains('localhost')) ? "http" : "https";
      _currentUrl = "$protocol://$host/cotizar";
    });
  }

  Future<void> _loadLogo() async {
    const String assetPath = 'assets/icons/LOGO-3D-CROMADO-SOLO.png';
    try {
      // Pre-cargamos la imagen para que el decodificador no trabe la UI
      final AssetImage assetImage = const AssetImage(assetPath);
      final ImageStream stream = assetImage.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener((image, synchronousCall) {
        if (mounted) {
          setState(() => _isImageLoaded = true);
        }
      }));
    } catch (e) {
      debugPrint('Error cargando logo para QR: $e');
      if (mounted) setState(() => _isImageLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          Text(
            'QR INTERACTIVO',
            style: GoogleFonts.oswald(letterSpacing: 2, fontWeight: FontWeight.bold),
          ),
          Text(
            'SELECCIÓN DE SERVICIOS',
            style: GoogleFonts.oswald(fontSize: 14, color: const Color(0xFFD4AF37), letterSpacing: 1),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            if (!_isImageLoaded)
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
              )
            else
              Column(
                children: [
                   Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: QrImageView(
                      data: _currentUrl,
                      version: QrVersions.auto,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      size: 200.0,
                      gapless: false,
                      embeddedImage: const AssetImage('assets/icons/LOGO-3D-CROMADO-SOLO.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(
                        size: Size(40, 40),
                      ),
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Input para IP Local
                  TextField(
                    controller: _hostController,
                    onChanged: (_) => _updateUrl(),
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'HOST / IP PARA PRUEBA LOCAL',
                      labelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
                      prefixIcon: const Icon(Icons.lan_outlined, size: 16),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            Text(
              'Escaneá este código desde el celu del cliente para que "entre" a tu oficina digital y elija sus servicios.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  if (!mounted) return;
                  await nav.push(
                    MaterialPageRoute(
                      builder: (_) => const PublicSelectionScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.remove_red_eye_outlined),
                label: const Text('PREVISUALIZAR CATÁLOGO (PROBAR AQUÍ)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => SharePlus.instance.share(ShareParams(text: '¡Hola! Te dejo el link para que elijas los servicios para tu evento en Junior Eventos: $_currentUrl')),
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('COMPARTIR'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('CERRAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
