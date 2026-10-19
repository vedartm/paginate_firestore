import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._query,
    this._limit,
    this._startAfterDocument, {
    this.isLive = false,
    bool includeMetadataChanges = false,
    this.options,
    this.itemsGlobalLimit,
    this.isAllItemsLive = true,
  })  : _includeMetadataChanges = includeMetadataChanges,
        assert(_limit > 0),
        assert(itemsGlobalLimit == null || itemsGlobalLimit >= 0),
        super(PaginationInitial());

  final int _limit;
  final Query _query;
  final DocumentSnapshot? _startAfterDocument;
  final bool isLive;
  final GetOptions? options;
  final int? itemsGlobalLimit;
  final bool isAllItemsLive;

  // Each listener owns its page. An update to an earlier page must not replace
  // later pages or move the cursor used to fetch the next page.
  final _pages = <_PaginationPage>[];
  final _requestedQueries = <Query>{};
  List<DocumentSnapshot> _documents = [];
  Future<void>? _request;
  Future<void>? _refreshRequest;
  Future<void>? _retryRequest;
  String _filterTerm = '';
  int _generation = 0;
  int _revision = 0;
  bool _disposed = false;
  bool _needsRefresh = false;
  bool _includeMetadataChanges;

  bool get includeMetadataChanges => _includeMetadataChanges;

  /// Changes event delivery without restarting queries or clearing loaded pages.
  void updateMetadataChanges(bool value) => _includeMetadataChanges = value;

  /// Includes waiting for a live page's server confirmation.
  bool get isFetching =>
      _request != null || _refreshRequest != null || _retryRequest != null;

  _PaginationPage? get _failedPage {
    for (final page in _pages) {
      if (page.error != null) return page;
    }
    return null;
  }

  int get _requestedCount =>
      _pages.fold(0, (total, page) => total + page.limit);

  bool get _hasReachedEnd =>
      itemsGlobalLimit == 0 ||
      (_pages.isNotEmpty &&
          _pages.last.confirmed &&
          ((itemsGlobalLimit != null && _requestedCount >= itemsGlobalLimit!) ||
              _pages.last.hasReachedEnd));

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  @override
  Future<void> close() async {
    _disposed = true;
    _generation++;
    await Future.wait(_pages.map(_stopPage));
    await super.close();
  }

  Future<void> _stopPage(_PaginationPage page) {
    // Invalidate callbacks before cancellation, including a cancelled listener
    // whose native registration has not finished yet.
    page.attempt++;
    final confirmation = page.confirmation;
    if (confirmation != null && !confirmation.isCompleted) {
      confirmation.complete();
    }
    page.confirmation = null;
    final subscription = page.subscription;
    page.subscription = null;
    if (subscription != null) page.cancellation = subscription.cancel();
    return page.cancellation ?? Future<void>.value();
  }

  /// Filters only documents already loaded, without issuing Firestore reads.
  /// An empty term restores the unfiltered list.
  void filterPaginatedList(String searchTerm) {
    final normalizedTerm = searchTerm.toLowerCase();
    if (_filterTerm == normalizedTerm) return;
    _filterTerm = normalizedTerm;
    if (!_disposed && state is! PaginationInitial) {
      _emitState();
    }
  }

  Future<void> refreshPaginatedList() {
    if (_disposed) return Future.value();
    if (_refreshRequest != null) return _refreshRequest!;

    final generation = ++_generation;
    final oldPages = List.of(_pages);
    _needsRefresh = false;
    _pages.clear();
    _requestedQueries.clear();
    _documents = [];
    _request = null;
    _retryRequest = null;
    emit(PaginationInitial());

    late final Future<void> request;
    request = Future.wait(oldPages.map(_stopPage)).then((_) async {
      if (_isCurrent(generation)) await _fetchPage(generation);
    }).whenComplete(() {
      if (identical(_refreshRequest, request)) _refreshRequest = null;
    });
    _refreshRequest = request;
    return request;
  }

  /// Concurrent calls share the same request, including while a live listener
  /// is waiting for its first server-confirmed snapshot.
  Future<void> fetchPaginatedList() {
    if (_disposed) return Future.value();
    if (_refreshRequest != null) return _refreshRequest!;
    if (_retryRequest != null) return _retryRequest!;
    if (state is PaginationError) return retryPaginatedList();
    if (_request != null) return _request!;
    if (_hasReachedEnd && state is! PaginationInitial) {
      return Future.value();
    }

    late final Future<void> request;
    request = _fetchPage(_generation).whenComplete(() {
      if (identical(_request, request)) _request = null;
    });
    _request = request;
    return request;
  }

  /// Retries one failed page, retaining loaded data and healthy live listeners.
  /// Calling this without an error does not request another page.
  /// Cursor/query errors require an explicit refresh or corrected settings.
  Future<void> retryPaginatedList() {
    if (_disposed) return Future.value();
    if (_refreshRequest != null) return _refreshRequest!;
    if (_retryRequest != null) return _retryRequest!;
    if (_needsRefresh) return Future.value();
    final page = _failedPage;
    if (page == null) {
      // A local conversion/filter error must not cause another Firestore read.
      if (state is PaginationError) _emitState();
      return Future.value();
    }
    final generation = _generation;
    late final Future<void> request;
    request = _stopPage(page).then((_) async {
      if (_isCurrent(generation)) await _readPage(page, generation);
    }).whenComplete(() {
      if (identical(_retryRequest, request)) _retryRequest = null;
    });
    _retryRequest = request;
    return request;
  }

  Future<void> _fetchPage(int generation) async {
    // An already loaded live page can later receive pending local writes or
    // cached updates. Wait for its latest cursor, not just its first snapshot.
    while (_pages.isNotEmpty && !_pages.last.cursorIsCurrent) {
      final page = _pages.last;
      final confirmation = page.confirmation ??= Completer<void>();
      await confirmation.future;
      if (!_isCurrent(generation) || state is PaginationError) return;
    }
    if (_hasReachedEnd) {
      // Match asynchronous query completion so widget listeners can subscribe
      // before a zero-limit request reports that it has loaded.
      await Future<void>.value();
      if (_isCurrent(generation)) _emitState();
      return;
    }
    final pageLimit = itemsGlobalLimit == null
        ? _limit
        : min(_limit, itemsGlobalLimit! - _requestedCount);
    final cursor = _pages.isEmpty ? _startAfterDocument : _pages.last.cursor;
    try {
      final query =
          (cursor == null ? _query : _query.startAfterDocument(cursor))
              .limit(pageLimit);
      if (!_requestedQueries.add(query)) {
        throw StateError(
            'Pagination did not advance. Refresh before loading more.');
      }
      final page = _PaginationPage(query, pageLimit, cursor,
          isLive: isLive && (_pages.isEmpty || isAllItemsLive));
      _pages.add(page);
      await _readPage(page, generation);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _needsRefresh = true;
      unawaited(Future.wait(_pages.map(_stopPage)));
      emit(PaginationError(error: _asException(error)));
    }
  }

  Future<void> _readPage(_PaginationPage page, int generation) async {
    final attempt = ++page.attempt;
    // A new subscription's first snapshot replaces the saved page even when
    // it is empty and therefore contains no document changes.
    page.receivedSnapshot = false;
    bool isCurrentAttempt() =>
        _isCurrent(generation) && page.attempt == attempt;

    try {
      if (page.isLive) {
        final confirmation = page.confirmation ??= Completer<void>();
        page.cursorIsCurrent = false;
        final listener = page.query
            // A cache snapshot can be incomplete. Metadata events let us wait
            // for confirmation even when the server returns identical data.
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
          if (!isCurrentAttempt()) return;
          try {
            final confirmed = !snapshot.metadata.isFromCache &&
                !snapshot.metadata.hasPendingWrites;
            if (confirmed) page.error = null;
            _updatePage(page, snapshot,
                confirmed: confirmed, emitMetadata: includeMetadataChanges);
          } catch (error) {
            // Converter failures happen inside the data callback, not onError.
            if (isCurrentAttempt()) _failPage(page, error);
          }
        }, onError: (Object error, StackTrace stackTrace) {
          if (isCurrentAttempt()) _failPage(page, error);
        }, onDone: () {
          if (isCurrentAttempt()) {
            _failPage(page,
                StateError('The Firestore listener closed unexpectedly.'));
          }
        });
        page.subscription = listener;
        await confirmation.future;
      } else {
        final snapshot = await page.query.get(options);
        if (isCurrentAttempt()) {
          page.error = null;
          _updatePage(page, snapshot, confirmed: true);
        }
      }
    } catch (error) {
      if (isCurrentAttempt()) _failPage(page, error);
    }
  }

  Exception _asException(Object error) =>
      error is Exception ? error : Exception(error.toString());

  void _failPage(_PaginationPage page, Object error) {
    page.error = _asException(error);
    unawaited(_stopPage(page));
    _emitState();
  }

  void _updatePage(
    _PaginationPage page,
    QuerySnapshot snapshot, {
    required bool confirmed,
    bool emitMetadata = true,
  }) {
    final documentsInPage = snapshot.docs;
    final wasAtEnd = _hasReachedEnd;
    page.cursorIsCurrent = confirmed;
    if (confirmed) {
      page.confirmed = true;
      page.hasReachedEnd = documentsInPage.length < page.limit;
      // Retain the cursor on an empty result; never restart from page one.
      if (documentsInPage.isNotEmpty) page.cursor = documentsInPage.last;
      final confirmation = page.confirmation;
      if (confirmation != null) {
        confirmation.complete();
        page.confirmation = null;
      }
    }
    final changes = snapshot.docChanges;
    final hasDocumentChanges = !page.receivedSnapshot || changes.isNotEmpty;
    page.receivedSnapshot = true;
    if (hasDocumentChanges || emitMetadata) {
      if (hasDocumentChanges) {
        final revision = ++_revision;
        final changedPaths =
            changes.map((change) => change.doc.reference.path).toSet();
        // Only changed documents gain a new revision. An update to another
        // document on this page must not overwrite a newer overlapping copy.
        page.documentRevisions = {
          for (final document in documentsInPage)
            document.reference.path: changedPaths
                    .contains(document.reference.path)
                ? revision
                : page.documentRevisions[document.reference.path] ?? revision,
        };
      }
      page.documents = documentsInPage;
      _mergePages();
    }

    if (hasDocumentChanges ||
        emitMetadata ||
        wasAtEnd != _hasReachedEnd ||
        state is PaginationInitial ||
        state is PaginationError) {
      // Only the initial empty cache is inconclusive. Later local deletions
      // must also be reflected while their writes are still pending.
      if (_documents.isNotEmpty || confirmed || state is PaginationLoaded) {
        _emitState();
      }
    }
  }

  void _mergePages() {
    // Full paths also distinguish documents in collection-group queries.
    // When live pages overlap, keep the most recently received document data.
    final documents = <String, DocumentSnapshot>{};
    final revisions = <String, int>{};
    for (final loadedPage in _pages) {
      for (final document in loadedPage.documents) {
        final path = document.reference.path;
        final revision = loadedPage.documentRevisions[path]!;
        if (!revisions.containsKey(path) || revisions[path]! < revision) {
          documents[path] = document;
          revisions[path] = revision;
        }
      }
    }
    _documents = documents.values.toList();
  }

  void _emitState() {
    // Healthy listeners continue updating retained pages, but must not hide a
    // different page's error or let the widget start automatic pagination.
    if (_needsRefresh) return;
    final pageError = _failedPage?.error;
    if (pageError != null) {
      emit(PaginationError(error: pageError));
      return;
    }
    try {
      final documents = _filterTerm.isEmpty
          ? _documents
          : _documents
              .where((document) => document
                  .data()
                  .toString()
                  .toLowerCase()
                  .contains(_filterTerm))
              .toList();
      emit(PaginationLoaded(
        documentSnapshots: List.unmodifiable(documents),
        hasReachedEnd: _hasReachedEnd,
      ));
    } catch (error) {
      emit(PaginationError(error: _asException(error)));
    }
  }
}

class _PaginationPage {
  _PaginationPage(this.query, this.limit, this.cursor, {required this.isLive});

  final Query query;
  final int limit;
  final bool isLive;
  StreamSubscription<QuerySnapshot>? subscription;
  Future<void>? cancellation;
  int attempt = 0;
  Exception? error;
  DocumentSnapshot? cursor;
  List<QueryDocumentSnapshot> documents = [];
  bool hasReachedEnd = false;
  bool confirmed = false;
  bool cursorIsCurrent = false;
  Completer<void>? confirmation;
  bool receivedSnapshot = false;
  Map<String, int> documentRevisions = {};
}
