import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A decoded, validated square source icon.
class SourceIcon {
  SourceIcon(this.path, this.image);
  final String path;
  final img.Image image;
  int get size => image.width;
  bool get hasAlpha => image.hasAlpha && _anyTransparent(image);
}

bool _anyTransparent(img.Image image) {
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}

/// Loads [relativePath] from [projectDir]; returns the icon or an error
/// message.
({SourceIcon? icon, String? error}) loadSourceIcon(
  String projectDir,
  String relativePath,
) {
  final ext = p.extension(relativePath).toLowerCase();
  if (ext == '.svg') {
    return (
      icon: null,
      error:
          '"$relativePath" is SVG. The generator cannot rasterize SVG '
          'reliably; export a square PNG (1024×1024 recommended) and '
          'reference that.',
    );
  }
  final file = File(p.join(projectDir, relativePath));
  if (!file.existsSync()) {
    return (icon: null, error: 'Icon "$relativePath" does not exist.');
  }
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) {
    return (
      icon: null,
      error: '"$relativePath" could not be decoded. Use PNG (or JPEG).',
    );
  }
  if (image.width != image.height) {
    return (
      icon: null,
      error:
          '"$relativePath" is ${image.width}×${image.height}; app icons must '
          'be square. Pad or crop it rather than letting it be stretched.',
    );
  }
  return (icon: SourceIcon(relativePath, image), error: null);
}

/// High-quality downscale. Never upscales: callers check sizes first.
img.Image resize(img.Image source, int size) {
  if (source.width == size) return source.clone();
  return img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
}

/// Composites [source] onto an opaque [hexColor] background.
img.Image flatten(img.Image source, String hexColor) {
  final value = int.parse(hexColor.substring(1), radix: 16);
  final background = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  )..clear(img.ColorRgb8(value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF));
  return img.compositeImage(background, source.convert(numChannels: 4));
}

/// [source] scaled to [contentSize] and centered on a transparent
/// [canvasSize] square (adaptive icon foreground).
img.Image inset(img.Image source, int canvasSize, int contentSize) {
  final canvas = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  final offset = (canvasSize - contentSize) ~/ 2;
  return img.compositeImage(
    canvas,
    resize(source, contentSize).convert(numChannels: 4),
    dstX: offset,
    dstY: offset,
  );
}
