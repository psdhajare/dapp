import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dao.dart';
import 'widgets/share_card.dart';

/// Preview the branded share poster in a bottom sheet, then capture it to a PNG
/// and hand it to the platform share sheet.
///
/// Order matters on iOS: the activity sheet must be presented AFTER the preview
/// bottom sheet is dismissed, otherwise iOS silently refuses to present it on
/// top of the modal route (the share sheet "does nothing"). So we capture while
/// the preview is still mounted, pop it, then share from the parent context.
Future<void> shareBestCard(
  BuildContext context, {
  required CardInfo card,
  required String category,
  required String headline,
  required String caption,
}) async {
  final boundaryKey = GlobalKey();
  final rootContext = context; // stable presenter after the sheet closes

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: boundaryKey,
                child: ShareCard(
                  card: card,
                  category: category,
                  headline: headline,
                  caption: caption,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final file = await _capture(boundaryKey);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  if (file != null && rootContext.mounted) {
                    await _share(file, category, rootContext);
                  }
                },
                child: const Text('Share'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<File?> _capture(GlobalKey boundaryKey) async {
  try {
    // Ensure the boundary is painted before we snapshot it.
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/best_card_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  } catch (_) {
    return null;
  }
}

Future<void> _share(File file, String category, BuildContext context) async {
  // sharePositionOrigin is required on iPad and harmless on iPhone.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: 'best_card.png')],
      text: 'My best card for $category — via ToroKard',
      sharePositionOrigin: origin,
    );
  } catch (_) {
    // Platform share failed — nothing more to do.
  }
}
