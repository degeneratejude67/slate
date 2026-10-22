# Slate

A GoodNotes/Notability-style notebook app for iPad (iPadOS 17+), built on Apple's PencilKit,
PDFKit and Vision. Personal project; no Mac needed.

## Features

- **Library:** a subject sidebar (folders), a cover grid with 18 covers, search, and PDF
  import. PDFs dropped into the library folder become notebooks by themselves.
- **Marketplace (free, offline):** 16 paper templates (ruled, grid, dotted, Cornell, lecture,
  problem sheet, engineering pad, graph, isometric, planners, music), your own templates from
  any PDF or picture, covers, and 6 sticker packs.
- **Writing:**
  - ballpoint, fountain and brush pens, pencil, highlighter, eraser (whole strokes or
    precise) and lasso;
  - a shape tool that straightens lines, circles, triangles and rectangles;
  - text boxes, pictures, stickers and a laser pointer;
  - three favourite colours and widths per tool;
  - the Pencil draws, and fingers scroll and zoom; tap with two fingers to undo, three to redo.
- **Pages:** vertical or horizontal (page-by-page) scrolling, a new page added when you write
  on the last one, a page grid, bookmarks, the PDF outline, and adding, moving and deleting
  pages.
- **Notebooks:** tabs, a side view (a past paper beside your working), export to PDF with
  vector ink, and backup as a zip.
- **Audio:** record a lecture while writing; tap any ink later to hear what was being said.
- **Search:** handwriting (read on the device), text boxes, PDF text and titles.
- **Settings:** theme, desk colour, toolbar at the top or bottom, scrolling direction,
  gestures, and default paper and cover. A banner warns two days before the free signature
  runs out.

## Build

GitHub Actions (`.github/workflows/build.yml`) generates the Xcode project with XcodeGen,
builds an unsigned `Slate.ipa`, and runs the unit and UI tests on an iPad simulator. The
simulator screenshots are uploaded as the `test-output` artifact.

## Install and re-sign from Windows

1. `tools\fetch.ps1` downloads the newest build into `out\`.
2. In iloader, choose Import IPA and pick that `Slate.ipa`. The iPad must be plugged in.

A free Apple ID signature lasts 7 days. The "Slate re-sign reminder" task
(`tools\resign-reminder.ps1`) reminds you every 6 days. Notebooks are kept when you re-sign.

## Moving files over USB

- `python tools\push.py "<PC folder of PDFs>" "4-1 Study/ME 445"` copies lecture PDFs into
  the library; Slate turns them into notebooks the next time it opens.
- `python tools\pull.py` copies the whole library back to `D:\ipad\slate-backup\<date>`.

## Storage

Notebooks are folders in Files > On My iPad > Slate > Library:

```
<Title>.slate/
  notebook.json       title, cover, pages, items, bookmarks, recordings
  document.pdf        every page; template pages are generated PDF pages
  ink/<page>.drawing  PencilKit ink per page, in page coordinates
  images/, audio/     pictures and lecture recordings
  search.json         text found on each page, for search
  thumb.png           cover for imported PDFs
```
