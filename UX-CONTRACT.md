# MacSweep interaction contract

Source: user's request for Cleaner-App equivalent cleaning and selected-app
removal; observed original UI and packaged localization evidence in Evidence/.
This is an independent 0.1 implementation; algorithm parity is unverified.

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Table Selection | Model.selected + native checkboxes | This contract | visible page; duplicate extra copies | ScannerTests; UI fixture |
| Select/Listbox | SwiftUI Picker | DESIGN.md | platform-owned popup | UI sort picker |
| Date | Foundation formatted Date | This contract | OS-local format | UI file row/history |
| Form | Native settings controls | Model.persist | explicit folder chooser | UI settings |
| Scrollbar | Native ScrollView/List | macOS user preferences | OS-owned visibility and contrast | UI list/settings |
| Toast | Model.status + message alert | This contract | persistent status, error alert | UI empty/scan |
| CRUD | RemovalStore | Sources/Safety.swift | Trash + restore only | SafetyTests |

## Business sources and lifecycle
- Permissions: explicit folders selected by the user, existing OS permissions;
  no automatic Full Disk Access request or privileged helper.
- Removal: user selects paths, reviews exact paths and confirms Trash operation.
  Never empty Trash or permanently delete files.
- Privacy: local processing. No analytics, servers, AI calls or network in the
  produced app. REA is development tooling and is not bundled into MacSweep.
- Retention: journal in local Application Support; persists across app launches.
  Restore requires original inode/device in Trash and vacant original path.
- Billing: no purchases/subscriptions implemented.
- Uninstaller: exact bundle-ID candidates; data unchecked initially; running apps
  blocked again at confirmation. No claims of complete uninstall for all apps.

## State and navigation
Changing category clears selection, search and page. Local search is immediate
and clears selection; clear button exists. No URL state for local private paths.
Scan is read-only, cancellable; partial findings and errors remain visible.
Mutations disabled while scanning. A canceled scan is explicitly partial.
Settings persist for next scan. Cache access opt-in for each launch; sandbox
container cache/log discovery has a separate opt-in. Disabling duplicate/name/
photo categories skips their derived content analysis; inventory is shared.
Duplicate extra-copy selection retains a deterministic path per group; review
rejects selecting all copies within a duplicate group. Same-name files are not
treated as duplicates. Photo series are temporal, not visual-similarity groups.
Errors preserve their paths and appear in history or persistent result alerts.
No automatic retry of mutations. Cancel sheet makes no changes.

## Navigation hit targets
NavigationSectionButton owns each complete sidebar row. Text, icon and padded
empty space activate the same section. Hover highlights the row. The overview
category cards likewise activate from their complete padded bounds. Native
Button focus and keyboard activation remain canonical.

Sidebar space badges use Model.sidebarSpace, independent of filters/selection.
Duplicate savings retain one deterministic copy per group; other categories show
reviewable candidate sizes, never guaranteed savings. Unknown/unscanned is —,
scanning is …, disabled is Off, known empty is 0 MB. Management rows have no
file-space estimate. Tooltips explain overlap; categories must not be summed.

Large duplicate candidates use a rejecting-only sample prefilter; full SHA-256 remains the equality authority. Phase feedback distinguishes inventory, comparison and photo analysis.

Navigation performance: Model owns cached category inventories, formatted space badges, per-section search/order results and selected entries. Result, junk, download-root and enabled-category mutations invalidate all derived data. Query/order and selection-first ordering use explicit cache keys; page changes reuse the ordered collection. Empty selection returns immediately. File list icons use a bounded shared file-type icon cache and do not query each file path during rendering.
