# Feed Me, Seymour!

A native RSS reader for macOS and iOS. One SwiftUI target, two first-class apps.

![App icon](FeedMeSeymour/Resources/Assets.xcassets/AppIcon.appiconset/icon-mac-256.png)

## What it is

A two-pane reader. On the left, your subscriptions under one tab and your
favorites under the other, with an add button in the bottom right corner. On
the right, one chronological river of everything you're subscribed to. Pick an
article and press **Space** (or ⌘↩, or double-click) and it expands to take over
the pane.

Articles are **not** rendered in a web view. Feed HTML is parsed into native
blocks — paragraphs, headings, quotes, lists, code, tables, figures, galleries,
video, audio, embeds — and drawn with SwiftUI. That's what makes the typography
real typography and the media real media:

- **Type.** New York, SF Pro or SF Rounded; adjustable size, line height and
  measure; Dynamic Type on top of your own setting; three papers (System, Paper,
  Night). Bold, italic, inline code, strikethrough, links and superscript
  footnote markers all survive the trip through HTML.
- **Media.** Images fade in and open into a pinch-to-zoom lightbox. Animated
  GIFs and APNGs are decoded with ImageIO and played on a `TimelineView` (and
  held still when Reduce Motion is on). Video uses `AVPlayerViewController` /
  `AVPlayerView`, so you get Picture in Picture, AirPlay, subtitles and speed.
  Audio enclosures get a real transport wired into Now Playing, the Lock Screen,
  Control Center and media keys. YouTube, Vimeo, Spotify, Bluesky and other
  embeds stay dormant behind a poster until you ask for them — nothing loads,
  and no tracker fires, from scrolling past.
- **Sharing.** `ShareLink` everywhere: rows, the reader, images, audio, embeds,
  and in every context menu. Plus copy link and open in browser.

## Read aloud

Press `L` in the reader (or `⌘⇧L`, or the speaker button) and the article is
read to you by `AVSpeechSynthesizer`. The current paragraph scrolls itself into
view and the word being spoken is highlighted as it goes.

This is the second payoff for not using a web view. Because the article is
already a list of typed blocks, the script knows what it's looking at:

- **Code listings and tables are announced, not read.** "Swift code sample."
  "Table with 4 rows." Nobody wants a synthesizer reading braces aloud.
- **Images are described** from their caption or alt text, so you get what a
  sighted reader gets. Undescribed images are passed over rather than announced
  as nothing.
- **Video, audio and embeds are announced**, so a gap in the narration has an
  explanation.
- **Ordered lists are numbered aloud**, headings get a pause before them,
  quotations are followed by their attribution, and a section break becomes
  silence rather than a spoken word.
- **Language is detected** from the opening paragraphs, so a French article is
  read by a French voice when one is installed — the chosen voice is only
  overridden when it plainly doesn't match.

Each segment is its own `AVSpeechUtterance`, which is what makes it possible to
pause at a sensible place, skip by paragraph, and know which block is being
spoken. Word highlighting maps the synthesizer's UTF-16 `NSRange` onto character
offsets before touching the rendered `AttributedString`, so it lands correctly
in paragraphs containing emoji or combining marks.

The transport lives at the root of the window rather than inside the reader, so
closing the article never leaves a voice you can't stop. Voice, speed, pitch and
Personal Voice (iOS 17+) are in the bar's menu and in Settings. Turn on
**Continue to the next article** for hands-free listening down the timeline.

Reading aloud and podcast playback both want the Lock Screen, Control Center and
your AirPods, so neither owns them: `NowPlayingCenter` arbitrates, and whichever
started last takes the controls. Speech offers next/previous *paragraph* where
audio offers skip and scrub, because paragraphs are the only honest unit when a
synthesizer sets the pace.

No account, no analytics, no server in the middle — feeds are fetched straight
from their publishers.

## iCloud sync

Subscriptions, favorites and read state follow your Apple ID. Article text and
media do not: they stay on whichever device downloaded them, and are re-fetched
from the publisher when needed. A saved article is a few seconds of network; a
few thousand HTML blobs in the private database is not worth the round trip.

That's implemented as **two SwiftData stores in one container**:

| Store | Models | Backed by |
| --- | --- | --- |
| `FeedMeSeymourLocal` | `Feed`, `Article`, `MediaAttachment` | On disk only |
| `FeedMeSeymourCloud` | `SyncedSubscription`, `SyncedArticleState` | CloudKit private database |

SwiftData won't let a model in a synced store hold a relationship to one in a
local store, so rather than tear apart the `Feed`↔`Article` graph, the cloud
store holds small **mirror records** keyed by natural identifiers — a feed's
URL, an item's guid — because `PersistentIdentifier` differs on every device.
`SyncCoordinator` reconciles the two on launch, on returning to the foreground,
on backgrounding (so a star you just tapped gets pushed), after every refresh,
and whenever CloudKit delivers a remote change.

Details worth knowing:

- **Conflicts** resolve last-writer-wins against explicit clocks
  (`Feed.metadataUpdatedAt`, `Article.stateUpdatedAt`), not CloudKit's delivery
  order. The publisher's own feed title is never overwritten by a stale mirror;
  your rename and your ordering are.
- **Unsubscribing writes a tombstone**, not a delete. A hard delete would simply
  be undone by the next device to sync, which still has the subscription.
  Re-subscribing afterwards wins over the tombstone.
- **A favorite can arrive before its article does.** If you star something on
  your Mac and your iPhone has never seen that item, the phone stands in a
  placeholder that shows in Favorites and fills itself in on the next refresh of
  that feed.
- **Read state expires after 60 days** in the cloud store. Whether you read
  something two months ago isn't worth a record. Favorites are kept forever.
- Sync can be turned off in Settings.

**Building without a paid Apple Developer account:** delete the four iCloud keys
from `FeedMeSeymour.entitlements` (they're marked with a comment). The container
falls back to a fully local store on its own, and the app behaves exactly as it
did before sync existed.

## Getting started

Open `FeedMeSeymour.xcodeproj` in Xcode 16 or later and run.

- **macOS** 15 or later
- **iOS / iPadOS** 18 or later

A fresh install seeds five well-typeset feeds so the first launch isn't an empty
room. Replace them with your own, or import an OPML file (`⌘⇧I`).

## Keyboard

| Key | What it does |
| --- | --- |
| `Space` | Expand the selected article, or close the reader |
| `↑` `↓` | Move through the timeline |
| `J` / `K` | Next / previous article |
| `S` | Favorite |
| `L` | Read the article aloud |
| `Esc` | Close the reader |
| `⌘R` | Refresh all subscriptions |
| `⌘⇧N` | Add a subscription |
| `⌘⇧S` | Toggle favorite |
| `⌘⇧L` | Read aloud |
| `⌘⇧U` | Toggle read |
| `⌘+` `⌘-` `⌘0` | Text size |
| `⌘⇧K` | Mark all as read |
| `⌘⇧I` / `⌘⇧E` | Import / export OPML |

## How it's put together

```
FeedMeSeymour/
  App/          FeedMeSeymourApp, AppModel, menu commands
  Core/
    Models/     SwiftData: Feed, Article, MediaAttachment
    Feeds/      RSS/Atom/RDF/JSON parsing, discovery, fetching, refresh, OPML
    Content/    HTML tokenizer + entities -> ArticleBlock, with a render cache
    Sync/       CloudKit mirror records and the reconcile pass
  Design/       Typography, Palette, ReaderSettings
  Views/        Sidebar, Timeline, Reader
  Media/        AVKit video, audio playback, speech, animated images, embeds, lightbox
FeedMeSeymourTests/
```

Notable pieces:

- **`XMLFeedParser`** handles RSS 2.0, Atom 1.0 and RSS 1.0/RDF in one pass,
  including `content:encoded`, `media:*`, `itunes:*` and Dublin Core. Namespace
  processing is off on purpose — publishers bind prefixes inconsistently, and
  matching the qualified name as written is more forgiving. Atom
  `type="xhtml"` payloads are re-serialized back into HTML.
- **`FeedDiscovery`** takes whatever you paste — `theverge.com`, a `feed://`
  link, an HTML page — and finds the real feed, via `<link rel="alternate">`
  and then the conventional paths.
- **`ArticleContentParser`** is a forgiving HTML scanner that never throws.
  It handles `srcset` and lazy-loading attributes, drops tracking pixels and
  script/style content, picks a `<source>` AVFoundation can actually open, and
  treats `<br><br>` as the paragraph break that half the web means by it.
- **`FeedRefreshService`** fetches every subscription concurrently off the main
  actor with conditional GETs (`ETag` / `If-Modified-Since`), then merges on the
  main actor. Old entries are pruned; favorites never are.
- **`SyncCoordinator`** reconciles the local store against the iCloud mirror —
  see [iCloud sync](#icloud-sync) above.
- **`SpeechScript`** turns parsed blocks into something worth listening to, and
  **`SpeechReader`** drives the synthesizer — see [Read aloud](#read-aloud).

## Tests

`⌘U` in Xcode, or:

```sh
xcodebuild test -scheme FeedMeSeymour -destination 'platform=macOS'
```

The suite covers the feed parsers (RSS, Atom with escaped and xhtml content,
JSON Feed, date dialects, iTunes durations), feed discovery, OPML round-tripping,
the HTML-to-blocks layer (emphasis, links, entities, lists, tables, figures,
galleries, lazy images, video source selection, embeds, code blocks, and
deliberately malformed markup), and the sync reconcile pass (adoption,
tombstones, re-subscription, rename conflicts in both directions, duplicate
mirrors, placeholder favorites and state expiry) against an in-memory store, and
the read-aloud script (verbatim paragraphs, announced code and tables, described
images, numbered lists, separator pauses, rate clamping and language detection).

## Known limits

- The timeline filters and sorts in memory rather than pushing predicates into
  SwiftData. That is fine at the retention cap of 300 articles per feed; it
  would want revisiting before raising the cap much further.
- Background refresh happens when the app is frontmost or becomes active, not
  via `BGTaskScheduler`.
- The reconcile pass loads every article to compare state clocks. Fine at the
  retention cap; it would want a predicate-based pass before that grows.
- "Mark all as read" on a large store creates one cloud record per article in
  the following reconcile. Bounded by the 60-day expiry, but it is a burst.
- Changing voice or speed mid-article restarts from the current paragraph.
  `AVSpeechSynthesizer` can't re-rate an utterance already queued.
- Read-aloud position isn't restored across launches, and isn't synced.
- The project builds in Swift 5 language mode with minimal concurrency checking.
  Moving to Swift 6 is a worthwhile follow-up.
