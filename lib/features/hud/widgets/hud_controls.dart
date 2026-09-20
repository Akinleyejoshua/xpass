import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/models/assist_models.dart';

/// Compact icon button used across the HUD chrome.
class XpIconButton extends StatefulWidget {
  const XpIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.activeColor = XpColors.accent,
    this.size = 26,
    this.iconSize = 14,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;
  final double size;
  final double iconSize;
  final bool enabled;

  @override
  State<XpIconButton> createState() => _XpIconButtonState();
}

class _XpIconButtonState extends State<XpIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color foreground = !widget.enabled
        ? XpColors.textTertiary
        : widget.active
        ? widget.activeColor
        : _hovered
        ? XpColors.textPrimary
        : XpColors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.active
                  ? XpColors.accentSoft
                  : _hovered
                  ? XpColors.panelRaised
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.active ? XpColors.accent : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Small labelled pill — tier badges, shortcut hints, model names.
class XpChip extends StatelessWidget {
  const XpChip({
    super.key,
    required this.label,
    this.color = XpColors.textSecondary,
    this.background,
    this.borderColor,
    this.icon,
  });

  final String label;
  final Color color;
  final Color? background;
  final Color? borderColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? XpColors.panelRaised,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor ?? XpColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: XpType.label.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Status dot. Pulses while the model is thinking or streaming, so peripheral
/// vision alone tells the user whether an answer is on its way.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.status, this.size = 7});

  final HudStatus status;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _sync();
  }

  void _sync() {
    final bool shouldPulse = switch (widget.status) {
      HudStatus.thinking || HudStatus.streaming || HudStatus.capturing => true,
      _ => false,
    };
    if (shouldPulse) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = statusColor(widget.status);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

Color statusColor(HudStatus status) => switch (status) {
  HudStatus.listening => XpColors.statusLive,
  HudStatus.idle => XpColors.textTertiary,
  HudStatus.capturing ||
  HudStatus.thinking ||
  HudStatus.streaming => XpColors.statusThinking,
  HudStatus.error || HudStatus.muted => XpColors.statusMuted,
};

/// Thin horizontal level meter for one audio source.
class LevelMeter extends StatelessWidget {
  const LevelMeter({
    super.key,
    required this.level,
    required this.active,
    this.width = 26,
  });

  /// Normalised 0...1 RMS.
  final double level;
  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    // RMS of speech sits well under 0.3, so scale before clamping or the meter
    // never leaves the first third of its travel.
    final double normalised = active ? (level * 4.2).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: width,
      height: 3,
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: XpColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          FractionallySizedBox(
            widthFactor: normalised,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                color: active ? XpColors.statusLive : XpColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
