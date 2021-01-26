import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._query,
    this._limit,
    this._startAfterDocument,
  ) : super(PaginationInitial());

  DocumentSnapshot _lastDocument;
  final int _limit;
  final Query _query;
  final DocumentSnapshot _startAfterDocument;

  void fetchPaginatedList() async {
    try {
      if (state is PaginationInitial) {
        refreshPaginatedList();
      } else if (state is PaginationLoaded) {
        final loadedState = state as PaginationLoaded;
        if (loadedState.hasReachedEnd) return;
        final newItems = await _getDocumentSnapshots();
        emit(loadedState.copyWith(
          documentSnapshots: loadedState.documentSnapshots + newItems,
          hasReachedEnd: newItems.isEmpty,
        ));
      }
    } on Exception catch (error) {
      emit(PaginationError(error: error));
    }
  }

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

  Future<void> refreshPaginatedList() async {
    _lastDocument = null;

    final firstItems = await _getDocumentSnapshots();
    emit(PaginationLoaded(
      documentSnapshots: firstItems,
      hasReachedEnd: firstItems.isEmpty,
    ));
  }

  Future<List<DocumentSnapshot>> _getDocumentSnapshots() async {
    final localQuery = (_lastDocument != null)
        ? _query.startAfterDocument(_lastDocument)
        : _startAfterDocument != null
            ? _query.startAfterDocument(_startAfterDocument)
            : _query;
    try {
      final querySnapshot = await localQuery.limit(_limit).get();
      print(querySnapshot.docs.length);
      _lastDocument =
          querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;
      return querySnapshot.docs;
    } on PlatformException catch (exception) {
      print(exception);
      rethrow;
    }
  }
}
