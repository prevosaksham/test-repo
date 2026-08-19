import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Six-box OTP entry with auto-advance and backspace-to-previous.
/// Calls [onCompleted] when all boxes are filled and [onChanged] on every edit.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onCompleted,
    this.onChanged,
  });

  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.isNotEmpty && i < widget.length - 1) {
      _nodes[i + 1].requestFocus();
    }
    setState(() {}); // refresh box borders
    widget.onChanged?.call(_value);
    if (_value.length == widget.length && !_value.contains(' ')) {
      widget.onCompleted?.call(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Equal-width square boxes via Expanded + AspectRatio (responsive without a
    // LayoutBuilder — a LayoutBuilder here would break the parent's Intrinsic
    // height measurement and crash the screen).
    return Row(
      spacing: 12,
      children: List.generate(widget.length, (i) {
        final filled = _controllers[i].text.isNotEmpty;
        final focused = _nodes[i].hasFocus;
        return Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _controllers[i].text.isEmpty &&
                    i > 0) {
                  _nodes[i - 1].requestFocus();
                  _controllers[i - 1].clear();
                  setState(() {});
                }
              },
              child: TextField(
                controller: _controllers[i],
                focusNode: _nodes[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.title,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: p.otpBoxBg,
                  hintText: '-',
                  hintStyle: TextStyle(
                    color: p.hint,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  contentPadding: EdgeInsets.zero,
                  enabledBorder:
                      _border(filled ? AppColors.primary : Colors.transparent),
                  focusedBorder: _border(AppColors.primary),
                  border:
                      _border(focused ? AppColors.primary : Colors.transparent),
                ),
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          ),
        );
      }),
    );
  }

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: 1.4),
      );
}
