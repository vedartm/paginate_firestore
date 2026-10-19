import 'package:flutter/widgets.dart';

class PaginateChangeListener extends ChangeNotifier {}

/// Requests one failed page again without discarding successful pages.
/// Does nothing when there is no error. Dispose this notifier in its owner.
class PaginateRetryChangeListener extends PaginateChangeListener {
  void retry() => notifyListeners();
}

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

  String _filterTerm = '';

  set searchTerm(String value) {
    _filterTerm = value;
    notifyListeners();
  }

  String get searchTerm {
    return _filterTerm;
  }
}
