part of 'database.dart';

@DataClassName('TrafficStatRecord')
class TrafficStatRecords extends Table {
  @override
  String get tableName => 'traffic_stats';

  TextColumn get date => text()();

  TextColumn get scope => textEnum<TrafficStatsScope>()();

  TextColumn get key => text()();

  IntColumn get upload => integer().withDefault(const Constant(0))();

  IntColumn get download => integer().withDefault(const Constant(0))();

  IntColumn get proxyUpload => integer().withDefault(const Constant(0))();

  IntColumn get proxyDownload => integer().withDefault(const Constant(0))();

  IntColumn get connections => integer().withDefault(const Constant(0))();

  IntColumn get lastCoreUpload => integer().withDefault(const Constant(0))();

  IntColumn get lastCoreDownload => integer().withDefault(const Constant(0))();

  IntColumn get lastCoreProxyUpload =>
      integer().withDefault(const Constant(0))();

  IntColumn get lastCoreProxyDownload =>
      integer().withDefault(const Constant(0))();

  IntColumn get lastCoreConnections =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {date, scope, key};
}

@DriftAccessor(tables: [TrafficStatRecords])
class TrafficStatsDao extends DatabaseAccessor<Database>
    with _$TrafficStatsDaoMixin {
  TrafficStatsDao(super.attachedDatabase);

  Future<List<TrafficStatRecord>> getRecords(
    String date,
    TrafficStatsScope scope,
  ) {
    final stmt = trafficStatRecords.select()
      ..where((t) => t.date.equals(date) & t.scope.equalsValue(scope));
    return stmt.get();
  }

  Future<List<TrafficStatRecord>> getRecordsFrom(
    String date,
    TrafficStatsScope scope,
  ) {
    final stmt = trafficStatRecords.select()
      ..where(
        (t) => t.date.isBiggerOrEqualValue(date) & t.scope.equalsValue(scope),
      );
    return stmt.get();
  }

  /// Latest row per key strictly before [date]: the counter baseline a key
  /// carries into a new day when today's row does not exist yet.
  Future<Map<String, TrafficStatRecord>> getLatestBefore(
    String date,
    TrafficStatsScope scope,
  ) async {
    final stmt = trafficStatRecords.select()
      ..where(
        (t) => t.date.isSmallerThanValue(date) & t.scope.equalsValue(scope),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);
    final rows = await stmt.get();
    final latest = <String, TrafficStatRecord>{};
    for (final row in rows) {
      latest.putIfAbsent(row.key, () => row);
    }
    return latest;
  }

  Future<void> putAll(Iterable<TrafficStatRecordsCompanion> items) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(trafficStatRecords, items);
    });
  }

  Future<void> deleteAll() {
    return (trafficStatRecords.delete()).go();
  }

  Future<void> deleteBefore(String date) {
    return (trafficStatRecords.delete()
          ..where((t) => t.date.isSmallerThanValue(date)))
        .go();
  }
}
