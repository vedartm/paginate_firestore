# Pagination in Firestore

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-10-orange.svg?style=flat-square)](#contributors-)

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
  paginate_firestore: # latest version
```

Import it

```dart
import 'package:paginate_firestore/paginate_firestore.dart';
```

Implement it

```dart
      PaginateFirestore(
        //item builder type is compulsory.
        itemBuilder: (context, documentSnapshots, index) {
          final data = documentSnapshots[index].data() as Map?;
          return ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: data == null ? Text('Error in data') : Text(data['name']),
            subtitle: Text(documentSnapshots[index].id),
          );
        },
           // Use a stable ordering for predictable pagination
        query: FirebaseFirestore.instance.collection('users').orderBy('name'),
        //Change types accordingly
        itemBuilderType: PaginateBuilderType.listView,
        // to fetch real-time data
        isLive: true,
      ),
```

To use with listeners:

```dart
      PaginateRefreshedChangeListener refreshChangeListener = PaginateRefreshedChangeListener();

      RefreshIndicator(
        child: PaginateFirestore(
          itemBuilder: (context, documentSnapshots, index) => ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text((documentSnapshots[index].data() as Map)['name']),
            subtitle: Text(documentSnapshots[index].id),
          ),
          // Use a stable ordering for predictable pagination
          query: FirebaseFirestore.instance.collection('users').orderBy('name'),
          itemBuilderType: PaginateBuilderType.listView,
          listeners: [
            refreshChangeListener,
          ],
        ),
        onRefresh: () async {
          refreshChangeListener.refreshed = true;
        },
      )
```

## Pagination behavior and Firestore reads

Pages use `startAfterDocument` and `limit`, so scrolling fetches the next page
without fetching all previous pages again. Concurrent fetch calls share one
request. A refresh cancels existing listeners and starts again from the original
cursor; results from older requests are ignored. Refreshing deliberately reads
the first page again. Existing items remain visible while that refresh is pending,
then the refreshed results replace them. The initial loader is used for the first
load or a new pagination query; refresh errors still use the configured error
widget. Keeping items visible does not issue additional Firestore requests.

`itemsGlobalLimit` caps the total document slots requested across pages. For
example, `itemsPerPage: 15` and `itemsGlobalLimit: 25` request 15 documents, then
10, and stop. A limit of zero makes no query. Filtering and live deletions do not
reset this allowance. It is **not a billing cap**: subsequent live updates,
refreshes and reconnects can cause more reads. Overlapping live pages can also
mean fewer unique displayed documents than the allowance.

| Configuration | Read behavior |
| --- | --- |
| `isLive: false` (default) | One `get()` per requested page. Best when refresh-on-demand is sufficient. |
| `isLive: true, isAllItemsLive: false` | One listener on the first page; later pages use `get()`. Historical pages remain unchanged until refresh. |
| `isLive: true, isAllItemsLive: true` (default for live mode) | One listener per requested page; updates to loaded pages stay visible. |

For read savings, keep the default `isLive: false` when updating on explicit
refresh is sufficient. Use `isAllItemsLive: false` if only the first page needs
live updates. Neither mode automatically refreshes historical pages to keep them
fresh; choose based on what the screen needs.

Larger pages reduce request/listener count but can fetch documents the user never
views. After the initial page, list and grid views check their actual scroll layout
after the frame and fetch another page if the content does not fill the viewport.
This repeats until the viewport is full, the end is confirmed, `itemsGlobalLimit`
is reached, or `maxAutomaticFillPages` is exhausted.

`maxAutomaticFillPages` defaults to **3 additional page requests** after the initial
page. Set it to `0` to disable automatic filling. Every automatic fill request
counts, including pages whose items are filtered out, hidden, or add no visible
height. This bounds **automatic page requests**, not total Firestore billing,
live-listener reads, or pages requested by the user. Rebuilds, cache/server
confirmations, metadata events, filter notifications, and live updates do not
reset the budget. Explicit refreshes and new pagination queries/settings start a
new session and reset it. Errors stop filling; retry retains successful pages
and does not reset or resume the automatic-fill cycle.

Once content fills the viewport, automatic filling stops for that session, even
if later filtering or live deletions make the content shorter. Real user scrolling
toward the next page near the end continues pagination, with one page per
qualifying user scroll action and one request in flight at a time.
Rebuilds, programmatic scrolling, and a continuously visible loader do not request
more pages. Filled list/grid viewports keep the trailing `bottomLoader`, including
between gestures and page responses. **Load more** is reserved for underfilled
viewports after automatic filling has stopped, and for the fallback layouts
described below. Each tap requests exactly one page and does not start another
fill cycle. If that page fills the viewport, normal scrolling resumes.

The loader animates during scrolling/loading and remains a static placeholder
while idle; displaying it does not request a page. When manual loading is needed,
the button appears once scrolling and loading have stopped. Both controls share
a stable slot to avoid scroll jumps when switching. In lists the loader sits
after the last separator inside `padding`; in grids it occupies the next grid
cell, matching the original loader placement.

Layout detection supports list/grid views in either scroll direction, reversed
lists such as chats, and shrink-wrapped views with a finite available viewport.
In an **unbounded nested layout**, such as a shrink-wrapped view inside a
`SingleChildScrollView`, the inner widget cannot reliably measure the outer visible
viewport. It conservatively prefetches at most one extra page (or zero with a zero
budget), then uses the manual button; scrolling either view does not load more.
Give the pagination view a bounded size to enable viewport filling and infinite
scrolling. `PageView` retains its existing behavior: at most one automatic extra
page when the trailing control is built, followed by user scrolling or the button.
The configured budget can disable that prefetch but does not turn PageView into
a viewport-fill loop.

```dart
// In PaginateFirestore:
maxAutomaticFillPages: 3, // Extra page requests, not a document/read billing cap.
```

Use `loadMoreLabel` (default: `'Load more'`) to supply the button text from your
app's existing localization system. No localization dependency is required by
this package:

```dart
// In PaginateFirestore, using your app's AppLocalizations:
loadMoreLabel: AppLocalizations.of(context)!.loadMore,
```

Errors stop automatic pagination; there is no automatic retry timer or loop.
An explicit **retry** requests one failed page, using its original query, cursor,
and limit. Successful pages and healthy live listeners are retained.
Concurrent retries share one operation; retrying without an error makes no query.
If several live pages fail, each requires a separate retry; there is no batch
recovery. Successful recovery does not grant another automatic page fetch.
Local filtering errors are retried locally, without Firestore reads.
An explicit **refresh** still starts a new session and rereads the first page.

For widget error recovery, create a `PaginateRetryChangeListener` once in the
owning State, add it to `listeners`, and call `retry()` from your error button:

```dart
final retryListener = PaginateRetryChangeListener(); // Owned by your State.

// In PaginateFirestore:
listeners: [retryListener],
onError: (error) => TextButton(
  onPressed: retryListener.retry,
  child: const Text('Retry'),
),
```

Dispose the notifier in its owner. Existing error buttons that set
`PaginateRefreshedChangeListener.refreshed = true` still refresh everything;
use the retry notifier to retain successful pages. Direct cubit users can call
`retryPaginatedList()`; `fetchPaginatedList()` also retries one failed page when in
an error state.

Healthy live listeners keep receiving updates while another page has an error,
so their normal live-update reads still apply. Retry reattaches only the failed
listener and may reread that page. Fixed live page boundaries still apply.

Within each session, attempting to create another page with an already-requested
query reports an error before another Firestore request is issued. Explicit
retries of failed pages are the only exception. Stalled/cycling cursors and query
construction errors require an explicit refresh or corrected settings, rather
than a page retry. Application callbacks must not repeatedly request refresh or
retry themselves. These safeguards bound automatic page requests, not reads from
changes delivered by already active live listeners.

Firestore charges for documents returned and for billable live changes, with
possible index and security-rule reads. Cursors avoid the skipped-document reads
incurred by offsets. A short page marks the end; an exactly full final page needs
one subsequent empty query to discover the end unless a global limit was reached.
Even an empty query has a minimum one-document read charge. Reconnecting listeners
can incur fresh-query charges depending on persistence and disconnect duration.
See [Firestore billing](https://firebase.google.com/docs/firestore/pricing).

### Live pagination boundaries

Every live page has its own fixed start cursor and limit. Updates to an earlier
page preserve later loaded pages and their pagination cursor. However, inserts,
deletes, or changes to ordered fields can move documents across these fixed
boundaries, causing overlaps or gaps. Duplicates are removed by full document
path, including for collection-group queries. **Refresh to reconcile page
membership after such changes.** First-page-only live mode has the same boundary
limitation, including for new messages in a descending chat feed. Prefer immutable
sort fields, and use one-time pagination when a stable browsing session matters.
The package does not automatically requery all loaded pages on every change.

Live listeners can first return an incomplete local cache. Cached documents may
be displayed, but fetching another page waits for a server-confirmed snapshot
without pending writes, including after later local changes to that page.
There is no timeout: live pagination can remain waiting while offline.
Internal metadata events allow this confirmation even
when the server data is identical; they do not open additional queries. An empty
cache alone does not show the empty state. For explicit offline browsing use
`isLive: false` with `options: GetOptions(source: Source.cache)`; its results and
end-of-list status describe the cache. See
[Firestore snapshot events](https://firebase.google.com/docs/firestore/query-data/listen).

With `includeMetadataChanges: false`, metadata-only confirmations do not repeat
`onLoaded` unless they change the end-of-list status. The visible loader resumes
pagination when confirmation arrives. `onLoaded` and `onReachedEnd` respond to
loaded state changes, not parent rebuilds; they can still run again after data,
filter, or end-of-list changes. `onLoaded` may describe cached data.
Changing `includeMetadataChanges` updates event delivery in place, preserving
loaded pages and subscriptions without restarting queries.

`PaginateFilterChangeListener` searches **only already loaded documents**, locally,
without Firestore reads. Changing or clearing the term always uses the full loaded
list. Removing a filter listener also clears its filter. Filtering may expose the
bottom loader, but the same bounded automatic-loading allowance applies. Use a
different Firestore query for server-side filtering; updating `query` or
query-affecting pagination settings restarts the widget automatically. Equivalent
starting-cursor snapshots (same document path and ordered values) keep the current
session. Changing `isAllItemsLive` while live mode is off, or `GetOptions` while
all pages are live, also leaves the session intact because those settings are
unused in those modes. A failed request is reported through `onError`; use the
retry notifier to recover failed pages. Controllers and notifier instances passed
to the widget remain owned by the caller and should be disposed there.

### Keep converted queries stable across rebuilds

Firestore query equality includes the callbacks passed to `withConverter()`.
Recreating those callbacks in `build()` can make the query compare unequal even
when the collection, filters, and sorting are unchanged. The widget then starts
over and requests the first page again. An `onLoaded` callback that rebuilds the
parent can turn this into a repeating cycle.

Create and retain the converted query in the owning State or repository:

```dart
// A field in your State class, not inside build().
late final Query<User> usersQuery = FirebaseFirestore.instance
    .collection('users')
    .orderBy('name')
    .withConverter<User>(
      fromFirestore: (snapshot, _) => User.fromJson(snapshot.data()!),
      toFirestore: (user, _) => user.toJson(),
    );

// In PaginateFirestore:
query: usersQuery,
```

For queries depending on filters or the signed-in user, use a replaceable field
and rebuild the query when those inputs change. Stable converter functions, such
as top-level functions or static method tear-offs, also preserve query equality.
Equivalent ordinary queries without converters can be recreated without a
restart. Query restarts are separate from failed-page retries and reset the
pagination allowance, so keeping query inputs stable matters even with the
automatic-read safeguards.

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
    <td align="center"><a href="https://adamdupuis.com"><img src="https://avatars1.githubusercontent.com/u/6547826?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Adam Dupuis</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=adamdupuis" title="Code">💻</a></td>
    <td align="center"><a href="https://gauthamasir.github.io/Portfolio_Dart/"><img src="https://avatars1.githubusercontent.com/u/26927742?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Gautham</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=GauthamAsir" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/imhafeez"><img src="https://avatars3.githubusercontent.com/u/21155655?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Hafeez Ahmed</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=imhafeez" title="Code">💻</a></td>
    <td align="center"><a href="https://claudemir.casa"><img src="https://avatars3.githubusercontent.com/u/7956750?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Claudemir Casa</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=claudemircasa" title="Code">💻</a></td>
    <td align="center"><a href="https://www.nikhil27.com"><img src="https://avatars.githubusercontent.com/u/45140298?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Nikhil27bYt</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=Nikhil27b" title="Documentation">📖</a></td>
    <td align="center"><a href="https://github.com/ghprod"><img src="https://avatars.githubusercontent.com/u/1922652?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Ferri Sutanto</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=ghprod" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/jslattery26"><img src="https://avatars.githubusercontent.com/u/44002583?v=4?s=100" width="100px;" alt=""/><br /><sub><b>jslattery26</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=jslattery26" title="Code">💻</a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://approachablegeek.com"><img src="https://avatars.githubusercontent.com/u/68708352?v=4?s=100" width="100px;" alt=""/><br /><sub><b>garrettApproachableGeek</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=garrettApproachableGeek" title="Code">💻</a></td>
    <td align="center"><a href="https://www.suamusica.com.br/"><img src="https://avatars.githubusercontent.com/u/30954979?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Sua Música</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=SuaMusica" title="Code">💻</a></td>
    <td align="center"><a href="https://nelsonnerds.wordpress.com/"><img src="https://avatars.githubusercontent.com/u/1161152?v=4?s=100" width="100px;" alt=""/><br /><sub><b>Austin Nelson</b></sub></a><br /><a href="https://github.com/vedartm/paginate_firestore/commits?author=austinn" title="Code">💻</a></td>
  </tr>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
