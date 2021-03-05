# Pagination in Firestore

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-5-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

[![pub package](https://img.shields.io/pub/v/paginate_firestore.svg)](https://pub.dev/packages/paginate_firestore)
[![style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://github.com/tenhobi/effective_dart)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

<p align="center">
  <img src="https://raw.githubusercontent.com/excogitatr/paginate_firestore/master/assets/screen.gif" height="500px">
</p>

## Setup

Use the same setup used for `cloud_firestore` package (or follow [this](https://pub.dev/packages/cloud_firestore#setup)).

## Usage

In your pubspec.yaml

```yaml
dependencies:
  paginate_firestore: ^0.3.1
```

Import it

```dart
import 'package:paginate_firestore/paginate_firestore.dart';
```

Implement it

```dart
      PaginateFirestore(
        itemBuilderType: PaginateBuilderType.listView, // listview and gridview
        itemBuilder: (index, context, documentSnapshot) => ListTile(
          leading: CircleAvatar(child: Icon(Icons.person)),
          title: Text(documentSnapshot.data()['name']),
          subtitle: Text(documentSnapshot.documentID),
        ),
        // orderBy is compulsary to enable pagination
        query: Firestore.instance.collection('users').orderBy('name'),
        isLive: true // to fetch real-time data
      )
```

To use with listeners:

```dart
      PaginateRefreshedChangeListener refreshChangeListener = PaginateRefreshedChangeListener();

      RefreshIndicator(
        child: PaginateFirestore(
          itemBuilder: (context, documentSnapshot) => ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text(documentSnapshot.data()['name']),
            subtitle: Text(documentSnapshot.documentID),
          ),
          // orderBy is compulsary to enable pagination
          query: Firestore.instance.collection('users').orderBy('name'),
          listeners: [
            refreshChangeListener,
          ],
        ),
        onRefresh: () async {
          refreshChangeListener.refreshed = true;
        },
      )
```

## Contributions

Feel free to contribute to this project.

If you find a bug or want a feature, but don't know how to fix/implement it, please fill an [issue](https://github.com/excogitatr/paginate_firestore/issues).  
If you fixed a bug or implemented a feature, please send a [pull request](https://github.com/excogitatr/paginate_firestore/pulls).

## Getting Started

This project is a starting point for a Dart
[package](https://flutter.dev/developing-packages/),
a library module containing code that can be shared easily across
multiple Flutter or Dart projects.

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Contributors ✨

Thanks goes to these wonderful people:

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tr>
    <td align="center"><a href="https://adamdupuis.com"><img src="https://avatars1.githubusercontent.com/u/6547826?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Adam Dupuis</b></sub></a><br /><a href="https://github.com/excogitatr/paginate_firestore/commits?author=adamdupuis" title="Code">💻</a></td>
    <td align="center"><a href="https://gauthamasir.github.io/Portfolio_Dart/"><img src="https://avatars1.githubusercontent.com/u/26927742?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Gautham</b></sub></a><br /><a href="https://github.com/excogitatr/paginate_firestore/commits?author=GauthamAsir" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/imhafeez"><img src="https://avatars3.githubusercontent.com/u/21155655?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Hafeez Ahmed</b></sub></a><br /><a href="https://github.com/excogitatr/paginate_firestore/commits?author=imhafeez" title="Code">💻</a></td>
    <td align="center"><a href="https://claudemir.casa"><img src="https://avatars3.githubusercontent.com/u/7956750?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Claudemir Casa</b></sub></a><br /><a href="https://github.com/excogitatr/paginate_firestore/commits?author=claudemircasa" title="Code">💻</a></td>
    <td align="center"><a href="https://www.nikhil27.com"><img src="https://avatars.githubusercontent.com/u/45140298?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Nikhil27bYt</b></sub></a><br /><a href="https://github.com/excogitatr/paginate_firestore/commits?author=Nikhil27b" title="Documentation">📖</a></td>
  </tr>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
