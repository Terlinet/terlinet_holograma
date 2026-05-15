import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;

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
  late AnimationController _uiController;
  Size _imageSize = Size.zero;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _uiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = "Não há câmeras instaladas ou a câmera está indisponível.");
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await _controller!.initialize();

      _controller!.startImageStream((image) {
        if (_isProcessing) return;
        _isProcessing = true;
        _processImage(image);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Erro de conexão neural: Câmera indisponível.");
      }
    }
  }

  void _processImage(CameraImage image) {
    final List<Offset> points = [];
    final Uint8List bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;
    const int step = 14;

    for (int y = step; y < height - step; y += step) {
      for (int x = step; x < width - step; x += step) {
        final int idx = y * width + x;

        final int current = bytes[idx];
        final int neighbor = bytes[idx + 1];
        final int verticalNeighbor = bytes[idx + width];

        int diff = (current - neighbor).abs() + (current - verticalNeighbor).abs();

        if (diff > 25) {
          points.add(Offset((width - x).toDouble(), y.toDouble()));
        }
      }
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
    _uiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000814),
      body: _buildMainLayer(),
    );
  }

  Widget _buildMainLayer() {
    if (_errorMessage != null) return _buildErrorUI();
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: GridPainter())),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _uiController,
            builder: (context, child) => CustomPaint(
              painter: NeuralHologramPainter(
                points: _silhouettePoints,
                imageSize: _imageSize,
                scanProgress: _uiController.value,
              ),
            ),
          ),
        ),
        _buildHUD(),
      ],
    );
  }

  Widget _buildHUD() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _hudRow("BIOMETRIC_SCAN", "ENABLED", Colors.cyanAccent),
            _hudRow("NEURAL_MESH", "STABLE", Colors.purpleAccent),
            const Spacer(),
            Center(
              child: Text(
                "TERLINET HOLOGRAMA",
                style: TextStyle(
                  color: Colors.cyanAccent.withOpacity(0.6),
                  letterSpacing: 12,
                  fontSize: 14,
                  fontWeight: FontWeight.w100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudRow(String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
          Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildErrorUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, color: Colors.redAccent, size: 40),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _initCamera(),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent)),
            child: const Text("RESET_CONNECTION", style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }
}

class NeuralHologramPainter extends CustomPainter {
  final List<Offset> points;
  final Size imageSize;
  final double scanProgress;

  NeuralHologramPainter({required this.points, required this.imageSize, required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()..strokeCap = StrokeCap.round;
    final linePaint = Paint()..color = Colors.cyanAccent.withOpacity(0.05)..strokeWidth = 0.5;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;
    final double scanY = size.height * scanProgress;

    for (int i = 0; i < points.length; i += 4) {
      final p1 = Offset(points[i].dx * scaleX, points[i].dy * scaleY);
      for (int j = i + 1; j < math.min(i + 5, points.length); j++) {
        final p2 = Offset(points[j].dx * scaleX, points[j].dy * scaleY);
        double distance = (p1 - p2).distance;
        if (distance < 40) {
          canvas.drawLine(p1, p2, linePaint);
        }
      }
    }

    for (var p in points) {
      final pos = Offset(p.dx * scaleX, p.dy * scaleY);
      final distToScan = (pos.dy - scanY).abs();

      if (distToScan < 60) {
        double intensity = 1.0 - (distToScan / 60);
        paint.color = Colors.cyanAccent.withOpacity(0.3 + (0.7 * intensity));
        canvas.drawCircle(pos, 1.5, paint);
      } else {
        paint.color = Colors.cyanAccent.withOpacity(0.2);
        canvas.drawCircle(pos, 1.0, paint);
      }
    }

    final scanRect = Rect.fromLTWH(0, scanY, size.width, 2);
    canvas.drawRect(scanRect, Paint()..color = Colors.cyanAccent.withOpacity(0.2));
  }

  @override
  bool shouldRepaint(NeuralHologramPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent.withOpacity(0.02)..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 50) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
