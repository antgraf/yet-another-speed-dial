# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Yet Another Speed Dial — a cross-browser (Chrome, Firefox, Edge, Brave, Opera, Vivaldi) WebExtension that replaces the new tab page with a bookmark "speed dial" grid. Manifest V3.

There is **no build system, package manager, bundler, linter, or test suite**. `src/` is the extension verbatim — what you edit is what ships. Vendored libraries live pre-minified in `src/js/lib/`. The canonical version number is `version` in `src/manifest.json`.

## Developing / running

- **Chrome/Edge/etc.:** `chrome://extensions` → enable Developer mode → "Load unpacked" → select the `src/` directory. Reload the extension from that page after edits to `background.js`/`manifest.json`; UI-only edits to `js/index.js` just need a new tab.
- **Firefox:** `about:debugging` → "This Firefox" → "Load Temporary Add-on" → pick `src/manifest.json`.
- **Releasing:** bump `version` in `manifest.json`, then update the release-notes gate and migrations in `background.js` (see below). Packaging is zipping the contents of `src/`. Recent commits tag releases as `vX.Y.Z`.

## Architecture: three execution contexts + native bookmarks as the database

The extension has no backend and no app-managed datastore for bookmarks. **The browser's native bookmarks tree is the source of truth**, under a folder literally titled `"Speed Dial"` (located by `chrome.bookmarks.search({title:'Speed Dial'})`, created if missing — see `getSpeedDialId` in `index.js` and `createBookmarkFromContextMenu` in `background.js`). Subfolders of that folder are the dial "folders" (tabs). This is why bookmarks sync via the browser for free, and why the code listens to `chrome.bookmarks.on{Created,Changed,Moved,Removed}` to react to changes made anywhere (including the browser's own bookmark manager).

Thumbnails, background colors, and user settings live separately in `chrome.storage.local`:
- key = the bookmark **URL** → `{ thumbnails: [...dataURIs], thumbIndex, bgColor }` (bgColor is stored as a CSS `linear-gradient(...)` string, not a plain color).
- key `"settings"` → the settings object (merged over `defaults` in `index.js`).
- `chrome.storage.sync` holds only `showReleaseNotes`.

The three JS contexts:

1. **`src/background.js`** — the MV3 service worker. Routes messages, owns all bookmark/contextMenu/action/lifecycle event listeners, captures tab/popup screenshots, runs install/update migrations, and orchestrates the offscreen document. Service workers cannot use `DOMParser`, `Image`, or `<canvas>`, so all HTML parsing and image work is delegated to the offscreen document.

2. **`src/offscreen.js`** (loaded via `offscreen.html`) — does the work the worker can't: `fetchImages()` fetches a page's HTML and extracts candidate images (favicon, `og:image`, `apple-touch-icon`/`link[rel=icon]` by size, schema.org `meta[itemprop=image]`, web app manifest icons, inline SVG logos, and CSS `background-image` URLs as a last resort), `resizeImage()` normalizes them to 256×144 webp, and `getBgColor()` samples edge pixels to derive the tile background. Created on demand by `setupOffscreenDocument()`.

3. **`src/js/index.js`** (the new tab page, `index.html` via `chrome_url_overrides.newtab`) — the entire UI: renders dials/folders, drag-and-drop reordering and moving between folders, the per-tile edit modal (image carousel + color picker), settings sidebar, search, and import/export. ~3000 lines, single file, no modules. Entry point is `init()` at the bottom.

`src/js/updated.js` / `updated.html` is just the release-notes page shown after updates.

### Message passing convention

All `chrome.runtime.sendMessage` payloads carry a `target` field (`'background' | 'offscreen' | 'newtab'`) and usually a `type`. Every `handleMessages` listener returns early if `message.target` isn't its own. Adding a new cross-context action means adding a `case` to the relevant `handleMessages` switch.

### Thumbnail fetch pipeline (the core data flow)

`index.js` renders tiles immediately (gray placeholders), then asks for images. End to end:

`index.js printBookmarks` → sends `getThumbs` → **background** `handleGetThumbs` reads `storage.local` in batches and pushes `thumbBatch` messages → **index.js** `setBackgroundImages` paints them. For *new/changed* bookmarks with no stored thumbnail, `background.js` `getThumbnails()` (optionally capturing a screenshot first) → message to **offscreen** → `fetchImages`/`resizeImage`/`getBgColor` → `saveThumbnails` message back to **background** → writes `storage.local` → `thumbBatch` (or a full `refresh`) to **index.js**. "Refresh all" batches through `handleRefreshAll`; single manual refresh forces a popup-window screenshot via `capturePopupScreenshot`.

## Conventions and gotchas specific to this codebase

- **Browser detection is done by feature, not name.** `chrome.runtime.getBrowserInfo` exists only in Firefox, so `if (!chrome.runtime.getBrowserInfo)` is used throughout as "this is Chrome" — notably to patch a Chrome-only off-by-one in `chrome.bookmarks.move` index handling (`moveBookmark`/`moveFolder`) and to choose webp vs jpeg encoding. Opera is detected by user-agent in `isOpera()` and needs a `tabs.onCreated` redirect workaround because it ignores `chrome_url_overrides`.
- **`webextension-polyfill`** (`js/lib/browser-polyfill.min.js`) provides the promise-based `chrome.*` API in Firefox; code uses `chrome.*` with `.then()` everywhere.
- **Vendored libs, no npm:** Sortable (drag/drop), TweenMax/GSAP (the FLIP-style tile layout animation in `layout()`/`animate()`), flexCarousel + slim jQuery (edit-modal image carousel), Coloris (color picker, outputs `#RRGGBBAA`).
- **Color format churn:** background colors round-trip between rgba arrays, `#RRGGBBAA` hex (for Coloris), and `linear-gradient(...)` strings (for storage/CSS). Helpers `rgbToHex`/`hexToRgba`/`rgbaToCssGradient`/`hexToCssGradient`/`cssGradientToHex` convert between them. `getBgColor` is duplicated in both `index.js` and `offscreen.js` (noted as tech debt in comments).
- **i18n:** strings live in `src/_locales/<lang>/messages.json` and are applied in `init()` to elements carrying `data-locale` / `data-locale-placeholder` attributes; in code via `chrome.i18n.getMessage(...)`.
- **Migrations & release notes** are version-gated in `background.js` `handleInstalled`: `isPreviousVersion(a, b)` compares dotted versions; `runMigrations` applies data migrations on update; the `updated.html` release-notes tab is shown only when upgrading past the hardcoded version and `showReleaseNotes` isn't false. Update the hardcoded version when cutting a release with notes.
- **Import supports four formats**, auto-detected in `importFileInput.onchange` by inspecting the JSON shape: Speed Dial 2 (`importFromSD2`), FVD (`importFromFVD`), current YASD v3 (`importFromYASD`), and legacy YASD (`importFromOldYASD`). The bookmark `onCreated` listener is toggled off during import to avoid a thumbnail-fetch storm.
