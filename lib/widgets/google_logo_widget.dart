import 'package:flutter/material.dart';

/// Crisp multi-color Google 'G' logo drawn vectorially
class GoogleLogoWidget extends StatelessWidget {
  const GoogleLogoWidget({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Draw Google 4-color arcs
    // Blue arc (right & top-right)
    canvas.drawArc(rect, -0.6, 1.2, false, bluePaint);
    // Green arc (bottom & bottom-right)
    canvas.drawArc(rect, 0.6, 1.3, false, greenPaint);
    // Yellow arc (bottom-left)
    canvas.drawArc(rect, 1.9, 1.2, false, yellowPaint);
    // Red arc (top & top-left)
    canvas.drawArc(rect, 3.1, 1.5, false, redPaint);

    // Horizontal bar for 'G'
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final barRect = Rect.fromLTWH(
      center.dx - size.width * 0.05,
      center.dy - strokeWidth / 2,
      size.width * 0.55,
      strokeWidth,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(strokeWidth * 0.2)),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
