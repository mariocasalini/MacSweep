---
version: alpha
colors:
  background: "#051A38"
  panel: "#132540"
  accent: "#54B0FA"
typography:
  heading:
    fontFamily: "SF Pro Display, system-ui, sans-serif"
    fontSize: "30px"
  body:
    fontFamily: "SF Pro Text, system-ui, sans-serif"
    fontSize: "13px"
  data:
    fontFamily: "SF Mono, monospace"
rounded:
  panel: "12px"
  navigation: "7px"
spacing:
  panel: "22px"
  row: "12px"
components:
  sidebar:
    width: "260px"
  list:
    pageSize: 150
---

# MacSweep

## Overview
Native macOS product utility, Italian copy. Reference: observed Cleaner-App 9.7
navigation, dark navy surfaces, file category cards and a review-first workflow.
Independent name and implementation, no copied logos or proprietary artwork.
Signature: a visible file-by-file review and reversible history, not a one-click
promise. No decorative marketing charts or fabricated disk-space totals.

## Colors
Runtime source of truth is `Theme` in Sources/MacSweep.swift. Documented hex
values round its RGB channels. Semantic destructive controls use the native
macOS destructive intent; focus, selection and contrast adapt to OS settings.

## Typography
System SF font roles, 30pt overview heading, 18pt centered screen title, 13pt body and
native caption roles. File sizes use tabular digits. No downloaded fonts.

## Layout
260pt sidebar and content panel with stable 60pt header and 48pt status strip.
Minimum 920×620pt. Lists own their scrolling, 150 results per page. Settings and
overview scroll separately. Native List virtualizes installed application rows.

## Elevation & Depth
Flat navy panels; no background animation. Native sheets own focus and modality.

## Shapes
12pt overview cards, 7pt sidebar selection. Native buttons retain macOS geometry.

## Components
Canonical native SwiftUI controls for buttons, checkboxes, search, pickers,
lists, sheets, alerts and progress. App identity uses Assets/AppIcon.png (generated brush/cyan-ribbon mark) and the
packaged AppIcon.icns; BrandMark loads the bundled 256px BrandIcon.png.
Navigation uses SF Symbols; system file/application icons
come from the user's installed files. Theme is the single owned palette adapter.

## Do's and Don'ts
Show full paths in review and history; truncate only within result rows and
provide Finder/preview actions. Never imply summed category sizes equal savings.
Never preselect results or call approximate photo groups visually identical.

NavigationSectionButton owns full-row rectangular hit testing and a quiet hover
fill. Overview card labels also define a rectangular hit area spanning padding.
Native Button semantics and keyboard behavior are preserved.

Sidebar space badges use Model.sidebarSpace, independent of filters/selection.
Duplicate savings retain one deterministic copy per group; other categories show
reviewable candidate sizes, never guaranteed savings. Unknown/unscanned is —,
scanning is …, disabled is Off, known empty is 0 MB. Management rows have no
file-space estimate. Tooltips explain overlap; categories must not be summed.

File result rows use native type icons from a shared bounded cache. Navigation
reuses Model-owned derived lists and totals; changes to scan data invalidate them.

The brand icon is also used in the macOS menu bar and explicitly in the Dock.
The menu offers Open/Quit; closing the window keeps the app and its model alive.
Ordinary inventory appears before derived content analysis; pending cards say In analisi.

Bulk Trash progress is throttled to roughly 10 Hz to avoid excessive redraws;
complete history becomes visible when the operation finishes or is interrupted.

## Cleaner-App runtime comparison, 0.2.0
Grounded in current native screenshots: segmented File utente / File inutili
overview, seven colored SF Symbol navigation tiles in 3+4 rows, three junk
category tiles with checkboxes and an explicit review action. File sections
use a list/detail split with separate checkbox removal selection and native
row focus. Native navy list surfaces replace platform-default backgrounds.
MacSweep identity, extra management tools and explicit scan/error states remain.
No proprietary Cleaner-App artwork or paid-tool gates are copied.
