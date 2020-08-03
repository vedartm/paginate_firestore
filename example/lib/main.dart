import 'package:flutter/material.dart';
import 'package:paginate_firestore/paginate_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firestore pagination library',
      theme: ThemeData(
        primarySwatch: Colors.yellow,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Firestore pagination example'),
        centerTitle: true,
      ),
      body: PaginateFirestore(
        //item builder type is compulsory.
        itemBuilderType:
            PaginateBuilderType.gridView, //Change types accordingly
        itemBuilder: (index, context, documentSnapshot) => ListTile(
          leading: CircleAvatar(child: Icon(Icons.person)),
          title: Text(documentSnapshot.data['name']),
          subtitle: Text(documentSnapshot.documentID),
        ),
        // orderBy is compulsory to enable pagination
        query: Firestore.instance.collection('users').orderBy('name'),
      ),
    );
  }
}
