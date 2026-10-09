import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

TrafficStatRecordsCompanion record(
  String date,
  String key, {
  int upload = 0,
  int download = 0,
  int proxyUpload = 0,
  int proxyDownload = 0,
  int connections = 0,
}) {
  return TrafficStatRecordsCompanion.insert(
    date: date,
    scope: TrafficStatsScope.process,
    key: key,
    upload: Value(upload),
    download: Value(download),
    proxyUpload: Value(proxyUpload),
    proxyDownload: Value(proxyDownload),
    connections: Value(connections),
  );
}

void main() {
  late Database database;

  setUp(() {
    database = Database(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('round-trips rows scoped by date and scope', () async {
    await database.trafficStatsDao.putAll([
      record('2026-10-09', 'curl'),
      record('2026-10-09', 'safari'),
      record('2026-10-08', 'curl'),
    ]);
    final hostRows = await database.trafficStatsDao.getRecords(
      '2026-10-09',
      TrafficStatsScope.host,
    );
    expect(hostRows, isEmpty);

    final rows = await database.trafficStatsDao.getRecords(
      '2026-10-09',
      TrafficStatsScope.process,
    );
    expect(rows.map((row) => row.key), unorderedEquals(['curl', 'safari']));

    final fromRows = await database.trafficStatsDao.getRecordsFrom(
      '2026-10-08',
      TrafficStatsScope.process,
    );
    expect(fromRows, hasLength(3));
  });

  test('latest-before keeps only the most recent row per key', () async {
    await database.trafficStatsDao.putAll([
      record('2026-10-07', 'curl', download: 30),
      record('2026-10-08', 'curl', download: 60),
      record('2026-10-08', 'safari', download: 10),
    ]);
    final latest = await database.trafficStatsDao.getLatestBefore(
      '2026-10-09',
      TrafficStatsScope.process,
    );
    expect(latest['curl']!.date, '2026-10-08');
    expect(latest['curl']!.download, 60);
    expect(latest['safari']!.date, '2026-10-08');
    expect(latest.containsKey('grep'), isFalse);
  });

  test('upsert replaces counters of the same day row', () async {
    await database.trafficStatsDao.putAll([
      record('2026-10-09', 'curl', download: 100, connections: 2),
    ]);
    await database.trafficStatsDao.putAll([
      record('2026-10-09', 'curl', download: 140, connections: 3),
    ]);
    final rows = await database.trafficStatsDao.getRecords(
      '2026-10-09',
      TrafficStatsScope.process,
    );
    expect(rows.single.download, 140);
    expect(rows.single.connections, 3);
  });

  test('deleteAll and deleteBefore prune history', () async {
    await database.trafficStatsDao.putAll([
      record('2026-10-07', 'curl'),
      record('2026-10-08', 'curl'),
      record('2026-10-09', 'curl'),
    ]);
    await database.trafficStatsDao.deleteBefore('2026-10-08');
    var rows = await database.trafficStatsDao.getRecordsFrom(
      '',
      TrafficStatsScope.process,
    );
    expect(rows.map((row) => row.date), ['2026-10-08', '2026-10-09']);

    await database.trafficStatsDao.deleteAll();
    rows = await database.trafficStatsDao.getRecordsFrom(
      '',
      TrafficStatsScope.process,
    );
    expect(rows, isEmpty);
  });
}
