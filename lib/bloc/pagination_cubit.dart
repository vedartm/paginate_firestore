import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._query,
    this._limit,
    this._startAfterDocument, {
    this.isLive = false,
  }) : super(PaginationInitial());

  DocumentSnapshot _lastDocument;
  final int _limit;
  final Query _query;
  final DocumentSnapshot _startAfterDocument;
  final bool isLive;

  void filterPaginatedList(String searchTerm) {
    if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;

      final filteredList = loadedState.documentSnapshots
          .where((document) => document
              .data()
              .toString()
              .toLowerCase()
              .contains(searchTerm.toLowerCase()))
          .toList();

      emit(loadedState.copyWith(
        documentSnapshots: filteredList,
        hasReachedEnd: loadedState.hasReachedEnd,
      ));
    }
  }

  void refreshPaginatedList() async {
    _lastDocument = null;
    final localQuery = _getQuery();
    if (isLive) {
      localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(querySnapshot.docs);
      });
    } else {
      final querySnapshot = await localQuery.get();
      _emitPaginatedState(querySnapshot.docs);
    }
  }

  void fetchPaginatedList() {
    isLive ? _getLiveDocuments() : _getDocuments();
  }

  _getDocuments() async {
    final localQuery = _getQuery();
    try {
      if (state is PaginationInitial) {
        refreshPaginatedList();
      } else if (state is PaginationLoaded) {
        final loadedState = state as PaginationLoaded;
        if (loadedState.hasReachedEnd) return;
        final querySnapshot = await localQuery.get();
        _emitPaginatedState(
          querySnapshot.docs,
          previousList: loadedState.documentSnapshots,
        );
      }
    } on PlatformException catch (exception) {
      print(exception);
      rethrow;
    }
  }

  _getLiveDocuments() {
    final localQuery = _getQuery();
    if (state is PaginationInitial) {
      refreshPaginatedList();
    } else if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;
      if (loadedState.hasReachedEnd) return;
      localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(
          querySnapshot.docs,
          previousList: loadedState.documentSnapshots,
        );
      });
    }
  }

  void _emitPaginatedState(
    List<QueryDocumentSnapshot> newList, {
    List<QueryDocumentSnapshot> previousList = const [],
  }) {
    print(newList.length);
    _lastDocument = newList.isNotEmpty ? newList.last : null;
    emit(PaginationLoaded(
      documentSnapshots: previousList + newList,
      hasReachedEnd: newList.isEmpty,
    ));
  }

  Query _getQuery() {
    var localQuery = (_lastDocument != null)
        ? _query.startAfterDocument(_lastDocument)
        : _startAfterDocument != null
            ? _query.startAfterDocument(_startAfterDocument)
            : _query;
    localQuery = localQuery.limit(_limit);
    return localQuery;
  }
}
