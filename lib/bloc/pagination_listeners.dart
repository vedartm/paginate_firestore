import 'package:flutter/widgets.dart';

class PaginateChangeListener extends ChangeNotifier {}

class PaginateRefreshedChangeListener extends PaginateChangeListener {
  bool _refreshed = false;

  PaginateRefreshedChangeListener();

  set refreshed(bool value) {
    _refreshed = value;
    if (value) {
      notifyListeners();
    }
  }

  bool get refreshed {
    return _refreshed;
  }
}

class PaginateSearchChangeListener extends PaginateChangeListener {
  String _searchTerm;

  PaginateSearchChangeListener();

  set search(String value) {
    _searchTerm = value;
    if (value.isNotEmpty) {
      notifyListeners();
    }
  }

  String get search {
    return _searchTerm;
  }
}
