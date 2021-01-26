library paginate_firestore;

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
    Key key,
    @required this.itemBuilder,
    @required this.query,
    @required this.itemBuilderType,
    this.gridDelegate =
        const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
    this.startAfterDocument,
    this.itemsPerPage = 15,
    this.onError,
    this.onReachedEnd,
    this.onLoaded,
    this.emptyDisplay = const EmptyDisplay(),
    this.separator = const EmptySeparator(),
    this.initialLoader = const InitialLoader(),
    this.bottomLoader = const BottomLoader(),
    this.shrinkWrap = false,
    this.reverse = false,
    this.scrollDirection = Axis.vertical,
    this.padding = const EdgeInsets.all(0),
    this.physics,
    this.listeners,
    this.scrollController,
    this.header,
    this.footer,
    this.isLive = false,
  }) : super(key: key);

  final Widget bottomLoader;
  final Widget emptyDisplay;
  final SliverGridDelegate gridDelegate;
  final Widget initialLoader;
  final dynamic itemBuilderType;
  final int itemsPerPage;
  final List<ChangeNotifier> listeners;
  final EdgeInsets padding;
  final ScrollPhysics physics;
  final Query query;
  final bool reverse;
  final ScrollController scrollController;
  final Axis scrollDirection;
  final Widget separator;
  final bool shrinkWrap;
  final bool isLive;
  final DocumentSnapshot startAfterDocument;
  final Widget header;
  final Widget footer;

  @override
  _PaginateFirestoreState createState() => _PaginateFirestoreState();

  final Widget Function(Exception) onError;

  final Widget Function(int, BuildContext, DocumentSnapshot) itemBuilder;

  final void Function(PaginationLoaded) onReachedEnd;

  final void Function(PaginationLoaded) onLoaded;
}

class _PaginateFirestoreState extends State<PaginateFirestore> {
  PaginationCubit _cubit;
  ScrollController _scrollController;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PaginationCubit, PaginationState>(
      cubit: _cubit,
      builder: (context, state) {
        if (state is PaginationInitial) {
          return widget.initialLoader;
        } else if (state is PaginationError) {
          return (widget.onError != null)
              ? widget.onError(state.error)
              : ErrorDisplay(exception: state.error);
        } else {
          final loadedState = state as PaginationLoaded;

          if (widget.onLoaded != null) {
            widget.onLoaded(loadedState);
          }
          if (loadedState.hasReachedEnd && widget.onReachedEnd != null) {
            widget.onReachedEnd(loadedState);
          }

          if (loadedState.documentSnapshots.isEmpty) {
            return widget.emptyDisplay;
          }
          return widget.itemBuilderType == PaginateBuilderType.listView
              ? _buildListView(loadedState)
              : _buildGridView(loadedState);
        }
      },
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    _scrollController = widget.scrollController ?? ScrollController();
    if (widget.listeners != null) {
      for (var listener in widget.listeners) {
        if (listener is PaginateRefreshedChangeListener) {
          listener.addListener(() {
            if (listener.refreshed) {
              _cubit.refreshPaginatedList();
            }
          });
        } else if (listener is PaginateFilterChangeListener) {
          listener.addListener(() {
            if (listener.searchTerm != null && listener.searchTerm.isNotEmpty) {
              _cubit.filterPaginatedList(listener.searchTerm);
            }
          });
        }
      }
    }

    _cubit = PaginationCubit(
      widget.query,
      widget.itemsPerPage,
      widget.startAfterDocument,
      isLive: widget.isLive,
    )..fetchPaginatedList();
    super.initState();
  }

  Widget _buildGridView(PaginationLoaded loadedState) {
    var gridView = CustomScrollView(
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      slivers: <Widget>[
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid(
            gridDelegate: widget.gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= loadedState.documentSnapshots.length) {
                  _cubit.fetchPaginatedList();
                  return widget.bottomLoader;
                }
                return widget.itemBuilder(
                    index, context, loadedState.documentSnapshots[index]);
              },
              childCount: loadedState.hasReachedEnd
                  ? loadedState.documentSnapshots.length
                  : loadedState.documentSnapshots.length + 1,
            ),
          ),
        ),
        if (widget.footer != null) SliverToBoxAdapter(child: widget.footer),
      ],
    );

    if (widget.listeners != null && widget.listeners.isNotEmpty) {
      return MultiProvider(
        providers: widget.listeners
            .map((_listener) => ChangeNotifierProvider(
                  create: (context) => _listener,
                ))
            .toList(),
        child: gridView,
      );
    }

    return gridView;
  }

  Widget _buildListView(PaginationLoaded loadedState) {
    var listView = CustomScrollView(
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      slivers: <Widget>[
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final itemIndex = index ~/ 2;
                if (index.isEven) {
                  if (itemIndex >= loadedState.documentSnapshots.length) {
                    _cubit.fetchPaginatedList();
                    return widget.bottomLoader;
                  }
                  return widget.itemBuilder(itemIndex, context,
                      loadedState.documentSnapshots[itemIndex]);
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
              childCount: max(
                  0,
                  (loadedState.hasReachedEnd
                              ? loadedState.documentSnapshots.length
                              : loadedState.documentSnapshots.length + 1) *
                          2 -
                      1),
            ),
          ),
        ),
        if (widget.footer != null) SliverToBoxAdapter(child: widget.footer),
      ],
    );

    if (widget.listeners != null && widget.listeners.isNotEmpty) {
      return MultiProvider(
        providers: widget.listeners
            .map((_listener) => ChangeNotifierProvider(
                  create: (context) => _listener,
                ))
            .toList(),
        child: listView,
      );
    }

    return listView;
  }
}

enum PaginateBuilderType { listView, gridView }
