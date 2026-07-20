import 'package:flutter/material.dart';

import '../theme.dart';

/// Icon + text field in a panel — port of iOS `VoltField`. Secure fields get
/// an eye toggle.
class VoltField extends StatefulWidget {
  const VoltField({
    super.key,
    required this.hint,
    required this.icon,
    this.controller,
    this.secure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.enabled = true,
    this.maxLines = 1,
  });

  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final bool secure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final int maxLines;

  @override
  State<VoltField> createState() => _VoltFieldState();
}

class _VoltFieldState extends State<VoltField> {
  late bool _obscured = widget.secure;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: voltPanel(radius: Radii.field),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: widget.maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: widget.maxLines > 1 ? 14 : 0),
            child: Icon(widget.icon, size: 18, color: Palette.textLow),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: _obscured,
              enabled: widget.enabled,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofillHints,
              onSubmitted: widget.onSubmitted,
              maxLines: widget.maxLines,
              style: Typo.body(16, FontWeight.w500),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: Typo.body(16, FontWeight.w400, Palette.textLow),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (widget.secure)
            IconButton(
              onPressed: () => setState(() => _obscured = !_obscured),
              icon: Icon(
                _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: Palette.textLow,
              ),
            ),
        ],
      ),
    );
  }
}
