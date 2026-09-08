import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../services/ai_coding_usage_service.dart';
import '../../services/claude_usage_service.dart';
import '../../services/codex_usage_service.dart';
import '../widgets/custom_tooltip.dart';

class TaskBarAiUsageCarousel extends StatefulWidget {
  const TaskBarAiUsageCarousel({super.key, required this.agents});

  final List<String> agents;

  @override
  State<TaskBarAiUsageCarousel> createState() => _TaskBarAiUsageCarouselState();
}

class _TaskBarAiUsageCarouselState extends State<TaskBarAiUsageCarousel> {
  final PageController _controller = PageController();
  Timer? _clock;
  int _page = 0;
  static const double _lineHeight = 1.3;
  double get _usageFontSize => Design.baseFontSize + 1;

  List<String> get _agents => <String>['codex', 'claude'].where(widget.agents.contains).toList();

  @override
  void initState() {
    super.initState();
    AiCodingUsageService.instance.addListener(_update);
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (QuickMenuFunctions.isQuickMenuVisible) _update();
    });
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TaskBarAiUsageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _agents.length) {
      _page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    AiCodingUsageService.instance.removeListener(_update);
    _clock?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> agents = _agents;
    if (agents.isEmpty) return const SizedBox.shrink();
    final double lineHeight = (MediaQuery.textScalerOf(context).scale(_usageFontSize) * _lineHeight).ceilToDouble();
    // Two usage lines, a header (including its 14px icon), padding, border,
    // header spacing, and a small allowance for pixel rounding.
    final double cardHeight = lineHeight * 2 + lineHeight.clamp(14.0, double.infinity) + 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // if (agents.length > 1)
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.center,
          //   children: List<Widget>.generate(agents.length, (int index) {
          //     return CustomTooltip(
          //       message: 'Show ${agents[index] == 'codex' ? 'Codex' : 'Claude'} usage',
          //       child: InkWell(
          //         borderRadius: BorderRadius.circular(6),
          //         onTap: () => _controller.animateToPage(index,
          //             duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic),
          //         child: Padding(
          //           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          //           child: Text(agents[index] == 'codex' ? 'Codex' : 'Claude',
          //               style: TextStyle(
          //                 fontSize: Design.baseFontSize,
          //                 fontWeight: FontWeight.w600,
          //                 color: _page == index ? Design.accent : Design.text.withAlpha(130),
          //               )),
          //         ),
          //       ),
          //     );
          //   }),
          // ),
          SizedBox(
            height: cardHeight,
            child: PageView.builder(
              controller: _controller,
              itemCount: agents.length,
              onPageChanged: (int page) => setState(() => _page = page),
              itemBuilder: (BuildContext context, int index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _buildProvider(agents[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProvider(String agent) {
    final bool codex = agent == 'codex';
    final CodexUsageRecord? codexRecord = CodexUsageService.instance.latest;
    final ClaudeUsageRecord? claudeRecord = ClaudeUsageService.instance.latest;
    final DateTime? fetchedAt = codex ? codexRecord?.fetchedAt : claudeRecord?.fetchedAt;
    final double? five =
        codex ? codexRecord?.fiveHourRemaining : (claudeRecord == null ? null : 100 - claudeRecord.fiveHour);
    final double? week =
        codex ? codexRecord?.weeklyRemaining : (claudeRecord == null ? null : 100 - claudeRecord.sevenDay);
    final DateTime? fiveReset =
        codex ? codexRecord?.fiveHourResetDateTime : DateTime.tryParse(claudeRecord?.fiveResetAt ?? '');
    final DateTime? weekReset =
        codex ? codexRecord?.weeklyResetDateTime : DateTime.tryParse(claudeRecord?.sevenResetAt ?? '');
    final bool loading =
        codex ? AiCodingUsageService.instance.codexLoading : AiCodingUsageService.instance.claudeLoading;
    final String? error = codex ? CodexUsageService.instance.lastError : ClaudeUsageService.instance.lastError;
    // final bool stale =
    //     fetchedAt != null && (error != null || DateTime.now().difference(fetchedAt) > const Duration(minutes: 5));
    final String name = codex ? 'Codex' : 'Claude';
    // final String status = fetchedAt == null ? (loading ? 'Loading…' : 'Unavailable') : (stale ? 'Cached' : 'Live');
    final TextStyle detail =
        TextStyle(fontSize: Design.baseFontSize, height: _lineHeight, color: Design.text.withAlpha(175));

    return Container(
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (fetchedAt == null)
                    Expanded(
                        child: Center(
                            child: Text(
                      loading
                          ? 'Fetching usage…'
                          : (codex
                              ? 'Install or run codex-cli-usage\nto make usage available.'
                              : 'Sign in to Claude Code\nto make usage available.'),
                      textAlign: TextAlign.center,
                      style: detail,
                    )))
                  else
                    Row(
                      children: <Widget>[
                        CustomTooltip(
                          message: '5h: ${_percent(five)} left',
                          child: SizedBox.square(
                            dimension: MediaQuery.textScalerOf(context).scale(Design.baseFontSize) * 2.6 * 1.3,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: (five ?? 0).clamp(0, 100) / 100),
                                duration: const Duration(milliseconds: 450),
                                builder: (BuildContext context, double value, Widget? child) => Stack(
                                  fit: StackFit.expand,
                                  alignment: Alignment.center,
                                  children: <Widget>[
                                    CircularProgressIndicator(
                                      value: value,
                                      strokeWidth: 3,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor: Design.text.withAlpha(20),
                                      color: Design.accent,
                                      semanticsLabel: '$name 5-hour remaining',
                                      semanticsValue: _percent(five),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _percent(five),
                                          style: TextStyle(
                                            fontSize: Design.baseFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: Design.text,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _usageLine('5h', five, fiveReset, codex ? codexRecord?.fiveHourResetAt : null),
                              _usageLine('Weekly', week, weekReset, codex ? codexRecord?.weeklyResetAt : null),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (fetchedAt != null)
            Positioned(
              top: 0,
              right: 8,
              child: CustomTooltip(
                message:
                    '${error == null ? '' : '$error\n'}Updated ${DateFormat('MMM d, HH:mm').format(fetchedAt.toLocal())}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(codex ? Icons.code_rounded : Icons.auto_awesome_rounded, size: 14, color: Design.accent),
                    const SizedBox(width: 6),
                    Text(name,
                        style: TextStyle(
                            fontSize: Design.baseFontSize - 1,
                            height: _lineHeight,
                            fontWeight: FontWeight.w600,
                            color: Design.text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _percent(double? value) => value == null ? '—' : '${value.clamp(0, 100).round()}%';

  Widget _usageLine(String label, double? remaining, DateTime? reset, String? fallback) {
    final String text = '$label: ${_percent(remaining)} Left ${_reset(reset, fallback)}';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text,
          maxLines: 1,
          style: TextStyle(fontSize: _usageFontSize, height: _lineHeight, color: Design.text.withAlpha(200))),
    );
  }

  String _reset(DateTime? reset, String? fallback) {
    if (reset == null) return fallback == null ? '· reset unavailable' : 'resets at $fallback';
    final DateTime local = reset.toLocal();
    final Duration remaining = local.difference(DateTime.now());
    if (remaining.isNegative) return '· reset passed, awaiting update';
    final int minutes = (remaining.inMilliseconds / Duration.millisecondsPerMinute).ceil();
    final int days = minutes ~/ (24 * 60);
    final int hours = (minutes ~/ 60) % 24;
    final int rest = minutes % 60;
    final String duration = '${days > 0 ? '${days}d' : ''}${hours > 0 ? '${hours}h' : ''}'
        '${rest > 0 || minutes == 0 ? '${rest}m' : ''}';
    return '($duration at ${DateFormat('HH:mm').format(local)})';
  }
}
