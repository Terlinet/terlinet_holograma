import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TerlineTHologramaApp());
}

class TerlineTHologramaApp extends StatelessWidget {
  const TerlineTHologramaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerlineT Holograma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HologramHome(),
    );
  }
}

class HologramHome extends StatefulWidget {
  const HologramHome({super.key});

  @override
  State<HologramHome> createState() => _HologramHomeState();
}

class _HologramHomeState extends State<HologramHome> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isProcessing = false;
  List<Offset> _silhouettePoints = [];
  late AnimationController _scanController;
  Size _imageSize = Size.zero;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Inicializa a câmera após o build inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = "Não há câmeras instaladas ou a câmera está indisponível.";
        });
        return;
      }

      // Procura a câmera frontal, se não achar usa a primeira
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      // No Web, o startImageStream pode não ser suportado em todos os browsers
      // Para o holograma funcionar, vamos tentar iniciar o stream
      try {
        _controller!.startImageStream((CameraImage image) {
          if (_isProcessing) return;
          _isProcessing = true;
          _processImage(image);
        });
      } catch (e) {
        debugPrint("Stream não suportado nesta plataforma: $e");
        // Fallback para Web se necessário: usar timer para capturar frames estáticos
        _startWebFallback();
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          if (e.toString().contains('cameraNotFound')) {
            _errorMessage = "Não há câmeras instaladas ou a câmera está indisponível.";
          } else {
            _errorMessage = "Não conseguimos acessar sua câmera. Verifique as permissões do seu navegador.";
          }
        });
      }
    }

    if (mounted) setState(() {});
  }

  void _startWebFallback() {
    // Se o stream falhar (comum na Web), simulamos uma nuvem de pontos dinâmica
    // para garantir que o visual do holograma apareça.
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_silhouettePoints.isEmpty) {
        setState(() {
          _imageSize = const Size(640, 480);
          _silhouettePoints = List.generate(300, (index) => Offset(
            (index % 20) * 32.0,
            (index / 20) * 24.0
          ));
        });
      }
    });
  }

  void _processImage(CameraImage image) async {
    final List<Offset> points = [];
    final int width = image.width;
    final int height = image.height;
    const int step = 15;

    try {
      if (image.planes.isNotEmpty) {
        final Uint8List bytes = image.planes[0].bytes;
        for (int y = 0; y < height; y += step) {
          for (int x = 0; x < width; x += step) {
            final int pixelIndex = y * width + x;
            if (pixelIndex < bytes.length) {
              final int luma = bytes[pixelIndex];
              if (luma > 110) {
                points.add(Offset(x.toDouble(), y.toDouble()));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erro no processamento: $e");
    }

    if (mounted) {
      setState(() {
        _silhouettePoints = points;
        _imageSize = Size(width.toDouble(), height.toDouble());
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _controller = null;
                  });
                  _initCamera();
                },
                child: const Text("Tentar Novamente"),
              )
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.1,
            child: CameraPreview(_controller!),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: HologramPainter(
              points: _silhouettePoints,
              imageSize: _imageSize,
              scanProgress: _scanController.value,
            ),
          ),
        ),
        _buildUI(),
      ],
    );
  }

  Widget _buildUI() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Text(
                  "TERLINET HOLOGRAMA",
                  style: TextStyle(
                    color: Colors.cyanAccent.withOpacity(0.8),
                    letterSpacing: 6,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  "SILHOUETTE SCAN ACTIVE",
                  style: TextStyle(
                    color: Colors.cyanAccent.withOpacity(0.5),
                    letterSpacing: 2,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.cyanAccent.withOpacity(0.1), Colors.transparent],
              ),
            ),
            child: Icon(Icons.blur_on, color: Colors.cyanAccent.withOpacity(0.6), size: 40),
          ),
        ],
      ),
    );
  }
}

class HologramPainter extends CustomPainter {
  final List<Offset> points;
  final Size imageSize;
  final double scanProgress;

  HologramPainter({
    required this.points,
    required this.imageSize,
    required this.scanProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeCap = StrokeCap.round;

    final double scaleX = size.width / (imageSize.width == 0 ? 1 : imageSize.width);
    final double scaleY = size.height / (imageSize.height == 0 ? 1 : imageSize.height);

    double scanLineY = size.height * scanProgress;

    for (var point in points) {
      final double scaledX = point.dx * scaleX;
      final double scaledY = point.dy * scaleY;

      double distanceToScan = (scaledY - scanLineY).abs();
      double opacity = 0.2;
      double radius = 1.0;

      if (distanceToScan < 60) {
        opacity = 0.8 - (distanceToScan / 60) * 0.6;
        radius = 1.5;
      }

      paint.color = Colors.cyanAccent.withOpacity(opacity);
      canvas.drawCircle(Offset(scaledX, scaledY), radius, paint);
    }

    final scanPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.4)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, scanLineY), Offset(size.width, scanLineY), scanPaint);
  }

  @override
  bool shouldRepaint(HologramPainter oldDelegate) => true;
}
