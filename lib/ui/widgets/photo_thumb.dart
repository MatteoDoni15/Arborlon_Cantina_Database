import 'dart:io';

import 'package:flutter/material.dart';

/// Miniatura di una foto salvata localmente (o un segnaposto se assente).
class PhotoThumb extends StatelessWidget {
  final String? path;
  final double size;
  final double radius;

  const PhotoThumb({
    super.key,
    required this.path,
    this.size = 56,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final hasPhoto = path != null && path!.isNotEmpty && File(path!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: hasPhoto
          ? Image.file(File(path!),
              width: size, height: size, fit: BoxFit.cover)
          : Container(
              width: size,
              height: size,
              color: c.primaryContainer,
              child: Icon(Icons.wine_bar, color: c.primary, size: size * 0.5),
            ),
    );
  }
}
