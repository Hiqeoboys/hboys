import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../domain/beginner_guide_data.dart';
import '../domain/field_sketch_spec.dart';
import 'widgets/field_sketch_stepper.dart';

/// Halaman Panduan Pemula (100% offline & gratis, 3 Bab, 9 Topik, tanpa kuis/pelacakan progres).
class BeginnerGuidePage extends StatefulWidget {
  const BeginnerGuidePage({super.key, this.initialTopicId});

  final String? initialTopicId;

  @override
  State<BeginnerGuidePage> createState() => _BeginnerGuidePageState();
}

class _BeginnerGuidePageState extends State<BeginnerGuidePage> {
  String _selectedChapterId = 'semua';
  TentType _selectedTentType = TentType.domeCross;
  TentSizeCategory _selectedTentSize = TentSizeCategory.soloDuo1to2;
  String? _expandedTopicId;
  final Map<String, GlobalKey> _topicKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    for (final topic in kBeginnerGuideTopics) {
      _topicKeys[topic.id] = GlobalKey();
    }
    final initial = widget.initialTopicId?.trim();
    if (initial != null &&
        kBeginnerGuideTopics.any((topic) => topic.id == initial)) {
      _expandedTopicId = initial;
    }

    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _topicKeys[initial]?.currentContext;
        if (ctx != null) {
          unawaited(
            Scrollable.ensureVisible(
              ctx,
              duration: HiqeoMotion.screenFade,
              curve: HiqeoMotion.standard,
              alignment: 0.08,
            ),
          );
        }
      });
    }
  }

  List<BeginnerGuideChapter> get _visibleChapters {
    if (_selectedChapterId == 'semua') return kBeginnerChapters;
    return kBeginnerChapters
        .where((c) => c.id == _selectedChapterId)
        .toList(growable: false);
  }

  void _toggleTopic(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _expandedTopicId = _expandedTopicId == id ? null : id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final chapters = _visibleChapters;

    return PageBackground(
      page: AppBackgroundPage.beranda,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Panduan pemula'),
        ),
        body: Column(
          children: <Widget>[
            // Bar filter bab
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _ChapterChip(
                    chipKey: const ValueKey<String>('guide-filter-semua'),
                    label: 'Semua (9 Topik)',
                    active: _selectedChapterId == 'semua',
                    onTap: () => setState(() => _selectedChapterId = 'semua'),
                  ),
                  for (final ch in kBeginnerChapters) ...<Widget>[
                    const SizedBox(width: 8),
                    _ChapterChip(
                      chipKey: ValueKey<String>('guide-filter-${ch.id}'),
                      label: ch.filterLabel,
                      active: _selectedChapterId == ch.id,
                      onTap: () => setState(() => _selectedChapterId = ch.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final chapter in chapters) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              chapter.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chapter.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final topic in kBeginnerGuideTopics
                          .where((t) => t.chapterId == chapter.id)) ...<Widget>[
                        _BeginnerTopicCard(
                          key: _topicKeys[topic.id],
                          topic: topic,
                          expanded: _expandedTopicId == topic.id,
                          onToggle: () => _toggleTopic(topic.id),
                          selectedTentType: _selectedTentType,
                          selectedTentSize: _selectedTentSize,
                          onTentTypeChanged: (t) =>
                              setState(() => _selectedTentType = t),
                          onTentSizeChanged: (s) =>
                              setState(() => _selectedTentSize = s),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                    ],

                    // Pintasan akhir halaman: Siapkan Pendakian & Panduan Keselamatan & Survival
                    Text(
                      'Langkah Berikutnya Sebelum Berangkat',
                      style: HiqeoTypography.overline(colors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    _BottomShortcutCard(
                      cardKey:
                          const ValueKey<String>('beginner-shortcut-siap-naik'),
                      icon: Icons.checklist_rounded,
                      title: 'Siapkan Pendakian',
                      subtitle:
                          'Cek daftar perlengkapan, gunung tujuan, dan kesiapan rombongan.',
                      onTap: () => context.push('/siap-naik'),
                    ),
                    const SizedBox(height: 10),
                    _BottomShortcutCard(
                      cardKey: const ValueKey<String>('beginner-shortcut-safety'),
                      icon: Icons.health_and_safety_outlined,
                      title: 'Panduan Keselamatan & Survival',
                      subtitle:
                          'Pelajari P3K gunung, hipotermia, petir, dan protokol tersesat.',
                      onTap: () => context.push('/p3k'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterChip extends StatelessWidget {
  const _ChapterChip({
    this.chipKey,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final Key? chipKey;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: chipKey,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? colors.primary : colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active ? colors.primary : colors.hairline,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? colors.onPrimary : colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeginnerTopicCard extends StatelessWidget {
  const _BeginnerTopicCard({
    super.key,
    required this.topic,
    required this.expanded,
    required this.onToggle,
    required this.selectedTentType,
    required this.selectedTentSize,
    required this.onTentTypeChanged,
    required this.onTentSizeChanged,
  });

  final BeginnerGuideTopic topic;
  final bool expanded;
  final VoidCallback onToggle;
  final TentType selectedTentType;
  final TentSizeCategory selectedTentSize;
  final ValueChanged<TentType> onTentTypeChanged;
  final ValueChanged<TentSizeCategory> onTentSizeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    final steps = topic.isInteractiveTent
        ? buildTentPitchingSteps(selectedTentType, selectedTentSize)
        : topic.steps;
    final tentSummary = topic.isInteractiveTent
        ? tentSetupSummary(selectedTentType, selectedTentSize)
        : null;

    return HiqeoGlassCard(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: expanded,
            label: topic.title,
            child: InkWell(
              key: ValueKey<String>('beginner-topic-toggle-${topic.id}'),
              borderRadius: BorderRadius.circular(20),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            topic.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            topic.summary,
                            maxLines: expanded ? 4 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      key: ValueKey<String>(
                        'beginner-topic-chevron-${topic.id}',
                      ),
                      turns: expanded ? 0.5 : 0.0,
                      duration: duration,
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (topic.isInteractiveTent &&
                              tentSummary != null) ...<Widget>[
                            _TentConfigSelector(
                              selectedType: selectedTentType,
                              selectedSize: selectedTentSize,
                              summary: tentSummary,
                              onTypeChanged: onTentTypeChanged,
                              onSizeChanged: onTentSizeChanged,
                            ),
                            const SizedBox(height: 12),
                          ],
                          IllustratedStepDeck(
                            key: ValueKey<String>(
                              topic.isInteractiveTent
                                  ? 'deck-${topic.id}-${selectedTentType.name}'
                                  : 'deck-${topic.id}',
                            ),
                            deckKeyPrefix: 'beginner-${topic.id}',
                            sectionTitle: 'Langkah Teknis Bergambar',
                            steps: steps,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TentConfigSelector extends StatelessWidget {
  const _TentConfigSelector({
    required this.selectedType,
    required this.selectedSize,
    required this.summary,
    required this.onTypeChanged,
    required this.onSizeChanged,
  });

  final TentType selectedType;
  final TentSizeCategory selectedSize;
  final TentSetupSummary summary;
  final ValueChanged<TentType> onTypeChanged;
  final ValueChanged<TentSizeCategory> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pilih Jenis Tenda',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final type in TentType.values)
                _ChoicePill(
                  pillKey: ValueKey<String>('tent-type-${type.name}'),
                  label: type.label,
                  selected: type == selectedType,
                  onTap: () => onTypeChanged(type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ukuran / Kapasitas Tenda',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final size in TentSizeCategory.values)
                _ChoicePill(
                  pillKey: ValueKey<String>('tent-size-${size.name}'),
                  label: size.label,
                  selected: size == selectedSize,
                  onTap: () => onSizeChanged(size),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _SpecTag(
                icon: Icons.group_outlined,
                label: summary.crewLabel,
              ),
              _SpecTag(
                icon: Icons.push_pin_outlined,
                label: 'Min. ${summary.stakesLabel}',
              ),
              _SpecTag(
                icon: Icons.straighten_rounded,
                label: summary.guylineLabel,
              ),
              if (summary.ridgePoleNote != null)
                _SpecTag(
                  icon: Icons.architecture_rounded,
                  label: summary.ridgePoleNote!,
                  accent: colors.successText,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    this.pillKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key? pillKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: pillKey,
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? colors.primary : colors.hairline,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? colors.onPrimary : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpecTag extends StatelessWidget {
  const _SpecTag({
    required this.icon,
    required this.label,
    this.accent,
  });

  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final fg = accent ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomShortcutCard extends StatelessWidget {
  const _BottomShortcutCard({
    this.cardKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key? cardKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    return HiqeoGlassCard(
      borderRadius: 20,
      child: Semantics(
        button: true,
        label: title,
        child: InkWell(
          key: cardKey,
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 22, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.2,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
