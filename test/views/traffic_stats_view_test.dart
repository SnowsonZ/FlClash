import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart' show trafficStatsDate;
import 'package:fl_clash/providers/app.dart' show viewSizeProvider;
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/traffic_stats.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _MockCoreHandlerInterface core;
  late Database memoryDatabase;
  late Database previousDatabase;

  setUp(() {
    core = _MockCoreHandlerInterface();
    memoryDatabase = Database(NativeDatabase.memory());
    previousDatabase = database;
    database = memoryDatabase;
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    container.read(viewSizeProvider.notifier).state = const Size(1400, 1000);
    globalState.container = container;
  });

  tearDown(() async {
    container.dispose();
    database = previousDatabase;
    await memoryDatabase.close();
  });

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: PageActivityScope(isActive: true, child: TrafficStatsView()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  TrafficStats liveSnapshot() {
    return const TrafficStats(
      process: [
        TrafficKeyStat(
          key: 'curl',
          upload: 20,
          download: 100,
          proxyUpload: 20,
          proxyDownload: 100,
          connections: 2,
        ),
        TrafficKeyStat(
          key: 'backupd',
          upload: 5,
          download: 10,
          proxyUpload: 0,
          proxyDownload: 0,
          connections: 1,
        ),
      ],
      host: [
        TrafficKeyStat(
          key: 'a.com',
          upload: 20,
          download: 100,
          proxyUpload: 20,
          proxyDownload: 100,
          connections: 2,
        ),
      ],
    );
  }

  testWidgets('lists live rows with the proxy-only filter on', (tester) async {
    when(() => core.getTrafficStats()).thenAnswer((_) async => liveSnapshot());

    await pumpView(tester);

    expect(find.text('curl'), findsOneWidget);
    expect(find.text('a.com'), findsNothing);
    expect(find.text('backupd'), findsNothing);
  });

  testWidgets('a narrow view drops the column headers', (tester) async {
    container.read(viewSizeProvider.notifier).state = const Size(420, 800);
    when(() => core.getTrafficStats()).thenAnswer((_) async => liveSnapshot());

    await pumpView(tester);

    expect(find.text('Speed'), findsNothing);
    expect(find.text('Traffic'), findsNothing);
    expect(find.text('curl'), findsOneWidget);
  });

  testWidgets('switching scope shows host rows', (tester) async {
    when(() => core.getTrafficStats()).thenAnswer((_) async => liveSnapshot());

    await pumpView(tester);
    await tester.tap(find.text('By service'));
    await tester.pump();
    await tester.pump();

    expect(find.text('a.com'), findsOneWidget);
    expect(find.text('curl'), findsNothing);
  });

  testWidgets('turning the filter off shows direct-only rows', (tester) async {
    when(() => core.getTrafficStats()).thenAnswer((_) async => liveSnapshot());

    await pumpView(tester);
    await tester.tap(find.text('Proxy only'));
    await tester.pump();
    await tester.pump();

    expect(find.text('curl'), findsOneWidget);
    expect(find.text('backupd'), findsOneWidget);
  });

  testWidgets('history rows survive an unreachable core', (tester) async {
    final today = trafficStatsDate(DateTime.now());
    await memoryDatabase.trafficStatsDao.putAll([
      TrafficStatRecordsCompanion.insert(
        date: today,
        scope: TrafficStatsScope.process,
        key: 'archived',
        download: const Value(4096),
        proxyDownload: const Value(4096),
        connections: const Value(3),
      ),
    ]);
    when(() => core.getTrafficStats()).thenThrow(StateError('core down'));

    await pumpView(tester);

    expect(find.text('archived'), findsOneWidget);
  });

  testWidgets('shows the empty state without data', (tester) async {
    when(
      () => core.getTrafficStats(),
    ).thenAnswer((_) async => const TrafficStats());

    await pumpView(tester);

    expect(find.byType(ListItem), findsNothing);
  });

  testWidgets('sorting by upload speed reorders rows', (tester) async {
    var bigUpload = 100;
    when(() => core.getTrafficStats()).thenAnswer(
      (_) async => TrafficStats(
        process: [
          const TrafficKeyStat(
            key: 'small',
            upload: 1000,
            download: 5000,
            proxyUpload: 1000,
            proxyDownload: 5000,
            connections: 1,
          ),
          TrafficKeyStat(
            key: 'big',
            upload: bigUpload,
            download: 50,
            proxyUpload: bigUpload,
            proxyDownload: 50,
            connections: 1,
          ),
        ],
      ),
    );

    await pumpView(tester);

    List<String> rowTitles() {
      return tester
          .widgetList<ListItem>(find.byType(ListItem))
          .map((item) => (item.title as Text).data ?? '')
          .toList();
    }

    expect(rowTitles(), ['small', 'big']);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Traffic'), findsOneWidget);

    bigUpload = 500;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    await tester.tap(find.byKey(const Key('trafficStatsSortMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload speed'));
    await tester.pumpAndSettle();

    expect(rowTitles(), ['big', 'small']);
    expect(find.text('↑ 200 B/s'), findsOneWidget);
  });
}
