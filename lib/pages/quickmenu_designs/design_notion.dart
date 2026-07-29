import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

class _NotionQuickMenuTokens {
  const _NotionQuickMenuTokens({
    required this.isDark,
    required this.canvas,
    required this.sidebar,
    required this.text,
    required this.dim,
    required this.divider,
    required this.hover,
  });

  factory _NotionQuickMenuTokens.resolve() {
    final bool isDark = Design.background.computeLuminance() < 0.5;
    final Color text = isDark ? const Color(0xFFE6E6E6) : const Color(0xFF37352F);
    return _NotionQuickMenuTokens(
      isDark: isDark,
      canvas: isDark ? const Color(0xFF202020) : const Color(0xFFFFFFFF),
      sidebar: isDark ? const Color(0xFF191919) : const Color(0xFFF7F6F3),
      text: text,
      dim: isDark ? const Color(0xFF9B9B9B) : const Color(0xFF787774),
      divider: text.withAlpha(isDark ? 22 : 18),
      hover: text.withAlpha(isDark ? 16 : 14),
    );
  }

  final bool isDark;
  final Color canvas;
  final Color sidebar;
  final Color text;
  final Color dim;
  final Color divider;
  final Color hover;
}

class MainMenuNotionWidget extends StatelessWidget {
  const MainMenuNotionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _NotionQuickMenuTokens tokens = _NotionQuickMenuTokens.resolve();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tokens.divider),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(tokens.isDark ? 90 : 28),
                blurRadius: 22,
                spreadRadius: -7,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _NotionBreadcrumbBar(tokens: tokens),
                _NotionPageIdentity(tokens: tokens),
                if (!user.quickActionsAtBottom)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.sidebar,
                      border: Border(
                        top: BorderSide(color: tokens.divider),
                        bottom: BorderSide(color: tokens.divider),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(7, 4, 7, 4),
                      child: TopBar(),
                    ),
                  )
                else if (user.bottomBarOnTop)
                  _NotionUtilityBand(tokens: tokens)
                else
                  SizedBox(height: 1, child: ColoredBox(color: tokens.divider)),
                ColoredBox(
                  color: tokens.canvas,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(6, 3, 6, 3),
                    child: TaskBar(),
                  ),
                ),
                if (!user.bottomBarOnTop) _NotionUtilityBand(tokens: tokens),
                if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                if (user.libreStats) const LibreStats(withTopDivider: false),
                _NotionFooter(tokens: tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotionBreadcrumbBar extends StatelessWidget {
  const _NotionBreadcrumbBar({required this.tokens});

  final _NotionQuickMenuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: tokens.canvas,
      child: Row(
        children: <Widget>[
          _NotionMark(tokens: tokens, size: 21),
          const SizedBox(width: 7),
          Text(
            'Tabame',
            style: TextStyle(
              fontFamily: 'Segoe UI Variable Text',
              fontFamilyFallback: const <String>['Segoe UI'],
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w600,
              color: tokens.text,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '/',
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: tokens.dim),
            ),
          ),
          Expanded(
            child: Text(
              'Quick Menu',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Segoe UI Variable Text',
                fontFamilyFallback: const <String>['Segoe UI'],
                fontSize: Design.baseFontSize + 1,
                color: tokens.dim,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.hover,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '•••',
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: tokens.dim,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotionPageIdentity extends StatelessWidget {
  const _NotionPageIdentity({required this.tokens});

  final _NotionQuickMenuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      color: tokens.canvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tokens.divider),
            ),
            child: Icon(Icons.bolt_rounded, size: 19, color: tokens.text),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Quick Menu',
                  style: TextStyle(
                    fontFamily: 'Segoe UI Variable Display',
                    fontFamilyFallback: const <String>['Segoe UI'],
                    fontSize: Design.baseFontSize + 6,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                    height: 1.05,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Open windows, pages and tools',
                  style: TextStyle(
                    fontFamily: 'Segoe UI Variable Text',
                    fontFamilyFallback: const <String>['Segoe UI'],
                    fontSize: Design.baseFontSize,
                    color: tokens.dim,
                    height: 1.1,
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

class _NotionUtilityBand extends StatelessWidget {
  const _NotionUtilityBand({required this.tokens});

  final _NotionQuickMenuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: PinnedAndTrayList(),
      ),
    );
  }
}

class _NotionFooter extends StatelessWidget {
  const _NotionFooter({required this.tokens});

  final _NotionQuickMenuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.keyboard_command_key_rounded, size: 13, color: tokens.dim),
                const SizedBox(width: 5),
                Text(
                  'Workspace',
                  style: TextStyle(
                    fontFamily: 'Segoe UI Variable Text',
                    fontFamilyFallback: const <String>['Segoe UI'],
                    fontSize: Design.baseFontSize - 0.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.dim,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(5, 3, 5, 4),
              child: BottomBar(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotionMark extends StatelessWidget {
  const _NotionMark({required this.tokens, required this.size});

  final _NotionQuickMenuTokens tokens;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: tokens.text.withAlpha(190)),
      ),
      child: Text(
        'N',
        style: TextStyle(
          fontFamily: 'Georgia',
          fontSize: size * 0.64,
          fontWeight: FontWeight.w700,
          color: tokens.text,
          height: 1,
        ),
      ),
    );
  }
}
