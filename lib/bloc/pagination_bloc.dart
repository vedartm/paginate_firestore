import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_event.dart';
part 'pagination_state.dart';

class PaginationBloc extends Bloc<PaginationEvent, PaginationState> {
  PaginationBloc(
    this._query,
    this._limit,
    this._startAfterDocument,
  ) : super(PaginationInitial());

  DocumentSnapshot _lastDocument;
  final Query _query;
  final int _limit;
  final DocumentSnapshot _startAfterDocument;

  @override
  Stream<PaginationState> mapEventToState(
    PaginationEvent event,
  ) async* {
    if (event is PageFetch) {
      final currentState = state;
      if (!_hasReachedEnd(currentState)) {
        try {
          if (currentState is PaginationInitial) {
            final firstItems = await _getDocumentSnapshots();
            yield PaginationLoaded(
              documentSnapshots: firstItems,
              hasReachedEnd: firstItems.isEmpty,
            );
            return;
          }
          if (currentState is PaginationLoaded) {
            final newItems = await _getDocumentSnapshots();
            yield currentState.copyWith(
              documentSnapshots: currentState.documentSnapshots + newItems,
              hasReachedEnd: newItems.isEmpty,
            );
          }
        } on Exception catch (error) {
          yield PaginationError(error: error);
        }
      }
    }
    if (event is PageFiltered) {
      if (state is PaginationLoaded) {
        PaginationLoaded currentState = state as PaginationLoaded;
        List<DocumentSnapshot> filteredItems = currentState.documentSnapshots.where((document) {
          bool hasFilter = false;
          document.data().forEach((key, value) {
            if (value.toString().contains(event.filter)) {
              hasFilter = true;
            }
          });
          return hasFilter;
        }).toList();

        yield PaginationLoaded(
            documentSnapshots: filteredItems,
            hasReachedEnd: currentState.hasReachedEnd
        );
      }
    }

    if (event is PageRefreshed) {
      _lastDocument = null;

      final firstItems = await _getDocumentSnapshots();
      yield PaginationLoaded(
        documentSnapshots: firstItems,
        hasReachedEnd: firstItems.isEmpty,
      );
    }
  }

  bool _hasReachedEnd(PaginationState state) =>
      state is PaginationLoaded && state.hasReachedEnd;

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
