import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/background/app_background.dart';
import '../../../design/background/page_background.dart';
import '../../../design/glass/hiqeo_liquid_glass.dart';
import '../../../design/tokens.dart';
import '../../../design/widgets/hiqeo_back_button.dart';
import '../../../design/widgets/hiqeo_state_view.dart';
import '../../guides/domain/field_sketch_spec.dart';
import '../../guides/presentation/widgets/field_sketch_stepper.dart';
import '../domain/first_aid_data.dart';

/// Halaman Panduan Keselamatan, P3K Gunung, & Wilderness Survival (100% offline,
/// lengkap dengan diagram Technical Field Sketch per langkah dan mode zoom).
class FirstAidGuidePage extends StatefulWidget {
  const FirstAidGuidePage({super.key});

  @override
  State<FirstAidGuidePage> createState() => _FirstAidGuidePageState();
}

class _FirstAidGuidePageState extends State<FirstAidGuidePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _category = 'Semua';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FirstAidTopic> get _filteredTopics {
    final q = _query.trim().toLowerCase();
    return kAllSafetyTopics.where((topic) {
      if (_category != 'Semua' && topic.category != _category) return false;
      if (q.isEmpty) return true;
      return topic.title.toLowerCase().contains(q) ||
          topic.summary.toLowerCase().contains(q) ||
          topic.category.toLowerCase().contains(q) ||
          topic.dangerSigns.any((s) => s.toLowerCase().contains(q)) ||
          topic.firstAidSteps.any((s) => s.toLowerCase().contains(q)) ||
          topic.prohibitionsAndMyths.any((s) => s.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = HiqeoColors.of(context);
    final topics = _filteredTopics;
    final showSectionHeaders = _category == 'Semua' && _query.trim().isEmpty;

    final p3kTopics = topics
        .where((t) => !t.isSurvivalChapter)
        .toList(growable: false);
    final survivalTopics = topics
        .where((t) => t.isSurvivalChapter)
        .toList(growable: false);

    return PageBackground(
      page: AppBackgroundPage.beranda,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const HiqeoBackButton(inAppBar: true),
          leadingWidth: HiqeoBackButton.appBarWidth,
          title: const Text('Panduan keselamatan & survival'),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                key: const ValueKey<String>('p3k-sos-button'),
                onPressed: () => context.push('/sos'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.warningText,
                  backgroundColor: colors.warning.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  minimumSize: const Size(56, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'SOS',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Container(
                height: 46,
                padding: EdgeInsets.only(
                  left: 14,
                  right: _query.isNotEmpty ? 4 : 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: colors.hairline),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('p3k-search-field'),
                        controller: _searchCtrl,
                        maxLength: 80,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          isDense: true,
                          hintText:
                              'Cari gejala, tindakan P3K, atau survival…',
                          hintStyle: TextStyle(
                            fontSize: 13.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      Semantics(
                        button: true,
                        label: 'Hapus pencarian',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Filter Kategori
            SizedBox(
              height: 44,
              child: ListView.separated(
                key: const ValueKey<String>('p3k-category-list'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: kFirstAidCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = kFirstAidCategories[index];
                  final active = cat == _category;
                  return Semantics(
                    button: true,
                    selected: active,
                    label: cat,
                    child: GestureDetector(
                      key: ValueKey<String>('p3k-category-$cat'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _category = cat);
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        child: Center(
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active ? colors.primary : colors.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color:
                                    active ? colors.primary : colors.hairline,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? colors.onPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 6),

            Expanded(
              child: topics.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: HiqeoStateView(
                          icon: Icons.search_off_rounded,
                          title: 'Panduan tidak ditemukan',
                          message:
                              'Tidak ada panduan keselamatan atau survival yang cocok dengan pencarian ini.',
                          actionLabel: 'Hapus pencarian',
                          onAction: () {
                            _searchCtrl.clear();
                            setState(() {
                              _query = '';
                              _category = kFirstAidCategories.first;
                            });
                          },
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        28 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: <Widget>[
                        if (showSectionHeaders) ...<Widget>[
                          _ChapterBanner(
                            title: 'Keselamatan & P3K Lapangan',
                            subtitle:
                                '10 topik kegawatdaruratan medis gunung dengan sketsa tindakan.',
                            colors: colors,
                          ),
                          const SizedBox(height: 10),
                          for (final topic in p3kTopics) ...<Widget>[
                            _FirstAidTopicCard(topic: topic, colors: colors),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 10),
                          _ChapterBanner(
                            title:
                                'Protokol Tersesat & Bertahan Hidup Multi-Hari',
                            subtitle:
                                'Wilderness Survival: STOP, Rule of 3, bivak darurat, air, api, & pangan.',
                            colors: colors,
                            isSurvival: true,
                          ),
                          const SizedBox(height: 10),
                          for (final topic in survivalTopics) ...<Widget>[
                            _FirstAidTopicCard(topic: topic, colors: colors),
                            const SizedBox(height: 10),
                          ],
                        ] else ...<Widget>[
                          for (final topic in topics) ...<Widget>[
                            _FirstAidTopicCard(topic: topic, colors: colors),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterBanner extends StatelessWidget {
  const _ChapterBanner({
    required this.title,
    required this.subtitle,
    required this.colors,
    this.isSurvival = false,
  });

  final String title;
  final String subtitle;
  final HiqeoColors colors;
  final bool isSurvival;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSurvival
            ? colors.primary.withValues(alpha: 0.10)
            : colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSurvival
              ? colors.primary.withValues(alpha: 0.28)
              : colors.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isSurvival
                ? Icons.forest_outlined
                : Icons.medical_services_outlined,
            size: 20,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstAidTopicCard extends StatefulWidget {
  const _FirstAidTopicCard({
    required this.topic,
    required this.colors,
  });

  final FirstAidTopic topic;
  final HiqeoColors colors;

  @override
  State<_FirstAidTopicCard> createState() => _FirstAidTopicCardState();
}

class _FirstAidTopicCardState extends State<_FirstAidTopicCard> {
  bool _expanded = false;

  List<GuideStep> _buildIllustratedSteps() {
    final steps = widget.topic.firstAidSteps;
    final sketches = widget.topic.stepSketches;
    return <GuideStep>[
      for (var i = 0; i < steps.length; i++)
        GuideStep(
          title: 'Langkah ${i + 1}',
          instruction: steps[i],
          sketchId: i < sketches.length
              ? sketches[i]
              : FieldSketchId.p3kStopPlanStayPut,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final colors = widget.colors;
    final hasSketches =
        topic.stepSketches.length == topic.firstAidSteps.length &&
            topic.firstAidSteps.isNotEmpty;

    return HiqeoGlassCard(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _expanded,
            label: topic.title,
            child: InkWell(
              key: ValueKey<String>('p3k-topic-${topic.id}'),
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            topic.category.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: topic.isSurvivalChapter
                                  ? colors.successText
                                  : colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            topic.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            topic.summary,
                            maxLines: _expanded ? 4 : 2,
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
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SectionBlock(
                    title: 'Tanda Bahaya (SOS / Evakuasi Segera)',
                    icon: Icons.warning_amber_rounded,
                    accent: colors.warningText,
                    items: topic.dangerSigns,
                    colors: colors,
                  ),
                  const SizedBox(height: 12),
                  if (hasSketches)
                    IllustratedStepDeck(
                      deckKeyPrefix: 'safety-${topic.id}',
                      sectionTitle: topic.isSurvivalChapter
                          ? 'Protokol Bertahan Hidup'
                          : 'Langkah Pertolongan Pertama',
                      sectionIcon: topic.isSurvivalChapter
                          ? Icons.explore_outlined
                          : Icons.medical_services_outlined,
                      accentColor: colors.primary,
                      steps: _buildIllustratedSteps(),
                    )
                  else
                    _SectionBlock(
                      title: 'Langkah Pertolongan Pertama',
                      icon: Icons.medical_services_outlined,
                      accent: colors.primary,
                      items: topic.firstAidSteps,
                      numbered: true,
                      colors: colors,
                    ),
                  const SizedBox(height: 12),
                  _SectionBlock(
                    title: 'Larangan & Mitos Berbahaya',
                    icon: Icons.do_not_disturb_alt_rounded,
                    accent: colors.warningText,
                    items: topic.prohibitionsAndMyths,
                    colors: colors,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.icon,
    required this.accent,
    required this.items,
    required this.colors,
    this.numbered = false,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<String> items;
  final HiqeoColors colors;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < items.length - 1 ? 6 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    child: Text(
                      numbered ? '${i + 1}.' : '•',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      items[i],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.38,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
