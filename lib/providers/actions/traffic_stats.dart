part of '../action.dart';

const trafficStatsFlushInterval = Duration(seconds: 30);

String trafficStatsDate(DateTime time) {
  String pad2(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad2(time.month)}-${pad2(time.day)}';
}

/// A counter that fell below [last] belongs to a restarted or reset core:
/// the fresh value counts once more.
int trafficStatsDelta(int current, int last) {
  return current >= last ? current - last : current;
}

/// A key absent today starts from its most recent earlier row, so an
/// unflushed midnight window lands on the new day.
TrafficStatRecordsCompanion mergeTrafficStatRecord({
  required String date,
  required TrafficStatsScope scope,
  required TrafficKeyStat current,
  TrafficStatRecord? today,
  TrafficStatRecord? previous,
}) {
  final row = today;
  final lastUpload = row?.lastCoreUpload ?? previous?.lastCoreUpload ?? 0;
  final lastDownload = row?.lastCoreDownload ?? previous?.lastCoreDownload ?? 0;
  final lastProxyUpload =
      row?.lastCoreProxyUpload ?? previous?.lastCoreProxyUpload ?? 0;
  final lastProxyDownload =
      row?.lastCoreProxyDownload ?? previous?.lastCoreProxyDownload ?? 0;
  final lastConnections =
      row?.lastCoreConnections ?? previous?.lastCoreConnections ?? 0;

  return TrafficStatRecordsCompanion.insert(
    date: date,
    scope: scope,
    key: current.key,
    upload: Value(
      (row?.upload ?? 0) + trafficStatsDelta(current.upload, lastUpload),
    ),
    download: Value(
      (row?.download ?? 0) + trafficStatsDelta(current.download, lastDownload),
    ),
    proxyUpload: Value(
      (row?.proxyUpload ?? 0) +
          trafficStatsDelta(current.proxyUpload, lastProxyUpload),
    ),
    proxyDownload: Value(
      (row?.proxyDownload ?? 0) +
          trafficStatsDelta(current.proxyDownload, lastProxyDownload),
    ),
    connections: Value(
      (row?.connections ?? 0) +
          trafficStatsDelta(current.connections, lastConnections),
    ),
    lastCoreUpload: Value(current.upload),
    lastCoreDownload: Value(current.download),
    lastCoreProxyUpload: Value(current.proxyUpload),
    lastCoreProxyDownload: Value(current.proxyDownload),
    lastCoreConnections: Value(current.connections),
  );
}

Future<void> applyTrafficStatsSnapshot(
  Database db,
  String date,
  TrafficStats stats,
) async {
  final rows = <TrafficStatRecordsCompanion>[];
  for (final scope in TrafficStatsScope.values) {
    final entries = switch (scope) {
      TrafficStatsScope.process => stats.process,
      TrafficStatsScope.host => stats.host,
    };
    if (entries.isEmpty) {
      continue;
    }
    final today = {
      for (final row in await db.trafficStatsDao.getRecords(date, scope))
        row.key: row,
    };
    final previous = await db.trafficStatsDao.getLatestBefore(date, scope);
    rows.addAll([
      for (final entry in entries)
        mergeTrafficStatRecord(
          date: date,
          scope: scope,
          current: entry,
          today: today[entry.key],
          previous: previous[entry.key],
        ),
    ]);
  }
  if (rows.isNotEmpty) {
    await db.trafficStatsDao.putAll(rows);
  }
}

@Riverpod(keepAlive: true)
class TrafficStatsAction extends _$TrafficStatsAction {
  Timer? _timer;
  bool _flushing = false;

  @override
  void build() {
    ref.onDispose(_stop);
  }

  CoreController get _core => ref.read(coreHandlerProvider);

  void start() {
    _timer ??= Timer.periodic(trafficStatsFlushInterval, (_) => flush());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Counters are cumulative, so a core that is down or restarting just means
  /// the next successful flush catches up.
  Future<void> flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      final stats = await _core.getTrafficStats();
      await applyTrafficStatsSnapshot(
        database,
        trafficStatsDate(DateTime.now()),
        stats,
      );
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  Future<void> clear() async {
    await database.trafficStatsDao.deleteAll();
    try {
      _core.resetTraffic();
    } catch (_) {}
  }
}
