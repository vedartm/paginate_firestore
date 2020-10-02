part of 'pagination_bloc.dart';

@immutable
abstract class PaginationEvent {}

class PageFetch implements PaginationEvent {}

class PageRefreshed implements PaginationEvent {}

class PageFiltered implements PaginationEvent {
  final String filter;

  PageFiltered(this.filter);
}