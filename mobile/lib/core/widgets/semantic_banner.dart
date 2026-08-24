import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One shared shape for every "here's something worth telling you" strip —
/// a new PR, a plateau warning, rest-timer status. Previously each of these
/// was a one-off Container with its own padding/radius/color choices; this
/// gives them a consistent look while still reading as three different
/// kinds of message via [AppSemanticColors].
class SemanticBanner extends StatelessWidget {
  const SemanticBanner._({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
    this.trailing,
  });

  factory SemanticBanner.success(
    BuildContext context, {
    required String message,
    IconData icon = Icons.emoji_events,
    Widget? trailing,
  }) {
    final semantic = context.semanticColors;
    return SemanticBanner._(
      icon: icon,
      message: message,
      background: semantic.successContainer,
      foreground: semantic.onSuccessContainer,
      trailing: trailing,
    );
  }

  factory SemanticBanner.warning(
    BuildContext context, {
    required String message,
    IconData icon = Icons.trending_flat,
    Widget? trailing,
  }) {
    final semantic = context.semanticColors;
    return SemanticBanner._(
      icon: icon,
      message: message,
      background: semantic.warningContainer,
      foreground: semantic.onWarningContainer,
      trailing: trailing,
    );
  }

  factory SemanticBanner.info(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline,
    Widget? trailing,
  }) {
    final semantic = context.semanticColors;
    return SemanticBanner._(
      icon: icon,
      message: message,
      background: semantic.infoContainer,
      foreground: semantic.onInfoContainer,
      trailing: trailing,
    );
  }

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
