# Cleaner-App runtime comparison — MacSweep 0.2.0

## Observed reference (current run, native app)
1. Overview uses File utente/File inutili scope tabs. User categories use seven colorful tiles (3 + 4).
2. File inutili shows three checked categories: logs 122 KB, app caches 127 MB, browser cache 840 MB; total 968 MB.
3. Review opens a confirmation with expandable category groups and a separate final Remove button. The browser category includes Library/Caches/Google/Chrome/Default and Default/Service Worker/CacheStorage, Default/Service Worker/ScriptCache and Default/GPUCache under Library/Application Support/Google/Chrome.
4. App-cache review lists ordinary user-cache items, including node-gyp, but does not propose Spotify media or GeoServices maps.
5. A file category opens a list on the left with a separate detail panel on the right, selection checkboxes and a bottom review action.

Reference review was cancelled. No original-app cleanup was executed. Screenshots were captured, saved and inspected in the current task work/ui-reference folder. No proprietary artwork is bundled in MacSweep.

## Implemented
- Scope tabs, 3+4 category tile navigation, three junk-category controls and prominent review action.
- List/detail split with native row focus separate from removal checkboxes; metadata, preview and Finder actions. Navy list/search surfaces, centered section title and overview back navigation.
- Dedicated asynchronous cache scan: first explicit visit to File inutili or a cache/log category starts it; repeat scan remains available. Full explicit user scans include read-only junk inventory by default; no launch-time scan.
- Dedicated cache totals do not depend on a completed user-file scan. Unknown, disabled, partial and access-error states remain distinct.
- Exact observed Chrome support-cache suffixes added for Default/Profile profiles. Cookies, History, Login Data, Local Storage, IndexedDB and arbitrary Application Support data remain excluded. Spotify media and GeoServices maps remain outside standard cleanup. Optional container scope stays opt-in.
- Descriptor-relative cache traversal avoids repeated ancestor metadata queries while preserving no-follow, dataless, exclusion, package, snapshot and cancellation rules.
- Review selects only checked and enabled categories, then uses the existing exact-path confirmation and Trash journal.

## Runtime verification
Isolated MacSweep 0.2.0: switched File utente -> File inutili, scanned caches, observed 125.3 MB app caches + 870.6 MB browser caches + 156 KB logs (996 MB total), opened browser files and inspected the detail panel. Returned to overview, unchecked app/browser categories, reviewed only 40 log files, then cancelled. No user files moved. Final CLI metadata-only scan later measured 163,303,881 app-cache bytes, 872,340,887 browser-cache bytes, 156,032 log bytes, 10 access warnings in 1.618 s; caches changed while apps were active. Counts are actual inventory, not numbers copied from Cleaner-App.

84 fixture checks passed: 32 scanner + 25 safety + 27 junk. Additional Model assertions cover cache-only badges, aggregate scope, category review, busy/disabled guards and unknown state. Native build, extracted archive signature and strict UI audit passed.

## Limits
This is a closer independent native UI and behavior implementation, not pixel-perfect proprietary artwork or certified algorithm parity. Reference and native preview were compared at their actual window sizes; final changes refined tile/button sizes and list colors. Exact totals vary with active browser/app writes, permissions and scan time. Original uses grouped folder candidates; MacSweep retains individual file review and snapshot checks. No permanent deletion, automatic app termination or permission expansion added.
