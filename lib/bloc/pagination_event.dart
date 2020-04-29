part of 'pagination_bloc.dart';

@immutable
abstract class PaginationEvent {}

class PageFetch implements PaginationEvent {}

class PageRefreshed implements PaginationEvent {}
