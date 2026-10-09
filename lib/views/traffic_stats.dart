import 'dart:math';

import 'package:clock/clock.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TrafficStatsSort { total, downloadSpeed, uploadSpeed }

class _LiveSample {
  final int upload;
  final int download;
  final DateTime at;

  const _LiveSample({
    required this.upload,
    required this.download,
    required this.at,
  });
}

class TrafficStatsView extends ConsumerStatefulWidget {
  const TrafficStatsView({super.key});

  @override
  ConsumerState<TrafficStatsView> createState() => _TrafficStatsViewState();
}

class _TrafficStatsRow {
  final String key;
  int upload = 0;
  int download = 0;
  int proxyUpload = 0;
  int proxyDownload = 0;
  int connections = 0;
  int uploadSpeed = 0;
  int downloadSpeed = 0;

  _TrafficStatsRow(this.key);
}

class _TrafficStatsViewState extends ConsumerState<TrafficStatsView>
    with
        WidgetsBindingObserver,
        ActivePollingMixin<TrafficStatsView>,
        RouteMotionHoldMixin<TrafficStatsView> {
  TrafficStatsScope _scope = TrafficStatsScope.process;
  TrafficStatsRange _range = TrafficStatsRange.today;
  TrafficStatsSort _sort = TrafficStatsSort.total;
  bool _proxyOnly = true;
  List<_TrafficStatsRow> _rows = [];
  Map<String, _LiveSample> _liveSamples = const {};

  @override
  Duration get pollInterval => const Duration(seconds: 2);

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final rows = await _loadRows();
    if (!isCurrent()) {
      return;
    }
    updateWhenRouteSettled(() {
      if (mounted) {
        setState(() {
          _rows = rows;
        });
      }
    });
  }

  Future<List<_TrafficStatsRow>> _loadRows() async {
    final now = clock.now();
    final today = trafficStatsDate(now);
    final fromDate = switch (_range) {
      TrafficStatsRange.today => today,
      TrafficStatsRange.week => trafficStatsDate(
        now.subtract(const Duration(days: 6)),
      ),
      TrafficStatsRange.all => '',
    };
    final dao = database.trafficStatsDao;
    final dbRows = await dao.getRecordsFrom(fromDate, _scope);

    final totals = <String, _TrafficStatsRow>{};
    _TrafficStatsRow rowOf(String key) {
      return totals.putIfAbsent(key, () => _TrafficStatsRow(key));
    }

    final todayRows = <String, TrafficStatRecord>{};
    for (final row in dbRows) {
      if (row.date == today) {
        todayRows[row.key] = row;
        continue;
      }
      final item = rowOf(row.key);
      item.upload += row.upload;
      item.download += row.download;
      item.proxyUpload += row.proxyUpload;
      item.proxyDownload += row.proxyDownload;
      item.connections += row.connections;
    }

    TrafficStats? live;
    try {
      live = await ref.read(coreHandlerProvider).getTrafficStats();
    } catch (_) {}
    if (live != null) {
      final entries = switch (_scope) {
        TrafficStatsScope.process => live.process,
        TrafficStatsScope.host => live.host,
      };
      final now = clock.now();
      final samples = <String, _LiveSample>{
        for (final entry in entries)
          entry.key: _LiveSample(
            upload: entry.upload,
            download: entry.download,
            at: now,
          ),
      };
      if (entries.isNotEmpty) {
        final previous = await dao.getLatestBefore(today, _scope);
        for (final entry in entries) {
          final merged = mergeTrafficStatRecord(
            date: today,
            scope: _scope,
            current: entry,
            today: todayRows[entry.key],
            previous: previous[entry.key],
          );
          final item = rowOf(entry.key);
          item.upload += merged.upload.value;
          item.download += merged.download.value;
          item.proxyUpload += merged.proxyUpload.value;
          item.proxyDownload += merged.proxyDownload.value;
          item.connections += merged.connections.value;
        }
      }
      for (final entry in entries) {
        final previousSample = _liveSamples[entry.key];
        if (previousSample == null) {
          continue;
        }
        final elapsed = now.difference(previousSample.at);
        if (elapsed < const Duration(milliseconds: 500)) {
          continue;
        }
        final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        final item = totals[entry.key];
        if (item == null) {
          continue;
        }
        item.uploadSpeed =
            (max(0, entry.upload - previousSample.upload) / seconds).round();
        item.downloadSpeed =
            (max(0, entry.download - previousSample.download) / seconds)
                .round();
      }
      _liveSamples = samples;
    } else {
      _liveSamples = const {};
    }
    for (final row in todayRows.values) {
      if (totals.containsKey(row.key) && _liveHas(live, row.key)) {
        continue;
      }
      final item = rowOf(row.key);
      item.upload += row.upload;
      item.download += row.download;
      item.proxyUpload += row.proxyUpload;
      item.proxyDownload += row.proxyDownload;
      item.connections += row.connections;
    }

    var rows = totals.values.toList();
    if (_proxyOnly) {
      rows = rows
          .where((row) => row.proxyUpload > 0 || row.proxyDownload > 0)
          .toList();
    }
    _sortRows(rows);
    return rows;
  }

  int _sortValue(_TrafficStatsRow row) {
    return switch (_sort) {
      TrafficStatsSort.total =>
        _proxyOnly
            ? row.proxyDownload + row.proxyUpload
            : row.download + row.upload,
      TrafficStatsSort.downloadSpeed => row.downloadSpeed,
      TrafficStatsSort.uploadSpeed => row.uploadSpeed,
    };
  }

  void _sortRows(List<_TrafficStatsRow> rows) {
    rows.sort((a, b) => _sortValue(b).compareTo(_sortValue(a)));
  }

  bool _liveHas(TrafficStats? live, String key) {
    if (live == null) {
      return false;
    }
    return switch (_scope) {
      TrafficStatsScope.process => live.process.any((item) => item.key == key),
      TrafficStatsScope.host => live.host.any((item) => item.key == key),
    };
  }

  Future<void> _clearStats() async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.clearTrafficStats,
      message: TextSpan(text: appLocalizations.clearTrafficStatsTip),
    );
    if (res != true) {
      return;
    }
    await ref.read(trafficStatsActionProvider.notifier).clear();
    await poll(() => true);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: PageLabel.trafficStats.label,
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.clearAll,
          tooltip: appLocalizations.clearTrafficStats,
          onPressed: _clearStats,
        ),
      ],
      body: Column(
        children: [
          _buildFilters(context),
          Expanded(
            child: NullStatusSwitcher(
              isEmpty: _rows.isEmpty,
              nullStatus: NullStatus(
                label: appLocalizations.nullTip(appLocalizations.trafficStats),
                illustration: NullStatusIllustration.data,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NextClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: 16 + BottomInsetScope.of(context),
                ),
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const Divider(height: 0),
                itemBuilder: (context, index) {
                  return _buildRow(context, _rows[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, context.contentTopPadding + 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<TrafficStatsScope>(
              segments: [
                ButtonSegment(
                  value: TrafficStatsScope.process,
                  label: Text(appLocalizations.byApp),
                ),
                ButtonSegment(
                  value: TrafficStatsScope.host,
                  label: Text(appLocalizations.byService),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (selection) {
                setState(() {
                  _scope = selection.first;
                  _liveSamples = const {};
                });
                restartPolling();
              },
            ),
            const SizedBox(width: 12),
            SegmentedButton<TrafficStatsRange>(
              segments: [
                ButtonSegment(
                  value: TrafficStatsRange.today,
                  label: Text(appLocalizations.trafficStatsToday),
                ),
                ButtonSegment(
                  value: TrafficStatsRange.week,
                  label: Text(appLocalizations.trafficStatsWeek),
                ),
                ButtonSegment(
                  value: TrafficStatsRange.all,
                  label: Text(appLocalizations.trafficStatsAll),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (selection) {
                setState(() {
                  _range = selection.first;
                });
                restartPolling();
              },
            ),
            const SizedBox(width: 12),
            FilterChip(
              label: Text(appLocalizations.proxyOnly),
              selected: _proxyOnly,
              onSelected: (value) {
                setState(() {
                  _proxyOnly = value;
                });
                restartPolling();
              },
            ),
            const SizedBox(width: 12),
            _buildSortMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSortMenu(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    String labelOf(TrafficStatsSort sort) {
      return switch (sort) {
        TrafficStatsSort.total => appLocalizations.trafficStatsSortTotal,
        TrafficStatsSort.downloadSpeed =>
          appLocalizations.trafficStatsSortDownloadSpeed,
        TrafficStatsSort.uploadSpeed =>
          appLocalizations.trafficStatsSortUploadSpeed,
      };
    }

    return CommonPopupBox(
      targetBuilder: (open) => ActionChip(
        key: const Key('trafficStatsSortMenu'),
        avatar: const GlyphIcon(AppGlyphs.sort),
        label: Text(labelOf(_sort)),
        onPressed: () => open(offset: const Offset(0, 8)),
      ),
      popupBuilder: (_) => CommonPopupMenu(
        items: [
          for (final sort in TrafficStatsSort.values)
            CommonPopupMenuItem(
              label: labelOf(sort),
              checked: sort == _sort,
              onPressed: () {
                setState(() {
                  _sort = sort;
                  _sortRows(_rows);
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _TrafficStatsRow row) {
    final appLocalizations = context.appLocalizations;
    final name = row.key.isEmpty ? appLocalizations.unknown : row.key;
    final uploadShow = (row.upload).traffic;
    final downloadShow = (row.download).traffic;
    final proxyDownloadShow = (row.proxyDownload).traffic;
    Widget? trailing;
    if (_sort == TrafficStatsSort.downloadSpeed) {
      trailing = _buildSpeedText(
        context,
        AppGlyphs.arrowDown,
        row.downloadSpeed,
      );
    } else if (_sort == TrafficStatsSort.uploadSpeed) {
      trailing = _buildSpeedText(context, AppGlyphs.arrowUp, row.uploadSpeed);
    } else if (_proxyOnly) {
      trailing = Text(
        '${proxyDownloadShow.value} ${proxyDownloadShow.unit}',
        style: context.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return ListItem(
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${appLocalizations.trafficStatsConnections(row.connections)}   '
        '↓ ${downloadShow.value} ${downloadShow.unit}   '
        '↑ ${uploadShow.value} ${uploadShow.unit}',
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildSpeedText(BuildContext context, Glyph glyph, int speed) {
    final speedShow = speed.traffic;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(glyph, size: 16),
        const SizedBox(width: 4),
        Text(
          '${speedShow.value} ${speedShow.unit}/s',
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
