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

Everything stays on the device. No account, no server, no analytics.

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
| `Esc` | Close the reader |
| `⌘R` | Refresh all subscriptions |
| `⌘⇧N` | Add a subscription |
| `⌘⇧S` | Toggle favorite |
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
  Design/       Typography, Palette, ReaderSettings
  Views/        Sidebar, Timeline, Reader
  Media/        AVKit video, audio playback, animated images, embeds, lightbox
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

## Tests

`⌘U` in Xcode, or:

```sh
xcodebuild test -scheme FeedMeSeymour -destination 'platform=macOS'
```

The suite covers the feed parsers (RSS, Atom with escaped and xhtml content,
JSON Feed, date dialects, iTunes durations), feed discovery, OPML round-tripping,
and the HTML-to-blocks layer (emphasis, links, entities, lists, tables, figures,
galleries, lazy images, video source selection, embeds, code blocks, and
deliberately malformed markup).

## Known limits

- The timeline filters and sorts in memory rather than pushing predicates into
  SwiftData. That is fine at the retention cap of 300 articles per feed; it
  would want revisiting before raising the cap much further.
- Background refresh happens when the app is frontmost or becomes active, not
  via `BGTaskScheduler`.
- The project builds in Swift 5 language mode with minimal concurrency checking.
  Moving to Swift 6 is a worthwhile follow-up.
