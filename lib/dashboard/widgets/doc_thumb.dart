import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A document thumbnail that may arrive as a URL (new `/application/details`
/// shape) or as inline base64 bytes (legacy). Renders:
///   • [url] via [Image.network] when non-empty,
///   • else [bytes] via [Image.memory],
///   • else (and on a network load error) the [placeholder].
class DocThumbImage extends StatelessWidget {
  const DocThumbImage({
    super.key,
    required this.url,
    required this.bytes,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String url; // http(s) thumbnail url ('' if none)
  final Uint8List? bytes; // base64-decoded bytes (null if none)
  final Widget placeholder; // shown when no image / on load error
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        loadingBuilder: (c, child, prog) => prog == null
            ? child
            : const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, width: width, height: height);
    }
    return placeholder;
  }
}
