## 1.0.3+1

- Updates dependencies
- Supports Scrollbar

## 1.0.3

### Breaking changes

- Changes `emptyDisplay` to `onEmpty`
- `itemBuilder` type changes to `Function(BuildContext, List<DocumentSnapshot>, int)`

### Other changes

- Adds `allowImplicitScrolling` for snaphots and `options` for get
- Removes scroll from `onEmpty` and `onError`
- Use the new `flutter_lints` package and apply changes
- Updates `cloud_firestore` to v3.1.0
- Updates `provider` to v6.0.1
- Updates `bloc` to v7.2.1
- Updates `flutter_bloc` to v7.3.3

## 1.0.2

- Fixes refresh on emptyDisplay
- Adds `allowImplicitScrolling` in pageview
- Updates `cloud_firestore` to v2.4.0

## 1.0.1+1

- Fixes duplication of document snapshot

## 1.0.1

- New feature - Paginated page view. To use this, set the type as `itemBuilderType: PaginateBuilderType.pageView`
- Updates dependencies to latest

## 1.0.0

- **BREAKING**: `header` and `footer` accepts only sliver widget. If you want to add a normal widget wrap it with `SliverToBoxAdapter(child: YourWidget())`. Check example for more clarity.
- Updates dependencies to latest

## 1.0.0-nullsafety.1

- Updates `cloud_firestore` version to v2.0.0

## 1.0.0-nullsafety.0

- BREAKING: Opt into null safety

## 0.3.1

- Updates `cloud_firestore` and `firebase_core` to the latest

## 0.3.0+1

- Fixes documentation

## 0.3.0

- Added `isLive` to fetch real-time data
- Changed from bloc to cubit

## 0.2.2

- Added `header` and `footer` support

## 0.2.1

- Added support for Search listener

## 0.2.0

- Added scroll controller using `scrollController` attribute
- Added support for Refresh listener

## 0.1.3

- Updated packages to latest version

## 0.1.2

- Added GridView support using the attribute `itemBuilderType: PaginateBuilderType.gridView`
- Updated flutter_bloc to v6.0.1

## 0.1.1+1

- Updated flutter_bloc to v5.0.1

## 0.1.1

- Added `startAfterDocument` attribute

## 0.1.0

- Initial release
