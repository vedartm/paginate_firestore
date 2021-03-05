import 'package:flutter/widgets.dart';

class PaginateChangeListener extends ChangeNotifier {}

class PaginateRefreshedChangeListener extends PaginateChangeListener {
  PaginateRefreshedChangeListener();

  bool _refreshed = false;

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
  PaginateFilterChangeListener();

  late String _filterTerm;

  set searchTerm(String value) {
    _filterTerm = value;
    if (value.isNotEmpty) {
      notifyListeners();
    }
  }

  String get searchTerm {
    return _filterTerm;
  }
}
