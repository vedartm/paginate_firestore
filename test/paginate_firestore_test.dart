import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginate_firestore/bloc/pagination_cubit.dart';
import 'package:paginate_firestore/bloc/pagination_listeners.dart';
import 'package:paginate_firestore/paginate_firestore.dart';

import 'support/firestore_fakes.dart';

void main() {
  Widget buildWidget(
    RecordingFirestore store, {
    List<ChangeNotifier>? listeners,
    ScrollController? controller,
    void Function(PaginationLoaded)? onLoaded,
    int pageSize = 2,
    String loadMoreLabel = 'Load more',
    bool isLive = false,
    bool isAllItemsLive = true,
    bool includeMetadataChanges = false,
    bool outerScroll = false,
    GetOptions? options,
    DocumentSnapshot? startAfterDocument,
    int? globalLimit,
    PaginateBuilderType builderType = PaginateBuilderType.listView,
    PageController? pageController,
    Widget Function(BuildContext, List<DocumentSnapshot>, int)? itemBuilder,
  }) {
    final pagination = PaginateFirestore(
      query: store.query,
      itemsPerPage: pageSize,
      // Exercise the existing one-page-budget regressions. The default budget
      // and layout-driven filling have dedicated tests in automatic_fill_test.
      maxAutomaticFillPages: 1,
      loadMoreLabel: loadMoreLabel,
      itemBuilderType: builderType,
      pageController: pageController,
      listeners: listeners,
      scrollController: controller,
      isLive: isLive,
      isAllItemsLive: isAllItemsLive,
      includeMetadataChanges: includeMetadataChanges,
      shrinkWrap: outerScroll,
      onLoaded: onLoaded,
      options: options,
      startAfterDocument: startAfterDocument,
      itemsGlobalLimit: globalLimit,
      itemBuilder: itemBuilder ??
          (context, docs, index) =>
              SizedBox(height: 100, child: Text(docs[index].reference.path)),
    );
    return MaterialApp(
      home: Scaffold(
        body:
            outerScroll ? SingleChildScrollView(child: pagination) : pagination,
      ),
    );
  }

  for (final builderType in PaginateBuilderType.values) {
    testWidgets('filtering cannot chain page reads in ${builderType.name}',
        (tester) async {
      final store = RecordingFirestore();
      final filter = PaginateFilterChangeListener()..searchTerm = 'match';
      final controller = PageController(initialPage: 1);
      await tester.pumpWidget(buildWidget(store,
          listeners: [filter],
          builderType: builderType,
          pageController: controller));
      store.requests.single.respond([
        TestDocument('items/a', 'match'),
        TestDocument('items/b', 'other'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(2));
      store.requests.last.respond([
        TestDocument('items/c', 'other'),
        TestDocument('items/d', 'other'),
      ]);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.requests, hasLength(2));
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(store.requests, hasLength(3));
      store.requests.last.respond([
        TestDocument('items/e', 'other'),
        TestDocument('items/f', 'other'),
      ]);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.requests, hasLength(3));
      expect(find.text('Load more'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      filter.dispose();
      controller.dispose();
    });
  }

  testWidgets('custom load more label still loads the next page',
      (tester) async {
    final store = RecordingFirestore();
    const label = 'Načítať ďalšie';
    await tester.pumpWidget(buildWidget(store, loadMoreLabel: label));
    store.requests.single.respond([
      TestDocument('items/a'),
      TestDocument('items/b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(store.requests, hasLength(2));
    store.requests.last.respond([
      TestDocument('items/c'),
      TestDocument('items/d'),
    ]);
    await tester.pumpAndSettle();

    final button = find.widgetWithText(TextButton, label);
    expect(button, findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(store.requests, hasLength(2));

    await tester.tap(button);
    await tester.pump();
    expect(store.requests, hasLength(3));
    expect(store.requests.last.query.cursor!.reference.path, 'items/d');
    store.requests.last.respond([TestDocument('items/e')]);
    await tester.pumpAndSettle();
    expect(find.text('items/e'), findsOneWidget);
    expect(button, findsNothing);
    expect(store.requests, hasLength(3));
    await tester.pumpWidget(const SizedBox());
  });

  for (final builderType in [
    PaginateBuilderType.listView,
    PaginateBuilderType.gridView,
  ]) {
    testWidgets('outer scrolling cannot drain pages in ${builderType.name}',
        (tester) async {
      final store = RecordingFirestore();
      await tester.pumpWidget(
          buildWidget(store, outerScroll: true, builderType: builderType));
      store.requests.single.respond([
        TestDocument('items/a'),
        TestDocument('items/b'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(2));
      store.requests.last.respond([
        TestDocument('items/c'),
        TestDocument('items/d'),
      ]);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('metadata setting changes keep the existing live session',
      (tester) async {
    final store = RecordingFirestore();
    var loadedCount = 0;
    Widget widget(bool metadata) => buildWidget(store,
        isLive: true,
        globalLimit: 2,
        includeMetadataChanges: metadata,
        onLoaded: (_) => loadedCount++);
    await tester.pumpWidget(widget(false));
    store.requests.single.respond([
      TestDocument('items/a'),
      TestDocument('items/b'),
    ]);
    await tester.pumpAndSettle();
    expect(loadedCount, 1);
    await tester.pumpWidget(widget(true));
    store.requests.first.respond([
      TestDocument('items/a'),
      TestDocument('items/b'),
    ], metadataOnly: true);
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    expect(store.requests.single.cancelled, isFalse);
    expect(loadedCount, 2);
    await tester.pumpWidget(widget(false));
    store.requests.single.respond([
      TestDocument('items/a'),
      TestDocument('items/b'),
    ], metadataOnly: true);
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    expect(loadedCount, 2);
    await tester.pumpWidget(const SizedBox());
  });

  for (final isLive in [false, true]) {
    testWidgets('failed pages never retry on rebuilds (live: $isLive)',
        (tester) async {
      final store = RecordingFirestore();
      final refresh = PaginateRefreshedChangeListener();
      Widget widget(bool metadata) => buildWidget(store,
          isLive: isLive,
          includeMetadataChanges: metadata,
          listeners: [refresh]);
      await tester.pumpWidget(widget(false));
      store.requests.single.respond([
        TestDocument('items/a'),
        TestDocument('items/b'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(2));
      store.requests.last.fail(Exception('denied'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(widget(i.isEven));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(store.requests, hasLength(2));
      expect(find.text('Error occurred: Exception: denied'), findsOneWidget);

      // One explicit retry makes one attempt; a second failure stays stopped.
      refresh.refreshed = true;
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(3));
      store.requests.last.fail(Exception('still denied'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(store.requests, hasLength(3));
      expect(
          find.text('Error occurred: Exception: still denied'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      refresh.dispose();
    });
  }

  for (final isLive in [false, true]) {
    testWidgets('retry notifier recovers only the failed page (live: $isLive)',
        (tester) async {
      final store = RecordingFirestore();
      final retry = PaginateRetryChangeListener();
      await tester
          .pumpWidget(buildWidget(store, isLive: isLive, listeners: [retry]));
      store.requests.single.respond([
        TestDocument('items/a'),
        TestDocument('items/b'),
      ]);
      await tester.pump();
      await tester.pump();
      final failedQuery = store.requests.last.query;
      store.requests.last.fail(Exception('unavailable'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        retry.retry();
      }
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(3));
      expect(store.requests.last.query, failedQuery);
      store.requests.last.respond([
        TestDocument('items/c'),
        TestDocument('items/d'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('items/a'), findsOneWidget);
      expect(find.text('items/c'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        retry.retry();
        await tester.pump();
      }
      expect(store.requests, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      // Removing the widget detaches its listener without owning the notifier.
      retry.retry();
      expect(store.requests, hasLength(3));
      retry.dispose();
    });
  }

  testWidgets('retrying the initial page does not automatically fetch page two',
      (tester) async {
    final store = RecordingFirestore();
    final retry = PaginateRetryChangeListener();
    await tester.pumpWidget(buildWidget(store, listeners: [retry]));
    store.requests.single.fail(Exception('unavailable'));
    await tester.pumpAndSettle();
    retry.retry();
    await tester.pump();
    store.requests.last.respond([
      TestDocument('items/a'),
      TestDocument('items/b'),
    ]);
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    expect(find.text('Load more'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    retry.dispose();
  });

  for (final builderType in PaginateBuilderType.values) {
    testWidgets(
        'live events stay bounded and user scrolling resumes '
        'in ${builderType.name}', (tester) async {
      final store = RecordingFirestore();
      final filter = PaginateFilterChangeListener()..searchTerm = 'match';
      final controller = PageController(initialPage: 1);
      Widget widget() => buildWidget(store,
          isLive: true,
          includeMetadataChanges: true,
          listeners: [filter],
          builderType: builderType,
          pageController: controller);
      await tester.pumpWidget(widget());
      store.requests.single.respond([
        TestDocument('items/a', 'match'),
        TestDocument('items/b', 'other'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(2));
      store.requests.last.respond([
        TestDocument('items/c', 'other'),
        TestDocument('items/d', 'other'),
      ]);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        store.requests.last.respond([
          TestDocument('items/c', 'other'),
          TestDocument('items/d', 'other'),
        ], metadataOnly: i.isEven);
        await tester.pumpWidget(widget());
        await tester.pump();
      }
      expect(store.requests, hasLength(2));
      expect(find.text('Load more'), findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(3));
      store.requests.last.respond([
        TestDocument('items/e', 'other'),
        TestDocument('items/f', 'other'),
      ]);
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(3));
      expect(find.text('Load more'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      filter.dispose();
      controller.dispose();
    });
  }

  testWidgets('parent rebuilds do not repeat reads or loaded callbacks',
      (tester) async {
    final store = RecordingFirestore();
    var loadedCount = 0;
    await tester.pumpWidget(buildWidget(store, onLoaded: (_) => loadedCount++));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    expect(find.text('items/a'), findsOneWidget);
    expect(loadedCount, 1);
    await tester.pumpWidget(buildWidget(store, onLoaded: (_) => loadedCount++));
    await tester.pumpAndSettle();
    expect(loadedCount, 1);
    expect(store.requests, hasLength(1));
  });

  testWidgets('zero limit reports loaded without making a query',
      (tester) async {
    final store = RecordingFirestore();
    var loadedCount = 0;
    await tester.pumpWidget(
        buildWidget(store, globalLimit: 0, onLoaded: (_) => loadedCount++));
    await tester.pumpAndSettle();
    expect(store.requests, isEmpty);
    expect(loadedCount, 1);
    expect(find.text('No documents found'), findsOneWidget);
  });

  testWidgets('changing the query cancels the old listener and shows new data',
      (tester) async {
    final first = RecordingFirestore();
    final second = RecordingFirestore();
    await tester.pumpWidget(buildWidget(first, isLive: true));
    first.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildWidget(second, isLive: true));
    expect(first.requests.single.cancelled, isTrue);
    expect(second.requests, hasLength(1));
    // Only a refresh of the same query keeps the previous items visible.
    expect(find.text('items/a'), findsNothing);
    first.requests.single.respond([TestDocument('items/stale')]);
    second.requests.single.respond([TestDocument('items/b')]);
    await tester.pumpAndSettle();
    expect(find.text('items/a'), findsNothing);
    expect(find.text('items/stale'), findsNothing);
    expect(find.text('items/b'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(second.requests.single.cancelled, isTrue);
  });

  testWidgets('changing page size creates a request with the new limit',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildWidget(store, pageSize: 3));
    expect(store.requests, hasLength(2));
    expect(store.requests.last.query.pageLimit, 3);
    store.requests.last.respond([TestDocument('items/b')]);
    await tester.pumpAndSettle();
    expect(find.text('items/b'), findsOneWidget);
  });

  testWidgets('equivalent get options do not reread on parent rebuild',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildWidget(store, options: GetOptions()));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    await tester.pumpWidget(
        buildWidget(store, options: const GetOptions(source: Source.cache)));
    expect(store.requests, hasLength(2));
    expect(store.requests.last.options!.source, Source.cache);
    store.requests.last.respond([TestDocument('items/b')]);
    await tester.pumpAndSettle();
  });

  testWidgets('equivalent cursor snapshots do not restart pagination',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store,
        startAfterDocument: TestDocument('items/start', 'same sort value')));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(buildWidget(store,
          startAfterDocument: TestDocument('items/start', 'same sort value')));
    }
    expect(store.requests, hasLength(1));

    await tester.pumpWidget(buildWidget(store,
        startAfterDocument: TestDocument('items/start', 'changed sort value')));
    expect(store.requests, hasLength(2));
    store.requests.last.respond([TestDocument('items/b')]);
    await tester.pumpAndSettle();
    expect(find.text('items/b'), findsOneWidget);
  });

  testWidgets('irrelevant live/read settings do not restart queries',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildWidget(store, isAllItemsLive: false));
    expect(store.requests, hasLength(1));

    await tester.pumpWidget(buildWidget(store, isLive: true));
    store.requests.last.respond([TestDocument('items/b')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(buildWidget(store,
        isLive: true, options: const GetOptions(source: Source.cache)));
    expect(store.requests, hasLength(2));
    expect(store.requests.last.cancelled, isFalse);
    await tester.pumpWidget(buildWidget(store,
        isLive: false, options: const GetOptions(source: Source.cache)));
    expect(store.requests, hasLength(3));
    expect(store.requests.last.options!.source, Source.cache);
    store.requests.last.respond([TestDocument('items/c')]);
    await tester.pumpAndSettle();
  });

  testWidgets('caller-owned controllers and notifiers survive disposal',
      (tester) async {
    final store = RecordingFirestore();
    final controller = ScrollController();
    final filter = PaginateFilterChangeListener();
    await tester.pumpWidget(
        buildWidget(store, controller: controller, listeners: [filter]));
    store.requests.single.respond([TestDocument('items/a')]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(() => controller.addListener(() {}), returnsNormally);
    expect(() => filter.searchTerm = 'a', returnsNormally);
    expect(() => filter.addListener(() {}), returnsNormally);
    controller.dispose();
    filter.dispose();
  });

  testWidgets('clearing filters restores data and listener replacements work',
      (tester) async {
    final store = RecordingFirestore();
    final oldFilter = PaginateFilterChangeListener();
    final newFilter = PaginateFilterChangeListener();
    await tester.pumpWidget(buildWidget(store, listeners: [oldFilter]));
    store.requests.single.respond([TestDocument('items/a', 'apple')]);
    await tester.pumpAndSettle();
    oldFilter.searchTerm = 'missing';
    await tester.pumpAndSettle();
    expect(find.text('No documents found'), findsOneWidget);
    oldFilter.searchTerm = '';
    await tester.pumpAndSettle();
    expect(find.text('items/a'), findsOneWidget);
    await tester.pumpWidget(buildWidget(store, listeners: [newFilter]));
    oldFilter.searchTerm = 'missing';
    await tester.pumpAndSettle();
    expect(find.text('items/a'), findsOneWidget);
    newFilter.searchTerm = 'missing';
    await tester.pumpAndSettle();
    expect(find.text('No documents found'), findsOneWidget);
    expect(store.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    oldFilter.dispose();
    newFilter.dispose();
  });

  testWidgets('errors reach the error widget', (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store));
    store.requests.single.fail(Exception('denied'));
    await tester.pumpAndSettle();
    expect(find.text('Error occurred: Exception: denied'), findsOneWidget);
  });

  testWidgets('collection-group documents use distinct widget keys',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(buildWidget(store, pageSize: 3));
    store.requests.single.respond([
      TestDocument('parents/one/items/shared'),
      TestDocument('parents/two/items/shared'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('parents/one/items/shared'), findsOneWidget);
    expect(find.text('parents/two/items/shared'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final builderType in PaginateBuilderType.values) {
    testWidgets('cached pages resume after confirmation in ${builderType.name}',
        (tester) async {
      final store = RecordingFirestore();
      final a = TestDocument('items/a');
      final b = TestDocument('items/b');
      final pageController = PageController(initialPage: 2);
      var loadedCount = 0;
      await tester.pumpWidget(buildWidget(store,
          isLive: true,
          builderType: builderType,
          pageController: pageController,
          onLoaded: (_) => loadedCount++));
      store.requests.single.respond([a, b], fromCache: true);
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(1));
      expect(loadedCount, 1);
      store.requests.single.respond([a, b], metadataOnly: true);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(store.requests, hasLength(2));
      expect(loadedCount, 1);
      store.requests.last.respond([]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      pageController.dispose();
    });
  }

  testWidgets('removing a filter listener restores the unfiltered list',
      (tester) async {
    final store = RecordingFirestore();
    final filter = PaginateFilterChangeListener()..searchTerm = 'missing';
    await tester.pumpWidget(buildWidget(store, listeners: [filter]));
    store.requests.single.respond([TestDocument('items/a', 'apple')]);
    await tester.pumpAndSettle();
    expect(find.text('No documents found'), findsOneWidget);
    await tester.pumpWidget(buildWidget(store));
    await tester.pumpAndSettle();
    expect(find.text('items/a'), findsOneWidget);
    expect(store.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    filter.dispose();
  });

  testWidgets('refresh can paginate while an older read is still pending',
      (tester) async {
    final store = RecordingFirestore();
    final refresh = PaginateRefreshedChangeListener();
    final a = TestDocument('items/a');
    final b = TestDocument('items/b');
    await tester.pumpWidget(buildWidget(store, listeners: [refresh]));
    store.requests.single.respond([a, b]);
    await tester.pump();
    await tester.pump();
    expect(store.requests, hasLength(2));
    final oldRead = store.requests.last;
    refresh.refreshed = true;
    await tester.pump();
    await tester.pump();
    expect(store.requests, hasLength(3));
    expect(find.text('items/a'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    store.requests.last.respond([a, b]);
    await tester.pump();
    await tester.pump();
    expect(store.requests, hasLength(4));
    expect(store.requests.last.query.cursor, same(b));
    // Completing the obsolete read must not overwrite the refreshed session.
    oldRead.respond([TestDocument('items/obsolete')]);
    store.requests.last.respond([TestDocument('items/current')]);
    await tester.pumpAndSettle();
    expect(find.text('items/obsolete'), findsNothing);
    expect(find.text('items/current'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    refresh.dispose();
  });

  for (final fails in [false, true]) {
    testWidgets(
        'refresh replaces retained items with ${fails ? 'an error' : 'empty results'}',
        (tester) async {
      final store = RecordingFirestore();
      final refresh = PaginateRefreshedChangeListener();
      await tester.pumpWidget(buildWidget(store, listeners: [refresh]));
      store.requests.single.respond([TestDocument('items/a')]);
      await tester.pumpAndSettle();
      refresh.refreshed = true;
      await tester.pump();
      await tester.pump();
      expect(find.text('items/a'), findsOneWidget);
      expect(store.requests, hasLength(2));
      if (fails) {
        store.requests.last.fail(Exception('refresh failed'));
      } else {
        store.requests.last.respond([]);
      }
      await tester.pumpAndSettle();
      expect(find.text('items/a'), findsNothing);
      expect(
          find.text(fails
              ? 'Error occurred: Exception: refresh failed'
              : 'No documents found'),
          findsOneWidget);
      expect(store.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      refresh.dispose();
    });
  }

  for (final builderType in PaginateBuilderType.values) {
    for (final isLive in [false, true]) {
      testWidgets(
          'refresh keeps visible items mounted in ${builderType.name} (live: $isLive)',
          (tester) async {
        final store = RecordingFirestore();
        final refresh = PaginateRefreshedChangeListener();
        Widget widget() => buildWidget(store,
            listeners: [refresh],
            isLive: isLive,
            globalLimit: 2,
            builderType: builderType,
            itemBuilder: (context, docs, index) =>
                CounterItem(path: docs[index].reference.path));
        await tester.pumpWidget(widget());
        store.requests.single.respond([
          TestDocument('items/a'),
          TestDocument('items/b'),
        ]);
        await tester.pumpAndSettle();
        await tester.tap(find.text('items/a: 0'));
        await tester.pump();
        expect(find.text('items/a: 1'), findsOneWidget);

        refresh.refreshed = true;
        await tester.pump();
        await tester.pump();
        expect(store.requests, hasLength(2));
        expect(find.text('items/a: 1'), findsOneWidget);
        // Parent rebuilds while the refresh is pending keep the same item state
        // and must not initiate additional reads.
        await tester.pumpWidget(widget());
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('items/a: 1'), findsOneWidget);
        expect(store.requests, hasLength(2));
        if (isLive) {
          // An empty local cache is not a confirmed empty result. Keep the
          // existing items visible while the refreshed listener waits online.
          store.requests.last.respond([], fromCache: true);
          await tester.pump();
          await tester.pump();
          expect(find.text('items/a: 1'), findsOneWidget);
          expect(store.requests, hasLength(2));
        }
        store.requests.last.respond([
          TestDocument('items/a'),
          TestDocument('items/c'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('items/a: 1'), findsOneWidget);
        expect(find.text('items/b: 0'), findsNothing);
        expect(store.requests, hasLength(2));
        await tester.pumpWidget(const SizedBox());
        refresh.dispose();
      });
    }

    testWidgets('live reordering preserves item state in ${builderType.name}',
        (tester) async {
      final store = RecordingFirestore();
      final controller = PageController();
      final a = TestDocument('items/a');
      final b = TestDocument('items/b');
      await tester.pumpWidget(buildWidget(store,
          isLive: true,
          globalLimit: 2,
          builderType: builderType,
          pageController: controller,
          itemBuilder: (context, docs, index) =>
              CounterItem(path: docs[index].reference.path)));
      store.requests.single.respond([a, b]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('items/a: 0'));
      await tester.pump();
      expect(find.text('items/a: 1'), findsOneWidget);
      store.requests.single.respond([b, a]);
      await tester.pumpAndSettle();
      if (builderType == PaginateBuilderType.pageView) {
        controller.jumpToPage(1);
        await tester.pumpAndSettle();
      }
      expect(find.text('items/a: 1'), findsOneWidget);
      expect(store.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}

class CounterItem extends StatefulWidget {
  const CounterItem({super.key, required this.path});

  final String path;

  @override
  State<CounterItem> createState() => _CounterItemState();
}

class _CounterItemState extends State<CounterItem>
    with AutomaticKeepAliveClientMixin<CounterItem> {
  int count = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox(
      height: 100,
      child: TextButton(
        onPressed: () => setState(() => count++),
        child: Text('${widget.path}: $count'),
      ),
    );
  }
}
