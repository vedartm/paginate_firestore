library;

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/rendering.dart'
    show
        RenderAbstractViewport,
        RenderSliver,
        RenderSliverGrid,
        ScrollDirection;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'bloc/pagination_cubit.dart';
import 'bloc/pagination_listeners.dart';
import 'widgets/bottom_loader.dart';
import 'widgets/empty_display.dart';
import 'widgets/empty_separator.dart';
import 'widgets/error_display.dart';
import 'widgets/initial_loader.dart';

class PaginateFirestore extends StatefulWidget {
  const PaginateFirestore({
    super.key,
    required this.itemBuilder,
    required this.query,
    required this.itemBuilderType,
    this.gridDelegate =
        const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
    this.startAfterDocument,
    this.itemsPerPage = 15,
    this.itemsGlobalLimit,
    this.onError,
    this.onReachedEnd,
    this.onLoaded,
    this.onEmpty = const EmptyDisplay(),
    this.separator = const EmptySeparator(),
    this.initialLoader = const InitialLoader(),
    this.bottomLoader = const BottomLoader(),
    this.loadMoreLabel = 'Load more',
    this.maxAutomaticFillPages = 3,
    this.shrinkWrap = false,
    this.reverse = false,
    this.scrollDirection = Axis.vertical,
    this.padding = const EdgeInsets.all(0),
    this.physics,
    this.listeners,
    this.scrollController,
    this.allowImplicitScrolling = false,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.pageController,
    this.onPageChanged,
    this.header,
    this.footer,
    this.isLive = false,
    this.isAllItemsLive = true,
    this.includeMetadataChanges = false,
    this.options,
  })  : assert(itemsPerPage > 0),
        assert(maxAutomaticFillPages >= 0),
        assert(itemsGlobalLimit == null || itemsGlobalLimit >= 0);

  final Widget bottomLoader;

  /// Label for the manual loading button. Pass your app's localized string.
  final String loadMoreLabel;

  /// Maximum additional page requests used to fill the initial viewport.
  /// Defaults to 3; zero disables automatic filling. Hidden items count too.
  /// Refreshes and new pagination queries reset this budget; retries do not.
  /// This is not a cap on Firestore billing, live reads, or user-requested pages.
  /// PageView and unbounded nested layouts prefetch at most one extra page.
  final int maxAutomaticFillPages;

  final Widget onEmpty;
  final SliverGridDelegate gridDelegate;
  final Widget initialLoader;
  final PaginateBuilderType itemBuilderType;
  final int itemsPerPage;
  final List<ChangeNotifier>? listeners;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final Query query;
  final bool reverse;
  final bool allowImplicitScrolling;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final ScrollController? scrollController;
  final PageController? pageController;
  final Axis scrollDirection;
  final Widget separator;
  final bool shrinkWrap;
  final bool isLive;
  final DocumentSnapshot? startAfterDocument;
  final Widget? header;
  final Widget? footer;

  /// Maximum document slots requested across pages, including the first page.
  /// The final query is limited to the remaining allowance. Zero issues no reads.
  /// This does not cap reads billed for live updates, reconnects, or refreshes.
  final int? itemsGlobalLimit;

  /// Use this only if `isLive = true`
  /// If true (the default), each fetched page has a live listener.
  /// If false, only the first page is live; later pages use one-time reads.
  /// Pages have fixed start cursors and limits. Inserts, deletes, or changes to
  /// sort fields can move documents between pages; refresh to reconcile them.
  /// Larger pages reduce listener count but can read more unseen documents.
  final bool isAllItemsLive;

  /// Options for one-time reads, including later pages when only page one is live.
  final GetOptions? options;

  /// Use this only if `isLive = true`
  final bool includeMetadataChanges;

  final Widget Function(Exception)? onError;

  final Widget Function(BuildContext, List<DocumentSnapshot>, int) itemBuilder;

  final void Function(PaginationLoaded)? onReachedEnd;

  final void Function(PaginationLoaded)? onLoaded;

  final void Function(int)? onPageChanged;

  @override
  State<PaginateFirestore> createState() => _PaginateFirestoreState();
}

class _PaginateFirestoreState extends State<PaginateFirestore> {
  PaginationCubit? _cubit;
  // Display-only state keeps items mounted during a refresh of the same query.
  // Request cursors and budgets still belong to the new pagination session.
  PaginationLoaded? _lastLoadedState;
  Future<void>? _nextPageRequest;
  final _paginationControlKey = GlobalKey();
  final _itemsSliverKey = GlobalKey();
  bool _showManualLoadMore = false;
  int _automaticFillPages = 0;
  bool _automaticFillStopped = false;
  bool _scrollGestureAllowed = false;
  bool _scrollRequestAllowed = false;
  bool _paginationCheckScheduled = false;
  double _availableViewportExtent = double.infinity;
  List<ChangeNotifier> _attachedListeners = [];

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification ||
            notification is ScrollEndNotification) {
          // Rebuild cached controls when activity changes. Dimension changes
          // can end/start a bounce during layout, when setState is not safe.
          if (WidgetsBinding.instance.schedulerPhase ==
              SchedulerPhase.persistentCallbacks) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          } else {
            setState(() {});
          }
        }
        if (notification is UserScrollNotification) {
          _scrollGestureAllowed =
              notification.direction == ScrollDirection.reverse &&
                  _nextPageRequest == null &&
                  !_cubit!.isFetching;
        }
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _scrollGestureAllowed =
              _nextPageRequest == null && !_cubit!.isFetching;
        }
        // Increasing scroll offsets approach the next page, including in a
        // reversed view. Starting a drag alone does not establish its direction.
        final movingToEnd = notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) > 0 ||
            notification is OverscrollNotification &&
                notification.overscroll > 0;
        if (movingToEnd &&
            _scrollGestureAllowed &&
            _nextPageRequest == null &&
            !_cubit!.isFetching &&
            notification.metrics.extentAfter <=
                notification.metrics.viewportDimension * .2) {
          // Consume this scroll action, including its ballistic updates. A fast
          // no-growth response must not turn a continuing fling into a loop.
          _scrollGestureAllowed = false;
          _scheduleScrollRequest();
        }
        return false;
      },
      child: BlocConsumer<PaginationCubit, PaginationState>(
        bloc: _cubit,
        buildWhen: (prev, curr) => prev != curr,
        listener: (context, state) {
          if (state is PaginationInitial) {
            // A previous one-time read may still be in flight. It must not
            // block the loader in the refreshed pagination session.
            _resetAutomaticFill();
          }
          if (state is PaginationError) {
            _lastLoadedState = null;
            // A successful explicit retry restores pages, but does not grant
            // an additional automatic fetch beyond the failed request.
            _automaticFillStopped = true;
            _scrollRequestAllowed = false;
            _scrollGestureAllowed = false;
          }
          if (state is PaginationLoaded) {
            _lastLoadedState = state;
            widget.onLoaded?.call(state);
            if (state.hasReachedEnd) {
              _automaticFillStopped = true;
              widget.onReachedEnd?.call(state);
            }
          }
        },
        builder: (context, state) {
          if (state is PaginationInitial && _lastLoadedState == null) {
            return widget.initialLoader;
          } else if (state is PaginationError) {
            return (widget.onError != null)
                ? widget.onError!(state.error)
                : ErrorDisplay(exception: state.error);
          } else {
            final loadedState =
                state is PaginationLoaded ? state : _lastLoadedState!;
            if (loadedState.documentSnapshots.isEmpty &&
                (loadedState.hasReachedEnd ||
                    widget.itemBuilderType == PaginateBuilderType.pageView)) {
              return widget.onEmpty;
            }
            return LayoutBuilder(builder: (context, constraints) {
              _availableViewportExtent = widget.scrollDirection == Axis.vertical
                  ? constraints.maxHeight
                  : constraints.maxWidth;
              _schedulePaginationCheck();
              return widget.itemBuilderType == PaginateBuilderType.listView
                  ? _buildListView(loadedState)
                  : widget.itemBuilderType == PaginateBuilderType.gridView
                      ? _buildGridView(loadedState)
                      : _buildPageView(loadedState);
            });
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    for (var remove in _listenerRemovers) {
      remove();
    }
    _cubit?.close();
    super.dispose();
  }

  final _listenerRemovers = <VoidCallback>[];

  @override
  void initState() {
    super.initState();
    _createCubit();
    _attachListeners();
  }

  @override
  void didUpdateWidget(covariant PaginateFirestore oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOptions = oldWidget.options ?? const GetOptions();
    final newOptions = widget.options ?? const GetOptions();
    final usesOneTimeReads = !widget.isLive || !widget.isAllItemsLive;
    var restarted = false;
    if (oldWidget.query != widget.query ||
        oldWidget.itemsPerPage != widget.itemsPerPage ||
        oldWidget.itemsGlobalLimit != widget.itemsGlobalLimit ||
        !_hasSameStartCursor(oldWidget) ||
        oldWidget.isLive != widget.isLive ||
        (widget.isLive && oldWidget.isAllItemsLive != widget.isAllItemsLive) ||
        (usesOneTimeReads &&
            (oldOptions.source != newOptions.source ||
                oldOptions.serverTimestampBehavior !=
                    newOptions.serverTimestampBehavior))) {
      _cubit?.close();
      _createCubit();
      restarted = true;
    }
    _cubit?.updateMetadataChanges(widget.includeMetadataChanges);
    if (restarted || !listEquals(_attachedListeners, widget.listeners ?? [])) {
      for (final remove in _listenerRemovers) {
        remove();
      }
      _listenerRemovers.clear();
      _attachListeners();
    }
  }

  bool _hasSameStartCursor(PaginateFirestore oldWidget) {
    final oldCursor = oldWidget.startAfterDocument;
    final newCursor = widget.startAfterDocument;
    if (identical(oldCursor, newCursor)) return true;
    if (oldCursor == null || newCursor == null) return false;
    try {
      // Query equality compares the document path and ordered cursor values.
      // Snapshot identity and changes to unrelated fields do not affect it.
      return oldWidget.query.startAfterDocument(oldCursor) ==
          widget.query.startAfterDocument(newCursor);
    } catch (_) {
      // Let the cubit report invalid cursors through the normal error state.
      return false;
    }
  }

  void _attachListeners() {
    _attachedListeners = List.of(widget.listeners ?? []);
    var initialFilter = '';
    for (var listener in _attachedListeners) {
      VoidCallback remover = () {};
      if (listener is PaginateRefreshedChangeListener) {
        void fn() {
          if (listener.refreshed) {
            _cubit?.refreshPaginatedList();
          }
        }

        listener.addListener(fn);
        remover = () => listener.removeListener(fn);
      } else if (listener is PaginateRetryChangeListener) {
        void fn() {
          _cubit?.retryPaginatedList();
        }

        listener.addListener(fn);
        remover = () => listener.removeListener(fn);
      } else if (listener is PaginateFilterChangeListener) {
        void fn() {
          _cubit?.filterPaginatedList(listener.searchTerm);
        }

        listener.addListener(fn);
        initialFilter = listener.searchTerm;
        remover = () => listener.removeListener(fn);
      }
      _listenerRemovers.add(remover);
    }
    _cubit?.filterPaginatedList(initialFilter);
  }

  void _createCubit() {
    _lastLoadedState = null;
    _resetAutomaticFill();
    _cubit = PaginationCubit(
      widget.query,
      widget.itemsPerPage,
      widget.startAfterDocument,
      isLive: widget.isLive,
      isAllItemsLive: widget.isAllItemsLive,
      itemsGlobalLimit: widget.itemsGlobalLimit,
      includeMetadataChanges: widget.includeMetadataChanges,
      options: widget.options,
    )..fetchPaginatedList();
  }

  void _resetAutomaticFill() {
    _nextPageRequest = null;
    _automaticFillPages = 0;
    _automaticFillStopped = false;
    _scrollRequestAllowed = false;
    _scrollGestureAllowed = false;
    _showManualLoadMore = false;
  }

  void _scheduleScrollRequest() {
    if (_scrollRequestAllowed) return;
    _scrollRequestAllowed = true;
    // Scroll notifications may arrive during layout. Start the request before
    // the next build, so that frame paints the spinner along with the request.
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      if (!mounted || !_scrollRequestAllowed) return;
      _scrollRequestAllowed = false;
      _checkPaginationLayout(scrollRequested: true);
    });
  }

  void _schedulePaginationCheck() {
    if (_paginationCheckScheduled) return;
    _paginationCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paginationCheckScheduled = false;
      if (mounted) _checkPaginationLayout();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _checkPaginationLayout({bool scrollRequested = false}) {
    if (_nextPageRequest != null || _scrollRequestAllowed) return;
    final cubit = _cubit!;
    final state = cubit.state;
    if (state is! PaginationLoaded || state.hasReachedEnd) return;
    final controlContext = _paginationControlKey.currentContext;
    final scrollContext = _itemsSliverKey.currentContext ?? controlContext;
    if (scrollContext == null) return;
    final position = Scrollable.maybeOf(scrollContext)?.position;
    if (position == null || !position.hasContentDimensions) return;

    // Join an in-flight initial/cache confirmation without spending the budget.
    // Metadata-only confirmation need not emit another loaded state.
    if (cubit.isFetching) {
      _fetchNextPage();
      return;
    }

    final unbounded = !_availableViewportExtent.isFinite;
    final fallback =
        widget.itemBuilderType == PaginateBuilderType.pageView || unbounded;
    // An unbounded inner scroll view cannot identify the outer visible end.
    // Even gestures accepted by that inner view must use the manual fallback.
    if (!unbounded &&
        scrollRequested &&
        position.extentAfter <= position.viewportDimension * .2) {
      _automaticFillStopped = true;
      _fetchNextPage();
      return;
    }
    // PageView only prefetches when its trailing page is built.
    if (fallback && controlContext == null) return;

    if (!fallback) {
      if (_availableViewportExtent <= 0 || position.viewportDimension <= 0) {
        return;
      }
      // A lazy list/grid whose tail is not built already fills its viewport.
      if (controlContext == null) {
        _automaticFillStopped = true;
        _setManualControl(false);
        return;
      }
      final control = controlContext.findRenderObject();
      if (control is! RenderBox || !control.hasSize) return;
      var controlExtent = widget.scrollDirection == Axis.vertical
          ? control.size.height
          : control.size.width;
      if (widget.itemBuilderType == PaginateBuilderType.gridView) {
        final grid = _itemsSliverKey.currentContext!.findRenderObject()
            as RenderSliverGrid;
        final layout = widget.gridDelegate.getLayout(grid.constraints);
        final count = state.documentSnapshots.length;
        // A loader sharing the last row adds no height to the grid. Exclude
        // only the extent it actually adds, including grid spacing.
        controlExtent = layout.computeMaxScrollOffset(count + 1) -
            layout.computeMaxScrollOffset(count);
      }
      // Scroll metrics clamp short content to the viewport size. Use the actual
      // sliver extents, including padding/header/footer, then exclude the loader.
      var contentExtent = -controlExtent;
      RenderAbstractViewport.of(control).visitChildren((child) {
        if (child is RenderSliver) {
          contentExtent += child.geometry?.scrollExtent ?? 0;
        }
      });
      if (contentExtent >= _availableViewportExtent - .5) {
        _automaticFillStopped = true;
        // Filling the viewport enables normal scrolling. It is not a reason
        // to show the manual fallback between gestures or page responses.
        _setManualControl(false);
        return;
      }
    }
    final budget = fallback
        ? min(1, widget.maxAutomaticFillPages)
        : widget.maxAutomaticFillPages;
    if (_automaticFillStopped || _automaticFillPages >= budget) {
      _setManualControl(true);
      return;
    }
    _automaticFillPages++;
    _fetchNextPage();
  }

  void _setManualControl(bool visible) {
    if (_showManualLoadMore != visible) {
      setState(() => _showManualLoadMore = visible);
    }
  }

  void _fetchNextPage() {
    if (_nextPageRequest != null) return;
    final cubit = _cubit!;
    final currentState = cubit.state;
    // A stale loader must not turn an error into an implicit retry.
    if (currentState is! PaginationLoaded || currentState.hasReachedEnd) return;
    final request = cubit.fetchPaginatedList();
    _nextPageRequest = request;
    _showManualLoadMore = false;
    setState(() {});
    unawaited(request.then((_) {
      if (!identical(_nextPageRequest, request)) return;
      _nextPageRequest = null;
      final state = cubit.state;
      if (mounted &&
          identical(_cubit, cubit) &&
          state is PaginationLoaded &&
          !state.hasReachedEnd) {
        // Server confirmation may contain no data changes. Rebuild the visible
        // loader so scrolling resumes without emitting a duplicate onLoaded.
        setState(() {});
      }
    }));
  }

  Widget _buildPaginationControl(BuildContext context) {
    _schedulePaginationCheck();
    final scrollable = Scrollable.of(context);
    final isScrolling = scrollable.position.isScrollingNotifier.value;
    final isLoading = _nextPageRequest != null ||
        _cubit!.isFetching ||
        _cubit!.state is PaginationInitial;
    final showLoader = isScrolling || isLoading || !_showManualLoadMore;
    return IndexedStack(
      key: _paginationControlKey,
      // Reserve the same space for both controls. Changing the trailing extent
      // on scroll start/end could otherwise create repeated edge bounces.
      index: showLoader ? 0 : 1,
      alignment: switch (scrollable.axisDirection) {
        AxisDirection.down => Alignment.topCenter,
        AxisDirection.up => Alignment.bottomCenter,
        AxisDirection.right => Alignment.centerLeft,
        AxisDirection.left => Alignment.centerRight,
      },
      children: [
        // An idle scrollable list keeps the loader as its trailing placeholder.
        // Animate only during movement/loading, not indefinitely in the cache.
        TickerMode(
            enabled: showLoader && (isScrolling || isLoading),
            child: widget.bottomLoader),
        Center(
          child: TextButton(
            onPressed: () {
              _automaticFillStopped = true;
              _scrollRequestAllowed = false;
              _fetchNextPage();
            },
            child: Text(widget.loadMoreLabel),
          ),
        ),
      ],
    );
  }

  ChildIndexGetter _documentIndexLookup(PaginationLoaded state,
      {int stride = 1}) {
    // Keep each item's State attached to its document when live updates or
    // filtering move it. A map avoids repeated linear searches during layout.
    final indices = {
      for (var i = 0; i < state.documentSnapshots.length; i++)
        ValueKey(state.documentSnapshots[i].reference.path): i * stride,
    };
    return (key) => indices[key];
  }

  Widget _buildGridView(PaginationLoaded loadedState) {
    var gridView = CustomScrollView(
      reverse: widget.reverse,
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      slivers: [
        if (widget.header != null) widget.header!,
        if (loadedState.documentSnapshots.isEmpty)
          SliverToBoxAdapter(child: widget.onEmpty),
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid(
            key: _itemsSliverKey,
            gridDelegate: widget.gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= loadedState.documentSnapshots.length) {
                  return _buildPaginationControl(context);
                }
                final doc = loadedState.documentSnapshots[index];
                return KeyedSubtree(
                  key: ValueKey(doc.reference.path),
                  child: widget.itemBuilder(
                    context,
                    loadedState.documentSnapshots,
                    index,
                  ),
                );
              },
              childCount: loadedState.documentSnapshots.length +
                  (loadedState.hasReachedEnd ? 0 : 1),
              findChildIndexCallback: _documentIndexLookup(loadedState),
            ),
          ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider.value(value: listener))
            .toList(),
        child: gridView,
      );
    }

    return gridView;
  }

  Widget _buildListView(PaginationLoaded loadedState) {
    var listView = CustomScrollView(
      reverse: widget.reverse,
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      slivers: [
        if (widget.header != null) widget.header!,
        if (loadedState.documentSnapshots.isEmpty)
          SliverToBoxAdapter(child: widget.onEmpty),
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList(
            key: _itemsSliverKey,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final itemIndex = index ~/ 2;
                if (index.isEven) {
                  if (itemIndex >= loadedState.documentSnapshots.length) {
                    return _buildPaginationControl(context);
                  }
                  final doc = loadedState.documentSnapshots[itemIndex];
                  return KeyedSubtree(
                    key: ValueKey(doc.reference.path),
                    child: widget.itemBuilder(
                      context,
                      loadedState.documentSnapshots,
                      itemIndex,
                    ),
                  );
                }
                return widget.separator;
              },
              semanticIndexCallback: (widget, localIndex) {
                if (localIndex.isEven) {
                  return localIndex ~/ 2;
                }
                // ignore: avoid_returning_null
                return null;
              },
              findChildIndexCallback:
                  _documentIndexLookup(loadedState, stride: 2),
              childCount: max(
                  0,
                  (loadedState.documentSnapshots.length +
                              (loadedState.hasReachedEnd ? 0 : 1)) *
                          2 -
                      1),
            ),
          ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider.value(value: listener))
            .toList(),
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildPageView(PaginationLoaded loadedState) {
    var pageView = Padding(
      padding: widget.padding,
      child: PageView.custom(
        reverse: widget.reverse,
        allowImplicitScrolling: widget.allowImplicitScrolling,
        controller: widget.pageController,
        scrollDirection: widget.scrollDirection,
        physics: widget.physics,
        onPageChanged: widget.onPageChanged,
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= loadedState.documentSnapshots.length) {
              return _buildPaginationControl(context);
            }
            final doc = loadedState.documentSnapshots[index];
            return KeyedSubtree(
              key: ValueKey(doc.reference.path),
              child: widget.itemBuilder(
                context,
                loadedState.documentSnapshots,
                index,
              ),
            );
          },
          childCount: loadedState.hasReachedEnd
              ? loadedState.documentSnapshots.length
              : loadedState.documentSnapshots.length + 1,
          findChildIndexCallback: _documentIndexLookup(loadedState),
        ),
      ),
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider.value(value: listener))
            .toList(),
        child: pageView,
      );
    }

    return pageView;
  }
}

enum PaginateBuilderType { listView, gridView, pageView }
