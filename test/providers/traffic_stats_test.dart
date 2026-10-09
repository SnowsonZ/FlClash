import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter_test/flutter_test.dart';

TrafficKeyStat stat(
  String key, {
  int upload = 0,
  int download = 0,
  int proxyUpload = 0,
  int proxyDownload = 0,
  int connections = 0,
}) {
  return TrafficKeyStat(
    key: key,
    upload: upload,
    download: download,
    proxyUpload: proxyUpload,
    proxyDownload: proxyDownload,
    connections: connections,
  );
}

void main() {
  group('trafficStatsDelta', () {
    test('grows by the difference', () {
      expect(trafficStatsDelta(150, 100), 50);
    });

    test('a counter that fell belongs to a restarted core', () {
      expect(trafficStatsDelta(20, 100), 20);
    });
  });

  group('mergeTrafficStatRecord', () {
    test('first sight of a key counts everything the core holds', () {
      final merged = mergeTrafficStatRecord(
        date: '2026-10-09',
        scope: TrafficStatsScope.process,
        current: stat('curl', download: 100, proxyDownload: 100),
      );
      expect(merged.download.value, 100);
      expect(merged.proxyDownload.value, 100);
      expect(merged.lastCoreDownload.value, 100);
    });

    test('accumulates the delta onto the day row', () {
      final merged = mergeTrafficStatRecord(
        date: '2026-10-09',
        scope: TrafficStatsScope.process,
        current: stat('curl', download: 180, upload: 40, proxyDownload: 180),
        today: const TrafficStatRecord(
          date: '2026-10-09',
          scope: TrafficStatsScope.process,
          key: 'curl',
          upload: 10,
          download: 100,
          proxyUpload: 10,
          proxyDownload: 100,
          connections: 2,
          lastCoreUpload: 10,
          lastCoreDownload: 100,
          lastCoreProxyUpload: 10,
          lastCoreProxyDownload: 100,
          lastCoreConnections: 2,
        ),
      );
      expect(merged.download.value, 180);
      expect(merged.upload.value, 40);
      expect(merged.lastCoreDownload.value, 180);
    });

    test('a core restart counts the fresh value once more', () {
      final merged = mergeTrafficStatRecord(
        date: '2026-10-09',
        scope: TrafficStatsScope.process,
        current: stat('curl', download: 5),
        today: const TrafficStatRecord(
          date: '2026-10-09',
          scope: TrafficStatsScope.process,
          key: 'curl',
          upload: 0,
          download: 500,
          proxyUpload: 0,
          proxyDownload: 500,
          connections: 4,
          lastCoreUpload: 0,
          lastCoreDownload: 500,
          lastCoreProxyUpload: 0,
          lastCoreProxyDownload: 500,
          lastCoreConnections: 4,
        ),
      );
      expect(merged.download.value, 505);
      expect(merged.lastCoreDownload.value, 5);
    });

    test('a new day starts from the previous day baseline', () {
      final merged = mergeTrafficStatRecord(
        date: '2026-10-10',
        scope: TrafficStatsScope.process,
        current: stat('curl', download: 300),
        previous: const TrafficStatRecord(
          date: '2026-10-09',
          scope: TrafficStatsScope.process,
          key: 'curl',
          upload: 0,
          download: 250,
          proxyUpload: 0,
          proxyDownload: 250,
          connections: 1,
          lastCoreUpload: 0,
          lastCoreDownload: 250,
          lastCoreProxyUpload: 0,
          lastCoreProxyDownload: 250,
          lastCoreConnections: 1,
        ),
      );
      expect(merged.download.value, 50);
    });
  });

  group('applyTrafficStatsSnapshot', () {
    late Database database;

    setUp(() {
      database = Database(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    Future<List<TrafficStatRecord>> rows([String? date]) {
      return database.trafficStatsDao.getRecordsFrom(
        date ?? '',
        TrafficStatsScope.process,
      );
    }

    test('repeated snapshots accumulate within one day', () async {
      await applyTrafficStatsSnapshot(
        database,
        '2026-10-09',
        TrafficStats(
          process: [stat('curl', download: 100, proxyDownload: 100)],
          host: [stat('a.com', download: 100, proxyDownload: 100)],
        ),
      );
      await applyTrafficStatsSnapshot(
        database,
        '2026-10-09',
        TrafficStats(
          process: [stat('curl', download: 160, proxyDownload: 160)],
          host: [stat('a.com', download: 160, proxyDownload: 160)],
        ),
      );
      final processRows = await rows();
      expect(processRows.single.key, 'curl');
      expect(processRows.single.download, 160);
      expect(processRows.single.proxyDownload, 160);

      final hostRows = await database.trafficStatsDao.getRecordsFrom(
        '',
        TrafficStatsScope.host,
      );
      expect(hostRows.single.key, 'a.com');
      expect(hostRows.single.download, 160);
    });

    test('the unflushed midnight window lands on the new day', () async {
      await applyTrafficStatsSnapshot(
        database,
        '2026-10-09',
        TrafficStats(
          process: [stat('curl', download: 250, proxyDownload: 250)],
          host: const [],
        ),
      );
      await applyTrafficStatsSnapshot(
        database,
        '2026-10-10',
        TrafficStats(
          process: [stat('curl', download: 300, proxyDownload: 300)],
          host: const [],
        ),
      );
      final processRows = await rows();
      expect(processRows, hasLength(2));
      expect(
        processRows.firstWhere((row) => row.date == '2026-10-09').download,
        250,
      );
      expect(
        processRows.firstWhere((row) => row.date == '2026-10-10').download,
        50,
      );
    });
  });
}
