// Firestore exposes these interfaces for mocking in tests.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

class RecordingFirestore {
  final requests = <RecordedRequest>[];
  late final Query<Json> query = RecordingQuery(this);
}

class RecordingQuery extends Fake implements Query<Json> {
  RecordingQuery(this.store, {this.cursor, this.pageLimit});

  final RecordingFirestore store;
  final DocumentSnapshot? cursor;
  final int? pageLimit;

  // Match the SDK's value-based query equality, including cursor values.
  @override
  bool operator ==(Object other) =>
      other is RecordingQuery &&
      identical(store, other.store) &&
      pageLimit == other.pageLimit &&
      cursor?.reference.path == other.cursor?.reference.path &&
      (cursor as TestDocument?)?.value ==
          (other.cursor as TestDocument?)?.value;

  @override
  int get hashCode => Object.hash(store, pageLimit, cursor?.reference.path,
      (cursor as TestDocument?)?.value);

  @override
  Query<Json> startAfterDocument(DocumentSnapshot documentSnapshot) =>
      RecordingQuery(store, cursor: documentSnapshot, pageLimit: pageLimit);

  @override
  Query<Json> limit(int limit) =>
      RecordingQuery(store, cursor: cursor, pageLimit: limit);

  @override
  Future<QuerySnapshot<Json>> get([GetOptions? options]) {
    final request = RecordedRequest(this, options: options);
    store.requests.add(request);
    return request.result.future;
  }

  @override
  Stream<QuerySnapshot<Json>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    final request = RecordedRequest(this,
        isLive: true, includeMetadataChanges: includeMetadataChanges);
    store.requests.add(request);
    return request.stream.stream;
  }
}

class RecordedRequest {
  RecordedRequest(this.query,
      {this.isLive = false, this.includeMetadataChanges = false, this.options});

  final RecordingQuery query;
  final bool isLive;
  final bool includeMetadataChanges;
  final GetOptions? options;
  final result = Completer<QuerySnapshot<Json>>();
  bool cancelled = false;
  Completer<void>? cancellationGate;
  List<TestDocument> _previousDocuments = [];
  late final stream = StreamController<QuerySnapshot<Json>>(
    onCancel: () {
      cancelled = true;
      // Complete in this test's zone, rather than using the SDK's shared
      // already-completed cancellation future outside widget fake async.
      return cancellationGate?.future ?? Future<void>.value();
    },
  );

  void respond(List<TestDocument> docs,
      {bool fromCache = false,
      bool pendingWrites = false,
      bool metadataOnly = false}) {
    final previousByPath = {
      for (var i = 0; i < _previousDocuments.length; i++)
        _previousDocuments[i].reference.path: i,
    };
    final nextPaths = docs.map((doc) => doc.reference.path).toSet();
    final changes = <TestDocument>[
      for (var i = 0; i < docs.length; i++)
        if (previousByPath[docs[i].reference.path] != i ||
            !identical(_previousDocuments[i], docs[i]))
          docs[i],
      for (final previous in _previousDocuments)
        if (!nextPaths.contains(previous.reference.path)) previous,
    ];
    _previousDocuments = docs;
    final snapshot = TestSnapshot(docs,
        changedDocuments: changes,
        fromCache: fromCache,
        pendingWrites: pendingWrites,
        metadataOnly: metadataOnly);
    if (isLive) {
      stream.add(snapshot);
    } else {
      result.complete(snapshot);
    }
  }

  void fail(Exception error) {
    if (isLive) {
      stream.addError(error, StackTrace.current);
    } else {
      result.completeError(error, StackTrace.current);
    }
  }
}

class TestDocument extends Fake implements QueryDocumentSnapshot<Json> {
  TestDocument(String path, [this.value = ''])
      : reference = TestReference(path);

  final String value;

  @override
  final DocumentReference<Json> reference;

  @override
  String get id => reference.path.split('/').last;

  @override
  Json data() => {'value': value};
}

class TestReference extends Fake implements DocumentReference<Json> {
  TestReference(this.path);

  @override
  final String path;
}

class TestSnapshot extends Fake implements QuerySnapshot<Json> {
  TestSnapshot(this.docs,
      {bool fromCache = false,
      bool pendingWrites = false,
      this.metadataOnly = false,
      this.changedDocuments})
      : metadata = TestMetadata(fromCache, pendingWrites);

  @override
  final List<TestDocument> docs;

  @override
  final SnapshotMetadata metadata;
  final bool metadataOnly;
  final List<TestDocument>? changedDocuments;

  @override
  List<DocumentChange<Json>> get docChanges => metadataOnly
      ? []
      : (changedDocuments ?? docs).map(TestDocumentChange.new).toList();
}

class TestDocumentChange extends Fake implements DocumentChange<Json> {
  TestDocumentChange(this.doc);

  @override
  final TestDocument doc;
}

class InvalidSnapshot extends TestSnapshot {
  InvalidSnapshot() : super([]);

  @override
  List<TestDocument> get docs => throw const FormatException('Invalid data');
}

class TestMetadata extends Fake implements SnapshotMetadata {
  TestMetadata(this.isFromCache, this.hasPendingWrites);

  @override
  final bool isFromCache;

  @override
  final bool hasPendingWrites;
}

class InvalidDocument extends TestDocument {
  InvalidDocument() : super('items/invalid');

  @override
  Json data() => throw const FormatException('Invalid converted data');
}
