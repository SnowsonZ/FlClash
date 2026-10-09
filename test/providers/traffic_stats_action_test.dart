import 'package:drift/native.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;
  late Database memoryDatabase;
  late Database previousDatabase;

  setUpAll(() {
    core = MockCoreHandlerInterface();
    registerFallbackValue(const TrafficStats(process: [], host: []));
  });

  setUp(() {
    reset(core);
    memoryDatabase = Database(NativeDatabase.memory());
    previousDatabase = database;
    database = memoryDatabase;
  });

  tearDown(() async {
    database = previousDatabase;
    await memoryDatabase.close();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  TrafficStats snapshot(int download) {
    return TrafficStats(
      process: [
        TrafficKeyStat(
          key: 'curl',
          download: download,
          proxyDownload: download,
          connections: 1,
        ),
      ],
      host: [
        TrafficKeyStat(
          key: 'a.com',
          download: download,
          proxyDownload: download,
          connections: 1,
        ),
      ],
    );
  }

  test('flush persists both scopes and accumulates across flushes', () async {
    final container = buildContainer();
    final action = container.read(trafficStatsActionProvider.notifier);
    when(() => core.getTrafficStats()).thenAnswer((_) async => snapshot(100));

    await action.flush();

    when(() => core.getTrafficStats()).thenAnswer((_) async => snapshot(150));
    await action.flush();

    final processRows = await database.trafficStatsDao.getRecordsFrom(
      '',
      TrafficStatsScope.process,
    );
    final hostRows = await database.trafficStatsDao.getRecordsFrom(
      '',
      TrafficStatsScope.host,
    );
    expect(processRows.single.key, 'curl');
    expect(processRows.single.download, 150);
    expect(hostRows.single.key, 'a.com');
    expect(hostRows.single.download, 150);
  });

  test('flush survives an unreachable core', () async {
    final container = buildContainer();
    final action = container.read(trafficStatsActionProvider.notifier);
    when(() => core.getTrafficStats()).thenThrow(StateError('core down'));

    await action.flush();

    expect(
      await database.trafficStatsDao.getRecordsFrom(
        '',
        TrafficStatsScope.process,
      ),
      isEmpty,
    );
  });

  test('clear drops history and resets the core counters', () async {
    final container = buildContainer();
    final action = container.read(trafficStatsActionProvider.notifier);
    when(() => core.getTrafficStats()).thenAnswer((_) async => snapshot(100));
    await action.flush();
    when(() => core.resetTraffic()).thenReturn(null);

    await action.clear();

    expect(
      await database.trafficStatsDao.getRecordsFrom('', TrafficStatsScope.host),
      isEmpty,
    );
    verify(() => core.resetTraffic()).called(1);
  });
}
