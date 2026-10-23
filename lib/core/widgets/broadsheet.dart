import 'package:flutter/material.dart';

import '../icons/phosphor.dart';

import '../theme/app_theme.dart';
import 'tag.dart';

/// The Broadsheet page: no app bar, a scroll view that opens with the screen header
/// (kicker, large title, optional subtitle), then [children] with the screen padding.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.kicker,
    this.subtitle,
    this.back,
    this.actions = const [],
    required this.children,
    this.floatingActionButton,
    this.bottomBar,
  });

  final String title;
  final String? kicker;
  final String? subtitle;

  /// Shows a back link above the kicker. Pops the route when it has no handler.
  final BackLink? back;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? floatingActionButton;

  /// Pinned below the scroll view, for example a composer.
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  0,
                  AppSpace.screen,
                  AppSpace.xxl + 40,
                ),
                children: [
                  ScreenHeader(
                    title: title,
                    kicker: kicker,
                    subtitle: subtitle,
                    back: back,
                    actions: actions,
                    padded: false,
                  ),
                  ...children,
                ],
              ),
            ),
            ?bottomBar,
          ],
        ),
      ),
    );
  }
}

/// Kicker above a large serif title, an optional muted subtitle, and actions at the
/// right of the kicker line. [padded] adds the screen's horizontal padding.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.kicker,
    this.subtitle,
    this.back,
    this.actions = const [],
    this.padded = true,
  });

  final String title;
  final String? kicker;
  final String? subtitle;
  final BackLink? back;
  final List<Widget> actions;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padded ? AppSpace.screen : 0,
        back == null ? AppSpace.l : AppSpace.xs,
        padded ? AppSpace.screen : 0,
        AppSpace.l + 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?back,
          // The kicker line holds the actions too; it takes no space when both are absent.
          if (kicker != null || actions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpace.minTap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Kicker(kicker ?? ''),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          Text(title, style: AppText.screenTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: AppText.meta.copyWith(fontSize: 15)),
          ],
        ],
      ),
    );
  }
}

/// Small uppercase label in accent700, set above titles and section headings.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppText.kicker.copyWith(color: color),
  );
}

/// Back navigation: an accent text button with a caret. Pops the route by default.
class BackLink extends StatelessWidget {
  const BackLink({super.key, this.label = 'Back', this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(-10, 0),
      child: TextButton.icon(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// Section heading (20, w600) with optional actions at the right. Adds the space
/// that separates it from the section above unless [first].
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.text, {
    super.key,
    this.kicker,
    this.trailing,
    this.first = false,
  });

  final String text;
  final String? kicker;
  final Widget? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppSpace.section, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null) ...[
                  Kicker(kicker!),
                  const SizedBox(height: 4),
                ],
                Text(text, style: AppText.sectionHeading),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// An open list row: no card, border, or divider. Title (18, w600) with an optional
/// trailing widget (usually a [Tag]), then muted meta lines and optional extra content.
class OpenRow extends StatelessWidget {
  const OpenRow({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.meta,
    this.below,
    this.onTap,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  /// Muted 13px line (or lines) under the title.
  final String? meta;

  /// Extra content under the meta line, such as readiness tags.
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpace.minTap),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.row / 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(padding: const EdgeInsets.only(top: 2), child: leading),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(title, style: AppText.rowTitle)),
                      if (trailing != null) ...[
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: trailing,
                        ),
                      ],
                    ],
                  ),
                  if (meta != null && meta!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta!, style: AppText.meta),
                  ],
                  if (below != null) ...[const SizedBox(height: 8), below!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: AppRadius.all, child: content);
  }
}

/// A large serif numeral with a muted label beneath. [alert] sets the value in accent2.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.value,
    required this.label,
    this.alert = false,
    this.onTap,
  });

  final String value;
  final String label;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: AppText.numeral.copyWith(
              color: alert ? AppColors.accent2 : AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppText.meta),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: AppRadius.all, child: content);
  }
}

/// Metrics in a two-column grid, no boxes.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.metrics});

  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) =>
      MetricGridLayout(rowGap: AppSpace.l, children: metrics);
}

/// The 5px progress and readiness bar. The fill is accent at 80% and over, accent2
/// under 50%, and neutral600 in between, unless [tone] sets it.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.tone});

  /// 0 to 1.
  final double value;
  final Tone? tone;

  static Tone toneFor(double value) => value >= 0.8
      ? Tone.accent
      : value < 0.5
      ? Tone.alert
      : Tone.neutral;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: AppRadius.all,
      child: SizedBox(
        height: 5,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.neutral300,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              heightFactor: 1,
              child: ColoredBox(color: (tone ?? toneFor(v)).fill),
            ),
          ),
        ),
      ),
    );
  }
}

/// A two-column label and value grid: muted label above each value.
class FactGrid extends StatelessWidget {
  const FactGrid({super.key, required this.facts});

  final List<(String label, String value)> facts;

  @override
  Widget build(BuildContext context) {
    return MetricGridLayout(
      children: [
        for (final (label, value) in facts)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.meta),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}

/// Lays children out two per row with the standard gutters.
class MetricGridLayout extends StatelessWidget {
  const MetricGridLayout({super.key, required this.children, this.rowGap = 14});

  final List<Widget> children;
  final double rowGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : rowGap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: AppSpace.l),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A muted one-line message for empty lists.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
    child: Text(text, style: AppText.meta.copyWith(fontSize: 15)),
  );
}
