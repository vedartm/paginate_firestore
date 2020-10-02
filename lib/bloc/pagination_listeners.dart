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

class PaginateFilterChangeListener extends PaginateChangeListener {
  String _filterTerm;

  PaginateFilterChangeListener();

  set search(String value) {
    _filterTerm = value;
    if (value.isNotEmpty) {
      notifyListeners();
    }
  }

  String get filter {
    return _filterTerm;
  }
}
