import 'package:flutter/material.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/l10n/l10n.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui';

class DashboardView extends StatefulWidget {
  final SduiComponentModel component;

  const DashboardView({super.key, required this.component});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  // Track which bar series are hidden (0=IN, 1=OUT, 2=CACHE)
  final Set<int> _hiddenBarSeries = {};

  bool _isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  @override
  Widget build(BuildContext context) {
    final sections = widget.component.props['sections'] as List<dynamic>? ?? [];

    if (_isMobile(context)) {
      return _buildMobileLayout(context, sections);
    } else {
      return _buildDesktopLayout(context, sections);
    }
  }

  /// 移动端：极简布局，无外框，标题由外层 AppBar 提供
  Widget _buildMobileLayout(BuildContext context, List<dynamic> sections) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: sections.map<Widget>((section) {
          return _buildSection(context, section as Map<String, dynamic>);
        }).toList(),
      ),
    );
  }

  /// 桌面端：无外框，简洁标题，保留完整数据展示
  Widget _buildDesktopLayout(BuildContext context, List<dynamic> sections) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Text(
              context.l10n.navDashboard,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections.map<Widget>((section) {
                return _buildSection(context, section as Map<String, dynamic>);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, Map<String, dynamic> sectionData) {
    final title = sectionData['title'] as String? ?? '';
    final type = sectionData['type'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: _isMobile(context) ? 20.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  letterSpacing: 1.5,
                ),
              ),
            ),
          _buildContent(context, type, sectionData),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String type,
    Map<String, dynamic> data,
  ) {
    switch (type) {
      case 'status_cards':
        return _buildStatusCards(
          context,
          data['items'] as List<dynamic>? ?? [],
        );
      case 'stats_grid':
        return _buildStatsGrid(context, data['items'] as List<dynamic>? ?? []);
      case 'line_chart':
        return _buildLineChart(context, data['data'] as List<dynamic>? ?? []);
      case 'bar_chart':
        return _buildBarChart(context, data['data'] as List<dynamic>? ?? []);
      case 'table':
        return _buildTable(context, data);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Glass-morphism card wrapper
  Widget _glassCard(
    BuildContext context, {
    required Widget child,
    EdgeInsets? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildStatusCards(BuildContext context, List<dynamic> items) {
    final colorScheme = Theme.of(context).colorScheme;
    final mobile = _isMobile(context);

    return _glassCard(
      context,
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 10 : 14,
        vertical: 10,
      ),
      child: Row(
        mainAxisAlignment: mobile
            ? MainAxisAlignment.start
            : MainAxisAlignment.spaceAround,
        children: items.map((item) {
          final map = item as Map<String, dynamic>;
          final label = map['label'] as String? ?? '';
          final value = map['value'] as String? ?? '';
          final status = map['status'] as String? ?? 'ok';
          final isError = status == 'error';
          final displayText = mobile ? value : '$label: $value';

          return Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isError ? colorScheme.error : const Color(0xFF22C55E),
                    boxShadow: [
                      BoxShadow(
                        color: (isError
                                ? colorScheme.error
                                : const Color(0xFF22C55E))
                            .withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    displayText,
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                      fontWeight: FontWeight.w500,
                      color: isError
                          ? colorScheme.error
                          : colorScheme.onSurface.withOpacity(0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, List<dynamic> items) {
    final colorScheme = Theme.of(context).colorScheme;

    // Separate items with subtexts (token cards) and simple items
    final tokenCards = <Map<String, dynamic>>[];
    final simpleCards = <Map<String, dynamic>>[];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      if (map['subtext'] != null) {
        tokenCards.add(map);
      } else {
        simpleCards.add(map);
      }
    }

    return Column(
      children: [
        // Token cards: 2-column layout with detail rows
        if (tokenCards.isNotEmpty)
          Row(
            children: tokenCards.map((map) {
              final label = map['label'] as String? ?? '';
              final value = map['value'] as String? ?? '';
              final subtext = map['subtext'] as String? ?? '';
              final details = _parseSubtext(subtext);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: tokenCards.last == map ? 0 : 10,
                  ),
                  child: _glassCard(
                    context,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.headlineSmall!.fontSize,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                            color: colorScheme.onSurfaceVariant.withOpacity(
                              0.6,
                            ),
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: colorScheme.onSurface.withOpacity(
                                    0.04,
                                  ),
                                ),
                              ),
                            ),
                            child: Wrap(
                              spacing: 20,
                              runSpacing: 6,
                              children: details.entries.map((e) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      e.key,
                                      style: TextStyle(
                                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                                        color: colorScheme.onSurfaceVariant
                                            .withOpacity(0.4),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      e.value,
                                      style: TextStyle(
                                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

        if (tokenCards.isNotEmpty && simpleCards.isNotEmpty)
          const SizedBox(height: 10),

        // Simple cards: row layout
        if (simpleCards.isNotEmpty)
          Row(
            children: simpleCards.map((map) {
              final label = map['label'] as String? ?? '';
              final value = map['value'] as String? ?? '';

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: simpleCards.last == map ? 0 : 10,
                  ),
                  child: _glassCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.headlineSmall!.fontSize,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                            color: colorScheme.onSurfaceVariant.withOpacity(
                              0.6,
                            ),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  /// Parse subtext "3.0k in / 1.4k out · Cache: 300" into labeled map
  Map<String, String> _parseSubtext(String subtext) {
    if (subtext.isEmpty) return {};

    final result = <String, String>{};
    // Pattern: "3.0k in / 1.4k out · Cache: 300"
    // or:      "44 in / 50 out · 2026-03-10"
    final parts = subtext.split('·').map((s) => s.trim()).toList();

    if (parts.isNotEmpty) {
      final ioParts = parts[0].split('/').map((s) => s.trim()).toList();
      for (final io in ioParts) {
        if (io.toLowerCase().contains('in')) {
          result['IN'] = io
              .replaceAll(RegExp(r'\s*in\s*', caseSensitive: false), '')
              .trim();
        } else if (io.toLowerCase().contains('out')) {
          result['OUT'] = io
              .replaceAll(RegExp(r'\s*out\s*', caseSensitive: false), '')
              .trim();
        }
      }
    }

    if (parts.length > 1) {
      final extra = parts[1].trim();
      if (extra.toLowerCase().startsWith('cache')) {
        result['CACHE'] = extra
            .replaceAll(RegExp(r'cache[:\s]*', caseSensitive: false), '')
            .trim();
      } else {
        result['DATE'] = extra;
      }
    }

    return result;
  }

  Widget _buildLineChart(BuildContext context, List<dynamic> dataPoints) {
    final colorScheme = Theme.of(context).colorScheme;

    if (dataPoints.isEmpty) {
      return _glassCard(
        context,
        child: const Center(child: Text('No data yet')),
      );
    }

    final spots = <FlSpot>[];
    final labels = <String>[];
    for (int i = 0; i < dataPoints.length; i++) {
      final point = dataPoints[i] as Map<String, dynamic>;
      spots.add(FlSpot(i.toDouble(), (point['tokens'] as num).toDouble()));
      labels.add(point['hour'] as String? ?? '');
    }

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final ceilY = maxY < 100 ? 100.0 : (maxY * 1.2);

    return _glassCard(
      context,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: ceilY / 4,
              getDrawingHorizontalLine: (value) => FlLine(
                color: colorScheme.onSurface.withOpacity(0.05),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: ceilY / 4,
                  getTitlesWidget: (value, meta) {
                    if (value == 0) return const SizedBox.shrink();
                    final text = value >= 1000
                        ? '${(value / 1000).toStringAsFixed(1)}k'
                        : value.toInt().toString();
                    return Text(
                      text,
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    // Show label every 6 hours
                    if (idx % 6 != 0 || idx >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        labels[idx],
                        style: TextStyle(
                          fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (spots.length - 1).toDouble(),
            minY: 0,
            maxY: ceilY,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final idx = spot.x.toInt();
                    final hour = idx < labels.length ? labels[idx] : '';
                    return LineTooltipItem(
                      '$hour\n${spot.y.toInt()} tokens',
                      TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                        fontFamily: 'monospace',
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.3,
                color: colorScheme.primary,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.primary.withOpacity(0.2),
                      colorScheme.primary.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(BuildContext context, List<dynamic> dataPoints) {
    final colorScheme = Theme.of(context).colorScheme;

    if (dataPoints.isEmpty) {
      return _glassCard(
        context,
        child: const Center(child: Text('No data yet')),
      );
    }

    final dates = <String>[];
    final barGroups = <BarChartGroupData>[];
    double maxVal = 100;

    for (int i = 0; i < dataPoints.length; i++) {
      final point = dataPoints[i] as Map<String, dynamic>;
      final input = (point['input'] as num?)?.toDouble() ?? 0;
      final output = (point['output'] as num?)?.toDouble() ?? 0;
      final cache = (point['cache'] as num?)?.toDouble() ?? 0;
      final date = point['date'] as String? ?? '';
      dates.add(date);

      if (input > maxVal && !_hiddenBarSeries.contains(0)) maxVal = input;
      if (output > maxVal && !_hiddenBarSeries.contains(1)) maxVal = output;
      if (cache > maxVal && !_hiddenBarSeries.contains(2)) maxVal = cache;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: _hiddenBarSeries.contains(0) ? 0 : input,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF93C5FD), Color(0xFF3B82F6)],
              ),
              width: 6,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 0,
                color: const Color(0xFF3B82F6).withOpacity(0.06),
              ),
            ),
            BarChartRodData(
              toY: _hiddenBarSeries.contains(1) ? 0 : output,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6EE7B7), Color(0xFF10B981)],
              ),
              width: 6,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 0,
                color: const Color(0xFF10B981).withOpacity(0.06),
              ),
            ),
            BarChartRodData(
              toY: _hiddenBarSeries.contains(2) ? 0 : cache,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF67E8F9).withOpacity(0.7),
                  const Color(0xFF06B6D4).withOpacity(0.4),
                ],
              ),
              width: 6,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 0,
                color: const Color(0xFF06B6D4).withOpacity(0.04),
              ),
            ),
          ],
        ),
      );
    }

    final ceilY = maxVal * 1.15;

    String fmtY(double value) {
      if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
      if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}k';
      return value.toInt().toString();
    }

    return _glassCard(
      context,
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Wrap(
            spacing: 16,
            children: [
              _legendToggle(0, 'IN', const Color(0xFF93C5FD)),
              _legendToggle(1, 'OUT', const Color(0xFF6EE7B7)),
              _legendToggle(2, 'CACHE', const Color(0xFF67E8F9)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: ceilY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: ceilY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colorScheme.onSurface.withOpacity(0.05),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: ceilY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          fmtY(value),
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                            color: colorScheme.onSurfaceVariant.withOpacity(
                              0.4,
                            ),
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        // Show label every 5 days
                        if (idx % 5 != 0 || idx >= dates.length) {
                          return const SizedBox.shrink();
                        }
                        // Show only MM-DD
                        final d = dates[idx];
                        final short = d.length >= 5 ? d.substring(5) : d;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: TextStyle(
                              fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                              color: colorScheme.onSurfaceVariant.withOpacity(
                                0.5,
                              ),
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final labels = ['IN', 'OUT', 'CACHE'];
                      final colors = [
                        const Color(0xFF93C5FD),
                        const Color(0xFF6EE7B7),
                        const Color(0xFF67E8F9),
                      ];
                      final date = groupIndex < dates.length
                          ? dates[groupIndex]
                          : '';
                      return BarTooltipItem(
                        rodIndex == 0 ? '$date\n' : '',
                        TextStyle(color: colorScheme.onSurface, fontSize: Theme.of(context).textTheme.labelMedium!.fontSize),
                        children: [
                          TextSpan(
                            text: '${labels[rodIndex]}: ${fmtY(rod.toY)}',
                            style: TextStyle(
                              color: colors[rodIndex],
                              fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendToggle(int index, String label, Color color) {
    final hidden = _hiddenBarSeries.contains(index);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (hidden) {
            _hiddenBarSeries.remove(index);
          } else {
            _hiddenBarSeries.add(index);
          }
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: hidden ? color.withOpacity(0.2) : color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
              color: hidden ? color.withOpacity(0.3) : color,
              fontWeight: FontWeight.w500,
              decoration: hidden ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, Map<String, dynamic> data) {
    final columns = data['columns'] as List<dynamic>? ?? [];
    final rows = data['rows'] as List<dynamic>? ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    if (columns.isEmpty || rows.isEmpty) {
      return Text(context.l10n.noData);
    }

    return _glassCard(
      context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.map((row) {
          final cells = row as List<dynamic>? ?? [];
          if (cells.length < columns.length) return const SizedBox.shrink();

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.onSurface.withOpacity(0.03),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cells[0].toString(),
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (cells.length > 1)
                  Text(
                    cells[1].toString(),
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                      fontFamily: 'monospace',
                      color: colorScheme.primary,
                    ),
                  ),
                if (cells.length > 2) ...[
                  const SizedBox(width: 16),
                  Text(
                    cells[2].toString(),
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
