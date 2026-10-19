// Exercise the real Firestore query equality with a mocked native boundary.
// The platform interface and core are transitive Firestore SDK dependencies.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paginate_firestore/bloc/pagination_cubit.dart';
import 'package:paginate_firestore/paginate_firestore.dart';

typedef Json = Map<String, dynamic>;

class _TestApp extends Fake implements FirebaseApp {
  @override
  String get name => 'query-rebuild-test';

  @override
  FirebaseOptions get options => const FirebaseOptions(
        apiKey: 'test',
        appId: 'test',
        messagingSenderId: 'test',
        projectId: 'test',
      );
}

Json _decode(DocumentSnapshot<Json> snapshot, SnapshotOptions? options) =>
    snapshot.data()!;
Json _encode(Json data, SetOptions? options) => data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final app = _TestApp();
  platform.FirebaseFirestorePlatform.instance =
      MethodChannelFirebaseFirestore(app: app, databaseId: '(default)');
  final firestore = FirebaseFirestore.instanceFor(app: app);
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet',
    platform.FirebaseFirestoreHostApi.pigeonChannelCodec,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var requests = 0;

  setUp(() {
    requests = 0;
    messenger.setMockMessageHandler(channel.name, (_) async {
      requests++;
      return channel.codec.encodeMessage([
        platform.InternalQuerySnapshot(
          documents: [],
          documentChanges: [],
          metadata: platform.InternalSnapshotMetadata(
            hasPendingWrites: false,
            isFromCache: false,
          ),
        ),
      ]);
    });
  });
  tearDown(() => messenger.setMockMessageHandler(channel.name, null));

  Query<Json> plain() => firestore.collection('items').orderBy('value');
  Query<Json> converted(String field) => plain().withConverter<Json>(
        fromFirestore: (snapshot, _) => {field: snapshot.data()![field]},
        toFirestore: (data, _) => {field: data[field]},
      );
  Widget pagination(Query<Json> query,
          {ValueChanged<PaginationLoaded>? onLoaded}) =>
      PaginateFirestore(
        query: query,
        itemBuilderType: PaginateBuilderType.listView,
        itemBuilder: (_, __, ___) => const SizedBox(height: 100),
        onLoaded: onLoaded,
      );

  for (final stableConverter in [false, true]) {
    testWidgets(
        'equivalent queries survive rebuilds (converter: $stableConverter)',
        (tester) async {
      for (var i = 0; i < 11; i++) {
        final query = stableConverter
            ? plain().withConverter<Json>(
                fromFirestore: _decode, toFirestore: _encode)
            : plain();
        await tester
            .pumpWidget(MaterialApp(home: Scaffold(body: pagination(query))));
        await tester.pumpAndSettle();
      }
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('retained converted query prevents an onLoaded rebuild loop',
      (tester) async {
    final query = converted('value');
    var loadedCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (_, setState) => pagination(query, onLoaded: (_) {
            loadedCalls++;
            setState(() {});
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(loadedCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('different converter callbacks restart the query',
      (tester) async {
    for (final field in ['value', 'other']) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: pagination(converted(field))),
      ));
      await tester.pumpAndSettle();
    }
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
