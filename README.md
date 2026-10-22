# Slate

A GoodNotes/Notability-style notebook app for iPad (iPadOS 17+), built on Apple's PencilKit
and PDFKit. Personal project; no Mac needed.

- **Library:** subject sidebar (folders), cover grid, import PDFs, new notebooks on ruled,
  grid, dotted, Cornell or blank paper.
- **Writing:** ballpoint, fountain and brush pens, pencil, highlighter, eraser (whole
  strokes or precise), lasso. Three favourite colours and widths per tool. Pencil draws and
  fingers scroll and zoom. Tap with two fingers to undo, three to redo.
- **Pages:** add, move and delete pages, a page grid, and continuous vertical scroll.

## Build

GitHub Actions (`.github/workflows/build.yml`) generates the Xcode project with XcodeGen,
builds an unsigned `Slate.ipa`, and runs the unit and UI tests on an iPad simulator. The
simulator screenshots are uploaded as an artifact.

## Install from Windows

1. `tools\fetch.ps1` downloads the newest build into `out\`.
2. `tools\install.ps1` signs it with your Apple ID (plumesign) and installs it on the iPad.

With a free Apple ID, re-run `tools\install.ps1` within 7 days (or refresh with SideStore).
Notebooks are kept.

## Storage

Notebooks are folders in Files > On My iPad > Slate > Library:

```
<Title>.slate/
  notebook.json      title, cover, page list
  document.pdf       every page; template pages are generated PDF pages
  ink/<page>.drawing PencilKit ink per page, in page coordinates
  thumb.png          cover for imported PDFs
```
