import 'package:flutter/material.dart';
import 'package:paginate_firestore/paginate_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firestore pagination library',
      theme: ThemeData(
        primarySwatch: Colors.yellow,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore pagination example'),
        centerTitle: true,
      ),
      body: Scrollbar(
        child: PaginateFirestore(
          // Use SliverAppBar in header to make it sticky
          header: const SliverToBoxAdapter(child: Text('HEADER')),
          footer: const SliverToBoxAdapter(child: Text('FOOTER')),
          // item builder type is compulsory.
          itemBuilderType:
              PaginateBuilderType.listView, //Change types accordingly
          itemBuilder: (context, documentSnapshots, index) {
            final data = documentSnapshots[index].data() as Map?;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: data == null
                  ? const Text('Error in data')
                  : Text(data['name']),
              subtitle: Text(documentSnapshots[index].id),
            );
          },
          // orderBy is compulsory to enable pagination
          query: FirebaseFirestore.instance.collection('users').orderBy('name'),
          itemsPerPage: 5,
          // to fetch real-time data
          isLive: true,
        ),
      ),
    );
  }
}
