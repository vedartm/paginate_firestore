part of 'pagination_cubit.dart';

@immutable
abstract class PaginationState {}

class PaginationInitial extends PaginationState {}

class PaginationError extends PaginationState {
  final Exception error;
  PaginationError({required this.error});

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is PaginationError && o.error == error;
  }

  @override
  int get hashCode => error.hashCode;
}

class PaginationLoaded extends PaginationState {
  PaginationLoaded({
    required this.documentSnapshots,
    required this.hasReachedEnd,
  });

  final bool hasReachedEnd;
  final List<DocumentSnapshot> documentSnapshots;

  PaginationLoaded copyWith({
    bool? hasReachedEnd,
    List<DocumentSnapshot>? documentSnapshots,
  }) {
    return PaginationLoaded(
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      documentSnapshots: documentSnapshots ?? this.documentSnapshots,
    );
  }

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is PaginationLoaded &&
        o.hasReachedEnd == hasReachedEnd &&
        listEquals(o.documentSnapshots, documentSnapshots);
  }

  @override
  int get hashCode => hasReachedEnd.hashCode ^ documentSnapshots.hashCode;
}
