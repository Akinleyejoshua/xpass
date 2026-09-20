import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';

/// A titled group of settings rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: XpType.sectionHeading),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(subtitle!, style: XpType.bodyMuted.copyWith(fontSize: 11.5)),
          ],
          const SizedBox(height: 9),
          Container(
            decoration: BoxDecoration(
              color: XpColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: XpColors.border),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: XpColors.border,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + hint on the left, control on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.controlWidth = 190,
  });

  final String label;
  final String? hint;
  final Widget child;
  final double controlWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: XpType.body.copyWith(fontSize: 12.5)),
                if (hint != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: XpType.bodyMuted.copyWith(
                      fontSize: 11,
                      color: XpColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: controlWidth, child: child),
        ],
      ),
    );
  }
}

/// Full-width stacked row, for long text fields.
class SettingsStack extends StatelessWidget {
  const SettingsStack({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(label, style: XpType.body.copyWith(fontSize: 12.5)),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: XpType.bodyMuted.copyWith(
                fontSize: 11,
                color: XpColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

/// Text input styled for the HUD.
class XpTextField extends StatefulWidget {
  const XpTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.obscure = false,
    this.maxLines = 1,
    this.monospace = false,
    this.onTap,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final bool obscure;
  final int maxLines;
  final bool monospace;
  final VoidCallback? onTap;

  @override
  State<XpTextField> createState() => _XpTextFieldState();
}

class _XpTextFieldState extends State<XpTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  bool _revealed = false;

  @override
  void didUpdateWidget(XpTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt external changes (an import, a reset) without fighting the cursor
    // while the user is mid-edit.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hide = widget.obscure && !_revealed;

    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      onTap: widget.onTap,
      obscureText: hide,
      obscuringCharacter: '•',
      maxLines: hide ? 1 : widget.maxLines,
      minLines: 1,
      style: (widget.monospace ? XpType.code : XpType.body).copyWith(
        fontSize: 12,
      ),
      cursorColor: XpColors.accent,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: XpColors.panelRaised,
        hintText: widget.hintText,
        hintStyle: XpType.body.copyWith(
          fontSize: 12,
          color: XpColors.textTertiary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        border: _border(XpColors.border),
        enabledBorder: _border(XpColors.border),
        focusedBorder: _border(XpColors.accent),
        suffixIcon: widget.obscure
            ? IconButton(
                icon: Icon(
                  _revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 13,
                  color: XpColors.textSecondary,
                ),
                splashRadius: 12,
                onPressed: () => setState(() => _revealed = !_revealed),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 30,
          minHeight: 24,
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: color),
  );
}

/// Dropdown styled for the HUD.
class XpDropdown<T> extends StatelessWidget {
  const XpDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelOf,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: XpColors.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: XpColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          isDense: true,
          dropdownColor: XpColors.panelRaised,
          borderRadius: BorderRadius.circular(8),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 15,
            color: XpColors.textSecondary,
          ),
          style: XpType.body.copyWith(fontSize: 12),
          onChanged: (T? next) {
            if (next != null) onChanged(next);
          },
          items: <DropdownMenuItem<T>>[
            for (final T item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  labelOf(item),
                  style: XpType.body.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact switch.
class XpSwitch extends StatelessWidget {
  const XpSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Transform.scale(
        scale: 0.72,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: XpColors.accent,
          inactiveThumbColor: XpColors.textSecondary,
          inactiveTrackColor: XpColors.panelRaised,
          trackOutlineColor: const WidgetStatePropertyAll<Color>(
            XpColors.border,
          ),
        ),
      ),
    );
  }
}

/// Slider with an inline numeric readout.
class XpSlider extends StatelessWidget {
  const XpSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.format,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: XpColors.accent,
              inactiveTrackColor: XpColors.border,
              thumbColor: Colors.white,
              overlayColor: XpColors.accentSoft,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            format(value),
            style: XpType.metric.copyWith(color: XpColors.textPrimary),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Small filled button.
class XpButton extends StatelessWidget {
  const XpButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.busy = false,
    this.tone = XpColors.accent,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool busy;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: tone,
          disabledBackgroundColor: tone.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 13),
            const SizedBox(width: 6),
            Text(
              label,
              style: XpType.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
