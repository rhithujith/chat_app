import 'package:flutter/material.dart';

class CloudBubble extends StatelessWidget {
  final String message;
  final bool isSentByMe;

  const CloudBubble({
    super.key,
    required this.message,
    required this.isSentByMe,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isSentByMe ? 60 : 20,
          right: isSentByMe ? 20 : 60,
          bottom: 40,
        ),
        child: CustomPaint(
          painter: CloudPainter(isSentByMe: isSentByMe),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 30),
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class CloudPainter extends CustomPainter {
  final bool isSentByMe;

  CloudPainter({required this.isSentByMe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isSentByMe ? Colors.deepPurple : Colors.grey.shade600
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Bump radius — controls how big each bump is
    final br = w * 0.13;

    // Each bump is a small circle drawn as an arc
    // We go clockwise around the cloud: top → right → bottom → left

    // Define bump center points around the cloud
    final bumps = [
      // Top row bumps
      Offset(w * 0.25, h * 0.18),
      Offset(w * 0.45, h * 0.08),
      Offset(w * 0.65, h * 0.12),
      Offset(w * 0.82, h * 0.22),

      // Right side bumps
      Offset(w * 0.92, h * 0.42),
      Offset(w * 0.88, h * 0.62),

      // Bottom row bumps
      Offset(w * 0.75, h * 0.82),
      Offset(w * 0.55, h * 0.88),
      Offset(w * 0.35, h * 0.85),

      // Left side bumps
      Offset(w * 0.15, h * 0.72),
      Offset(w * 0.08, h * 0.52),
      Offset(w * 0.12, h * 0.32),
    ];

    // Draw overlapping circles for each bump
    for (final bump in bumps) {
      canvas.drawCircle(bump, br, paint);
    }

    // Fill the center rectangle so no gaps between bumps
    final centerRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.1, h * 0.15, w * 0.9, h * 0.85),
      const Radius.circular(20),
    );
    canvas.drawRRect(centerRect, paint);

    // Draw the sharp arrow tail
    // Draw the curved small arrow tail
    final tailPaint = Paint()
      ..color = isSentByMe ? Colors.deepPurple : Colors.grey.shade600
      ..style = PaintingStyle.fill;

    final tailPath = Path();

    if (isSentByMe) {
      // Small curved arrow at bottom RIGHT
      tailPath.moveTo(w * 0.80, h * 0.90);      // left base of arrow
      tailPath.quadraticBezierTo(
        w * 0.90, h * 0.95,                      // curve control point
        w * 0.98, h + 22,                        // arrow tip (small, close)
      );
      tailPath.quadraticBezierTo(
        w * 0.85, h * 0.95,                      // curve back
        w * 0.72, h * 0.92,                      // right base of arrow
      );
    } else {
      // Small curved arrow at bottom LEFT
      tailPath.moveTo(w * 0.20, h * 0.90);      // right base of arrow
      tailPath.quadraticBezierTo(
        w * 0.10, h * 0.95,                      // curve control point
        w * 0.02, h + 22,                        // arrow tip (small, close)
      );
      tailPath.quadraticBezierTo(
        w * 0.15, h * 0.95,                      // curve back
        w * 0.28, h * 0.92,                      // left base of arrow
      );
    }

    tailPath.close();
    canvas.drawPath(tailPath, tailPaint);
  }

  @override
  bool shouldRepaint(CloudPainter oldDelegate) =>
      oldDelegate.isSentByMe != isSentByMe;
}