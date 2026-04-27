import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const BalanceWheelApp());
}

class BalanceWheelApp extends StatelessWidget {
  const BalanceWheelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balance Wheel',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

// ── Line / angle state ────────────────────────────────────────────────────────

class LineState {
  Offset p1;
  Offset p2;
  Offset p3;
  double _span;
  double _prevShortSpan;

  LineState({required this.p1, required this.p2, required this.p3})
      : _span = _shortSpan(p1, p2, p3),
        _prevShortSpan = _shortSpan(p1, p2, p3);

  static double _normalize(double a) {
    while (a > 180) { a -= 360; }
    while (a <= -180) { a += 360; }
    return a;
  }

  // Angle (degrees, CCW-positive) from [from] toward [to].
  static double _dirAngle(Offset from, Offset to) =>
      atan2(-(to.dy - from.dy), to.dx - from.dx) * 180 / pi;

  static double _shortSpan(Offset p1, Offset p2, Offset p3) =>
      _normalize(_dirAngle(p2, p3) - _dirAngle(p2, p1));

  void _updateSpan() {
    final newShort = _shortSpan(p1, p2, p3);
    _span += _normalize(newShort - _prevShortSpan);
    _prevShortSpan = newShort;
  }

  void moveP1(Offset pos) {
    p1 = pos;
    _updateSpan();
  }

  void moveP2(Offset pos) {
    p2 = pos;
    _updateSpan();
  }

  void moveP3(Offset pos) {
    p3 = pos;
    _updateSpan();
  }

  double get span => _span;
  int get angleDeg => _span.abs().round();
}

// ── Overlay painter ───────────────────────────────────────────────────────────

class OverlayPainter extends CustomPainter {
  final LineState line;
  const OverlayPainter(this.line);

  @override
  void paint(Canvas canvas, Size size) {
    final segPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final arcPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(line.p1, line.p2, segPaint);
    canvas.drawLine(line.p2, line.p3, segPaint);

    // Arc centered on p2, starting in the direction of p1, spanning _span.
    // Our angles are CCW-positive; Flutter canvas uses CW-positive, so negate.
    final a1Rad = atan2(-(line.p1.dy - line.p2.dy), line.p1.dx - line.p2.dx);
    canvas.drawArc(
      Rect.fromCircle(center: line.p2, radius: 80),
      -a1Rad,
      -line.span * pi / 180,
      false,
      arcPaint,
    );

    canvas.drawCircle(line.p1, 30, Paint()..color = Colors.white);
    canvas.drawCircle(line.p2, 30, Paint()..color = const Color(0xFFA0141E));
    canvas.drawCircle(line.p3, 30, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(OverlayPainter old) => true;
}

// ── Main screen ───────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Assumed frame rate — phone cameras are typically 30 or 60 fps.
  static const _fps = 30.0;

  String? _videoPath;
  int _totalFrames = 0;
  int _frameIndex = 0;
  Uint8List? _frameData;
  bool _loadingFrame = false;
  LineState? _line;
  int? _draggingHandle;

  // ── Video loading ───────────────────────────────────────────────────────────

  Future<void> _pickVideo() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    if (result == null || result.files.isEmpty) return;
    await _openVideo(result.files.first.path!);
  }

  Future<void> _openVideo(String path) async {
    final ctrl = VideoPlayerController.file(File(path));
    await ctrl.initialize();
    final duration = ctrl.value.duration;
    await ctrl.dispose();

    setState(() {
      _videoPath = path;
      _totalFrames = (duration.inMilliseconds * _fps / 1000).round();
      _frameIndex = 0;
      _line = null;
      _frameData = null;
    });
    await _loadFrame(0);
  }

  Future<void> _loadFrame(int index) async {
    if (_videoPath == null || _loadingFrame) return;
    setState(() => _loadingFrame = true);

    final ms = (index * 1000.0 / _fps).round();
    final data = await VideoThumbnail.thumbnailData(
      video: _videoPath!,
      imageFormat: ImageFormat.JPEG,
      timeMs: ms,
      maxWidth: 0,
      maxHeight: 0,
      quality: 95,
    );

    if (mounted) {
      setState(() {
        _frameData = data;
        _frameIndex = index;
        _loadingFrame = false;
      });
    }
  }

  void _prevFrame() {
    if (_frameIndex > 0 && !_loadingFrame) _loadFrame(_frameIndex - 1);
  }

  void _nextFrame() {
    if (_frameIndex < _totalFrames - 1 && !_loadingFrame) {
      _loadFrame(_frameIndex + 1);
    }
  }

  // ── Touch / drag handling ───────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_line == null) return;
    final pos = d.localPosition;
    final handles = [_line!.p1, _line!.p2, _line!.p3];
    double minDist = double.infinity;
    int? nearest;
    for (var i = 0; i < handles.length; i++) {
      final dist = (handles[i] - pos).distance;
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }
    if (minDist < 80) _draggingHandle = nearest;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_line == null || _draggingHandle == null) return;
    final pos = d.localPosition;
    setState(() {
      switch (_draggingHandle!) {
        case 0:
          _line!.moveP1(pos);
        case 1:
          _line!.moveP2(pos);
        case 2:
          _line!.moveP3(pos);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) => _draggingHandle = null;

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_videoPath == null) {
      return Scaffold(
        body: Center(
          child: ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_file),
            label: const Text('Open Video'),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(child: _buildViewer()),
            _buildSidebar(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    return Column(
      children: [
        Expanded(child: _buildCanvas()),
        _buildNavBar(),
      ],
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);

      // Lazily initialise handles once layout size and first frame are known.
      if (_line == null && _frameData != null) {
        Future.microtask(() {
          if (mounted && _line == null) {
            setState(() {
              _line = LineState(
                p1: Offset(size.width * 0.25, size.height * 0.5),
                p2: Offset(size.width * 0.5, size.height * 0.5),
                p3: Offset(size.width * 0.75, size.height * 0.25),
              );
            });
          }
        });
      }

      return GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(fit: StackFit.expand, children: [
          if (_frameData != null)
            Image.memory(_frameData!, fit: BoxFit.contain)
          else
            const Center(child: CircularProgressIndicator()),
          if (_line != null)
            CustomPaint(painter: OverlayPainter(_line!)),
        ]),
      );
    });
  }

  Widget _buildNavBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.chevron_left),
            onPressed: (!_loadingFrame && _frameIndex > 0) ? _prevFrame : null,
          ),
          if (_loadingFrame)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            iconSize: 36,
            icon: const Icon(Icons.chevron_right),
            onPressed: (!_loadingFrame && _frameIndex < _totalFrames - 1)
                ? _nextFrame
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text('Frame: $_frameIndex', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('Angle: ${_line?.angleDeg ?? 0}°',
              style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
