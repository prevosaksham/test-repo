import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Shared page chrome for the "More" sub-screens — a white/grey AppBar with a
/// back chevron and a centered bold title (matches the More-section mockups).
class MoreScaffold extends StatelessWidget {
  const MoreScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        backgroundColor: p.cardBg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: p.title),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
      ),
      body: body,
    );
  }
}
