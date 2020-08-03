library paginate_firestore;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/pagination_bloc.dart';
import 'widgets/bottom_loader.dart';
import 'widgets/empty_display.dart';
import 'widgets/empty_separator.dart';
import 'widgets/error_display.dart';
import 'widgets/initial_loader.dart';

class PaginateFirestore extends StatefulWidget {
  const PaginateFirestore(
      {Key key,
      @required this.itemBuilder,
      @required this.query,
      @required this.itemBuilderType,
      this.gridDelegate =
          const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
      this.startAfterDocument,
      this.itemsPerPage = 15,
      this.onError,
      this.emptyDisplay = const EmptyDisplay(),
      this.separator = const EmptySeparator(),
      this.initialLoader = const InitialLoader(),
      this.bottomLoader = const BottomLoader(),
      this.shrinkWrap = false,
      this.reverse = false,
      this.scrollDirection = Axis.vertical,
      this.padding = const EdgeInsets.all(0),
      this.physics})
      : super(key: key);

  final Widget bottomLoader;
  final Widget initialLoader;
  final EdgeInsets padding;
  final Widget emptyDisplay;
  final ScrollPhysics physics;
  final Query query;
  final DocumentSnapshot startAfterDocument;
  final bool reverse;
  final Axis scrollDirection;
  final Widget separator;
  final bool shrinkWrap;
  final Widget Function(Exception) onError;
  final int itemsPerPage;
  final dynamic itemBuilderType;
  final SliverGridDelegate gridDelegate;

  @override
  _PaginateFirestoreState createState() => _PaginateFirestoreState();

  final Widget Function(int, BuildContext, DocumentSnapshot) itemBuilder;
}

class _PaginateFirestoreState extends State<PaginateFirestore> {
  PaginationBloc _bloc;
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PaginationBloc, PaginationState>(
      bloc: _bloc,
      builder: (context, state) {
        if (state is PaginationInitial) {
          return widget.initialLoader;
        } else if (state is PaginationError) {
          return (widget.onError != null)
              ? widget.onError(state.error)
              : ErrorDisplay(exception: state.error);
        } else {
          final loadedState = state as PaginationLoaded;
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
  void initState() {
    super.initState();
    _bloc = PaginationBloc(
      widget.query,
      widget.itemsPerPage,
      widget.startAfterDocument,
    )..add(PageFetch());
  }

  Widget _buildGridView(PaginationLoaded loadedState) {
    return GridView.builder(
      controller: _scrollController,
      itemCount: loadedState.hasReachedEnd
          ? loadedState.documentSnapshots.length
          : loadedState.documentSnapshots.length + 1,
      gridDelegate: widget.gridDelegate,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      padding: widget.padding,
      itemBuilder: (context, index) {
        if (index >= loadedState.documentSnapshots.length) {
          _bloc.add(PageFetch());
          return widget.bottomLoader;
        }
        return widget.itemBuilder(
            index, context, loadedState.documentSnapshots[index]);
      },
    );
  }

  Widget _buildListView(PaginationLoaded loadedState) {
    return ListView.separated(
      controller: _scrollController,
      reverse: widget.reverse,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      padding: widget.padding,
      separatorBuilder: (context, index) => widget.separator,
      itemCount: loadedState.hasReachedEnd
          ? loadedState.documentSnapshots.length
          : loadedState.documentSnapshots.length + 1,
      itemBuilder: (context, index) {
        if (index >= loadedState.documentSnapshots.length) {
          _bloc.add(PageFetch());
          return widget.bottomLoader;
        }
        return widget.itemBuilder(
            index, context, loadedState.documentSnapshots[index]);
      },
    );
  }
}

enum PaginateBuilderType { listView, gridView }
