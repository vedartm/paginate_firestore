import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginate_firestore/bloc/pagination_listeners.dart';
import 'package:paginate_firestore/paginate_firestore.dart';
import 'package:paginate_firestore/widgets/bottom_loader.dart';

import 'support/firestore_fakes.dart';

Widget pagination(
  RecordingFirestore store, {
  int? budget,
  int pageSize = 2,
  int? globalLimit,
  double itemExtent = 50,
  bool hidden = false,
  bool hideLaterItems = false,
  bool reverse = false,
  bool shrinkWrap = false,
  bool nested = false,
  bool live = false,
  bool metadata = false,
  Axis axis = Axis.vertical,
  PaginateBuilderType type = PaginateBuilderType.listView,
  List<ChangeNotifier>? listeners,
  ScrollController? controller,
  PageController? pageController,
  EdgeInsets padding = EdgeInsets.zero,
  Widget separator = const SizedBox.shrink(),
}) {
  final view = PaginateFirestore(
    query: store.query,
    itemsPerPage: pageSize,
    // The public default is separately asserted below.
    maxAutomaticFillPages: budget ?? 3,
    itemsGlobalLimit: globalLimit,
    loadMoreLabel: 'Načítať ďalšie',
    reverse: reverse,
    shrinkWrap: shrinkWrap || nested,
    scrollDirection: axis,
    scrollController: controller,
    pageController: pageController,
    padding: padding,
    separator: separator,
    isLive: live,
    includeMetadataChanges: metadata,
    listeners: listeners,
    itemBuilderType: type,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisExtent: itemExtent,
    ),
    itemBuilder: (context, docs, index) =>
        hidden || (hideLaterItems && index >= 2)
            ? const SizedBox.shrink()
            : SizedBox(
                width: itemExtent,
                height: itemExtent,
                child: Text(docs[index].reference.path),
              ),
  );
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 300,
          child: nested
              ? SingleChildScrollView(
                  child: Column(children: [
                    view,
                    const SizedBox(height: 1000),
                  ]),
                )
              : view,
        ),
      ),
    ),
  );
}

List<TestDocument> page(int index) => [
      TestDocument('items/${index * 2}', 'match'),
      TestDocument('items/${index * 2 + 1}', 'match'),
    ];

Future<void> frames(WidgetTester tester, [int count = 5]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final button = find.widgetWithText(TextButton, 'Načítať ďalšie');

  test('automatic fill defaults to three additional pages', () {
    final widget = PaginateFirestore(
      query: RecordingFirestore().query,
      itemBuilderType: PaginateBuilderType.listView,
      itemBuilder: (_, docs, index) => const SizedBox(),
    );
    expect(widget.maxAutomaticFillPages, 3);
  });

  testWidgets('automatic filling never flashes the manual button between pages',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, hidden: true));
    for (var i = 0; i < 3; i++) {
      store.requests.last.respond(page(i));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(button, findsNothing);
      }
      expect(store.requests, hasLength(i + 2));
      expect(find.byType(BottomLoader), findsOneWidget);
    }
    store.requests.last.respond(page(3));
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(store.requests, hasLength(4));
  });

  testWidgets('cached results show a spinner while waiting for the server',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, live: true, budget: 0));
    store.requests.single.respond(page(0), fromCache: true);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(button, findsNothing);
    }
    expect(find.byType(BottomLoader), findsOneWidget);
    expect(store.requests, hasLength(1));
    store.requests.single.respond(page(0), metadataOnly: true);
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(store.requests, hasLength(1));
  });

  for (final itemExtent in [100.0, 150.0]) {
    testWidgets('grid loader sharing a row respects actual height $itemExtent',
        (tester) async {
      final store = RecordingFirestore();
      await tester.pumpWidget(pagination(store,
          type: PaginateBuilderType.gridView,
          pageSize: 3,
          itemExtent: itemExtent));
      store.requests.single.respond([
        TestDocument('items/a'),
        TestDocument('items/b'),
        TestDocument('items/c'),
      ]);
      await frames(tester);
      // Three documents occupy two rows; the control shares the second row.
      // Two 100px rows need another page, but two 150px rows fill the viewport.
      expect(store.requests, hasLength(itemExtent == 100 ? 2 : 1));
      if (itemExtent == 100) {
        final loader = tester.getRect(find.byType(BottomLoader));
        final last = tester.getRect(find.byKey(const ValueKey('items/c')));
        expect(loader.top, last.top);
        expect(loader.left, last.right);
        store.requests.last.respond([
          TestDocument('items/d'),
          TestDocument('items/e'),
          TestDocument('items/f'),
        ]);
      }
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(itemExtent == 100 ? 2 : 1));
    });
  }

  for (final type in [
    PaginateBuilderType.listView,
    PaginateBuilderType.gridView
  ]) {
    for (final reverse in [false, true]) {
      testWidgets(
          '${type.name} normal pagination never offers manual loading between flings, '
          'reverse=$reverse', (tester) async {
        final store = RecordingFirestore();
        final controller = ScrollController();
        Widget build() => pagination(store,
            type: type,
            reverse: reverse,
            controller: controller,
            live: true,
            itemExtent: type == PaginateBuilderType.gridView ? 400 : 200);
        await tester.pumpWidget(build());
        store.requests.single.respond(page(0));
        await tester.pumpAndSettle();
        // Normal filled content must not select the manual fallback, even
        // during the idle gap between consecutive fast gestures.
        expect(button, findsNothing);
        for (var nextPage = 1; nextPage <= 3; nextPage++) {
          controller.jumpTo(controller.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(store.requests, hasLength(nextPage));
          expect(button, findsNothing);
          await tester.fling(find.byType(CustomScrollView),
              Offset(0, reverse ? 80 : -80), 2000);
          await frames(tester);
          expect(store.requests, hasLength(nextPage + 1));
          expect(button, findsNothing);
          store.requests.last.respond(page(nextPage));
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(button, findsNothing);
          }
          await tester.pumpAndSettle();
          expect(button, findsNothing);
          expect(store.requests, hasLength(nextPage + 1));
          store.requests.last.respond(page(nextPage), metadataOnly: true);
          await tester.pumpWidget(build());
          await tester.pumpAndSettle();
          expect(button, findsNothing);
          expect(store.requests, hasLength(nextPage + 1));
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });

      for (final axis in Axis.values) {
        testWidgets(
            '${type.name} keeps the loader inside padding, '
            '${axis.name}, reverse=$reverse', (tester) async {
          final store = RecordingFirestore();
          await tester.pumpWidget(pagination(store,
              type: type,
              axis: axis,
              reverse: reverse,
              padding: const EdgeInsets.fromLTRB(17, 23, 41, 29),
              separator: const SizedBox(width: 13, height: 13)));
          store.requests.single.respond(page(0));
          await frames(tester);
          expect(store.requests, hasLength(2));
          final loader = tester.getRect(find.byType(BottomLoader));
          final first = tester.getRect(find.byKey(const ValueKey('items/0')));
          final last = tester.getRect(find.byKey(const ValueKey('items/1')));
          final gap = type == PaginateBuilderType.listView ? 13 : 0;
          if (axis == Axis.vertical) {
            expect(loader.left, first.left);
            expect(loader.right, first.right);
            expect(reverse ? loader.bottom : loader.top,
                reverse ? last.top - gap : last.bottom + gap);
          } else {
            expect(loader.top, first.top);
            expect(loader.bottom, first.bottom);
            expect(reverse ? loader.right : loader.left,
                reverse ? last.left - gap : last.right + gap);
          }
          expect(
              find.ancestor(
                  of: find.byType(BottomLoader),
                  matching: find.byType(SliverPadding)),
              findsOneWidget);
        });
      }

      testWidgets(
          '${type.name}, reverse=$reverse fills then waits for scrolling',
          (tester) async {
        final store = RecordingFirestore();
        final controller = ScrollController();
        await tester.pumpWidget(pagination(store,
            type: type,
            reverse: reverse,
            controller: controller,
            itemExtent: type == PaginateBuilderType.gridView ? 100 : 50));
        // Each page contributes 100 px of actual content to a 300 px viewport.
        for (var i = 0; i < 3; i++) {
          expect(store.requests, hasLength(i + 1));
          store.requests.last.respond(page(i));
          await frames(tester);
        }
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(3));
        expect(button, findsNothing);

        // Programmatic movement and the continuously visible control do not
        // spend the remaining automatic allowance after the viewport is full.
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(3));
        // Browsing back through already loaded items must not fetch more just
        // because the gesture started near the pagination control.
        await tester.drag(
            find.byType(CustomScrollView), Offset(0, reverse ? -30 : 30));
        await frames(tester);
        expect(store.requests, hasLength(3));
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.drag(
            find.byType(CustomScrollView), Offset(0, reverse ? 100 : -100));
        await frames(tester);
        expect(store.requests, hasLength(4));
        expect(store.requests.last.query.cursor!.reference.path, 'items/5');
        // Scrolling/rebuilding during an outstanding request cannot overlap it.
        await tester.drag(
            find.byType(CustomScrollView), Offset(0, reverse ? 100 : -100));
        await frames(tester);
        expect(store.requests, hasLength(4));
        store.requests.last.respond(page(3));
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(4));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });

      testWidgets(
          '${type.name} fast scrolling shows the spinner in the request frame, '
          'reverse=$reverse', (tester) async {
        final store = RecordingFirestore();
        final controller = ScrollController();
        await tester.pumpWidget(pagination(store,
            type: type,
            reverse: reverse,
            controller: controller,
            itemExtent: type == PaginateBuilderType.gridView ? 400 : 200,
            budget: 0));
        store.requests.single.respond(page(0));
        await tester.pumpAndSettle();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final idleExtent = controller.position.maxScrollExtent;
        final gesture = await tester.startGesture(const Offset(150, 150));
        await gesture.moveBy(Offset(0, reverse ? 100 : -100));
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (store.requests.length > 1) {
            expect(button, findsNothing);
            expect(find.byType(BottomLoader), findsOneWidget);
          }
          expect(controller.position.maxScrollExtent, idleExtent);
        }
        expect(store.requests, hasLength(2));
        await gesture.up();
        store.requests.last.respond(page(1));
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(2));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }
  }

  for (final reverse in [false, true]) {
    for (final axis in Axis.values) {
      testWidgets(
          'mouse wheel respects direction in ${axis.name}, reverse=$reverse',
          (tester) async {
        final store = RecordingFirestore();
        final controller = ScrollController();
        await tester.pumpWidget(pagination(store,
            itemExtent: 200,
            controller: controller,
            axis: axis,
            reverse: reverse));
        store.requests.single.respond(page(0));
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(1));
        controller.jumpTo(controller.position.maxScrollExtent - 30);
        await tester.pumpAndSettle();
        final animation = controller.animateTo(
          controller.position.maxScrollExtent - 10,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
        await tester.pumpAndSettle();
        await animation;
        expect(store.requests, hasLength(1));

        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        pointer.hover(tester.getCenter(find.byType(CustomScrollView)));
        Offset delta(double value) {
          final physicalDelta = reverse ? -value : value;
          return axis == Axis.vertical
              ? Offset(0, physicalDelta)
              : Offset(physicalDelta, 0);
        }

        // A wheel event completes its scroll notifications before the frame.
        // Moving away must do nothing; moving toward the end must still load.
        final previousOffset = controller.offset;
        await tester.sendEventToBinding(pointer.scroll(delta(-10)));
        await tester.pumpAndSettle();
        expect(controller.offset, lessThan(previousOffset));
        expect(store.requests, hasLength(1));
        await tester.sendEventToBinding(pointer.scroll(delta(10)));
        await frames(tester);
        expect(store.requests, hasLength(2));
        await tester.sendEventToBinding(pointer.scroll(delta(5)));
        await frames(tester);
        expect(store.requests, hasLength(2));
        store.requests.last.respond(page(1));
        await tester.pumpAndSettle();
        expect(store.requests, hasLength(2));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }

    testWidgets('fling approaching the end loads once, reverse=$reverse',
        (tester) async {
      final store = RecordingFirestore();
      final controller = ScrollController();
      await tester.pumpWidget(pagination(store,
          itemExtent: 250,
          hideLaterItems: true,
          controller: controller,
          reverse: reverse));
      store.requests.single.respond(page(0));
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(1));
      expect(controller.position.extentAfter,
          greaterThan(controller.position.viewportDimension * .2));
      await tester.fling(
          find.byType(CustomScrollView), Offset(0, reverse ? 100 : -100), 1500);
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (controller.position.isScrollingNotifier.value ||
            store.requests.length > 1) {
          expect(button, findsNothing);
        }
      }
      expect(store.requests, hasLength(2));
      // A quick response with no new visible height must not let the rest of
      // the fling or bounce request further pages.
      store.requests.last.respond(page(1));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (controller.position.isScrollingNotifier.value) {
          expect(button, findsNothing);
        }
        expect(store.requests, hasLength(2));
      }
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(2));
      expect(button, findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
        variant: const TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));

    testWidgets(
        'zero-height rows spend the budget; one tap reads one page '
        '(reverse=$reverse)', (tester) async {
      final store = RecordingFirestore();
      Widget build() => pagination(store, hidden: true, reverse: reverse);
      await tester.pumpWidget(build());
      for (var i = 0; i < 4; i++) {
        expect(store.requests, hasLength(i + 1));
        store.requests.last.respond(page(i));
        await frames(tester);
      }
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(4));
      expect(button, findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(build());
      }
      expect(store.requests, hasLength(4));
      await tester.tap(button);
      await frames(tester);
      expect(store.requests, hasLength(5));
      store.requests.last.respond(page(4));
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(5));
      expect(button, findsOneWidget);
      expect(store.requests.map((r) => r.query).toSet(), hasLength(5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'a zero budget disables filling; a tap still requests just one page',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, budget: 0, hidden: true));
    store.requests.single.respond(page(0));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    await tester.tap(button);
    await frames(tester);
    expect(store.requests, hasLength(2));
    store.requests.last.respond(page(1));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
  });

  testWidgets('manual fallback disappears when its page fills the viewport',
      (tester) async {
    final store = RecordingFirestore();
    final controller = ScrollController();
    await tester
        .pumpWidget(pagination(store, budget: 1, controller: controller));
    store.requests.single.respond(page(0));
    await frames(tester);
    store.requests.last.respond(page(1));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await frames(tester);
    expect(store.requests, hasLength(3));
    store.requests.last.respond(page(2));
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    expect(find.byType(BottomLoader), findsOneWidget);
    expect(store.requests, hasLength(3));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('one continuing gesture cannot chain no-growth pages',
      (tester) async {
    final store = RecordingFirestore();
    await tester
        .pumpWidget(pagination(store, itemExtent: 150, hideLaterItems: true));
    store.requests.single.respond(page(0));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    final gesture = await tester.startGesture(const Offset(150, 150));
    await gesture.moveBy(const Offset(0, -60));
    await frames(tester);
    expect(store.requests, hasLength(2));
    store.requests.last.respond(page(1));
    await frames(tester);
    expect(button, findsNothing);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await frames(tester);
      expect(store.requests, hasLength(2));
      expect(button, findsNothing);
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    expect(button, findsNothing);
    // Keeping the placeholder does not turn a continuing gesture or idle
    // rebuild into more reads. A fresh user scroll still requests one page.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await frames(tester);
    expect(store.requests, hasLength(3));
    expect(button, findsNothing);
  });

  testWidgets(
      'live updates and filtering cannot restart a completed fill cycle',
      (tester) async {
    final store = RecordingFirestore();
    final filter = PaginateFilterChangeListener();
    Widget build() =>
        pagination(store, live: true, itemExtent: 150, listeners: [filter]);
    await tester.pumpWidget(build());
    store.requests.single.respond(page(0));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    for (var i = 0; i < 5; i++) {
      filter.searchTerm = i.isEven ? 'missing' : '';
      store.requests.single.respond(page(0));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
    }
    expect(store.requests, hasLength(1));
    expect(button, findsOneWidget);
    // A manual page still must not restart the unused three-page allowance.
    await tester.tap(button);
    await frames(tester);
    expect(store.requests, hasLength(2));
    store.requests.last.respond(page(1));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    filter.dispose();
  });

  testWidgets('a short page confirms the end before the fill budget is spent',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, hidden: true));
    store.requests.single.respond(page(0));
    await frames(tester);
    store.requests.last.respond([TestDocument('items/last')]);
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    expect(button, findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
  });

  testWidgets('global limit truncates the final request and stops filling',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, hidden: true, globalLimit: 3));
    store.requests.single.respond(page(0));
    await frames(tester);
    expect(store.requests, hasLength(2));
    expect(store.requests.last.query.pageLimit, 1);
    store.requests.last.respond([TestDocument('items/last')]);
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(2));
    expect(button, findsNothing);
  });

  testWidgets(
      'live inserts after a confirmed end do not restart automatic filling',
      (tester) async {
    final store = RecordingFirestore();
    await tester.pumpWidget(pagination(store, live: true));
    store.requests.single.respond([page(0).first]);
    await tester.pumpAndSettle();
    expect(button, findsNothing);
    store.requests.single.respond(page(0));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(1));
    expect(button, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final live in [false, true]) {
    testWidgets(
        'error and explicit retry stop filling and retain pages (live=$live)',
        (tester) async {
      final store = RecordingFirestore();
      final retry = PaginateRetryChangeListener();
      Widget build() => pagination(store, live: live, listeners: [retry]);
      await tester.pumpWidget(build());
      store.requests.single.respond(page(0));
      await frames(tester);
      final failedQuery = store.requests.last.query;
      store.requests.last.fail(Exception('denied'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(build());
      }
      expect(store.requests, hasLength(2));
      for (var i = 0; i < 5; i++) {
        retry.retry();
      }
      await frames(tester);
      expect(store.requests, hasLength(3));
      expect(store.requests.last.query, failedQuery);
      store.requests.last.respond(page(1));
      await tester.pumpAndSettle();
      expect(find.text('items/0'), findsOneWidget);
      expect(find.text('items/2'), findsOneWidget);
      expect(store.requests.first.cancelled, isFalse);
      expect(button, findsOneWidget);
      expect(store.requests, hasLength(3));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(3));
      await tester.pumpWidget(const SizedBox());
      retry.dispose();
    });
  }

  for (final type in [
    PaginateBuilderType.listView,
    PaginateBuilderType.gridView
  ]) {
    testWidgets(
        'filtered pages, rebuilds and live confirmations share one budget '
        'in ${type.name}', (tester) async {
      final store = RecordingFirestore();
      final filter = PaginateFilterChangeListener()..searchTerm = 'missing';
      Widget build(bool metadata) => pagination(store,
          type: type, live: true, metadata: metadata, listeners: [filter]);
      await tester.pumpWidget(build(false));
      for (var i = 0; i < 4; i++) {
        expect(store.requests, hasLength(i + 1));
        store.requests.last.respond(page(i), fromCache: true);
        await frames(tester);
        expect(store.requests, hasLength(i + 1));
        store.requests.last.respond(page(i), metadataOnly: true);
        await frames(tester);
      }
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(4));
      expect(button, findsOneWidget);
      for (var i = 0; i < 6; i++) {
        filter.searchTerm = i.isEven ? 'another missing term' : 'missing';
        store.requests.first.respond(page(0), metadataOnly: i.isEven);
        await tester.pumpWidget(build(i.isEven));
        await frames(tester);
      }
      expect(store.requests, hasLength(4));
      expect(button, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      filter.dispose();
    });

    testWidgets('unbounded nested ${type.name} uses bounded fallback',
        (tester) async {
      final store = RecordingFirestore();
      await tester.pumpWidget(pagination(store, nested: true, type: type));
      store.requests.single.respond(page(0));
      await frames(tester);
      expect(store.requests, hasLength(2));
      store.requests.last.respond(page(1));
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -100));
        await tester.pumpAndSettle();
      }
      expect(store.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('bounded shrink-wrapped and horizontal lists fill their viewport',
      (tester) async {
    for (final axis in Axis.values) {
      final store = RecordingFirestore();
      await tester.pumpWidget(pagination(store, shrinkWrap: true, axis: axis));
      for (var i = 0; i < 3; i++) {
        expect(store.requests, hasLength(i + 1));
        store.requests.last.respond(page(i));
        await frames(tester);
      }
      await tester.pumpAndSettle();
      expect(store.requests, hasLength(3));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('refresh and new query reset the fill budget', (tester) async {
    final first = RecordingFirestore();
    final second = RecordingFirestore();
    final refresh = PaginateRefreshedChangeListener();
    Widget build(RecordingFirestore store) =>
        pagination(store, hidden: true, listeners: [refresh]);
    await tester.pumpWidget(build(first));
    for (var i = 0; i < 4; i++) {
      first.requests.last.respond(page(i));
      await frames(tester);
    }
    expect(first.requests, hasLength(4));
    refresh.refreshed = true;
    await frames(tester);
    for (var i = 0; i < 4; i++) {
      expect(first.requests, hasLength(5 + i));
      first.requests.last.respond(page(i));
      await frames(tester);
    }
    expect(first.requests, hasLength(8));
    await tester.pumpWidget(build(second));
    for (var i = 0; i < 4; i++) {
      expect(second.requests, hasLength(i + 1));
      second.requests.last.respond(page(i));
      await frames(tester);
    }
    expect(second.requests, hasLength(4));
    await tester.pumpWidget(const SizedBox());
    refresh.dispose();
  });

  testWidgets('PageView retains one automatic prefetch when its tail is built',
      (tester) async {
    final store = RecordingFirestore();
    final controller = PageController(initialPage: 2);
    await tester.pumpWidget(pagination(store,
        type: PaginateBuilderType.pageView, pageController: controller));
    store.requests.single.respond(page(0));
    await frames(tester);
    expect(store.requests, hasLength(2));
    store.requests.last.respond(page(1));
    await tester.pumpAndSettle();
    controller.jumpToPage(4);
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    expect(store.requests, hasLength(2));
    await tester.tap(button);
    await frames(tester);
    expect(store.requests, hasLength(3));
    store.requests.last.respond(page(2));
    await tester.pumpAndSettle();
    expect(store.requests, hasLength(3));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
