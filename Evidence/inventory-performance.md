# Real-folder inventory and macOS identity — 0.1.5

## Investigation and measurement
The previous synthetic duplicate benchmark did not represent expensive traversal through deep real directory trees. The previous scanner resolved the entire ancestor path for every file and prefetched/read multiple Foundation resource keys per item.

Compared optimized native builds of the scanner in commit baeef44 and the new scanner using the user's configured roots. Both runs were metadata-only: duplicate/name/photo content analysis was disabled. The active Codex workspace and MacSweep project were excluded from this comparison to avoid build/test writes changing the input. User exclusions were preserved.

Previous: 46.531 s, 66,623 files. New: 2.342 s, 66,623 files. Sorted path-and-size SHA-256 fingerprints match exactly. Both reported 100 issues (the existing capped issue count). This is a local sequential warm-cache measurement of inventory only, not complete duplicate hashing, not a Cleaner-App timing, and not a guarantee for other datasets. No file names or contents are included in the evidence.

## Implementation
Directories are opened with descriptor-relative O_NOFOLLOW traversal. fstatat/AT_SYMLINK_NOFOLLOW reads child identity and SF_DATALESS before descent or content access; directory open/fstat checks reject replacements. Package metadata is requested only for directories. Files use kernel stat size, dates and identity rather than resolving their full ancestor path for each entry. Dot/UF_HIDDEN items, links, packages, protected/excluded paths and dataless placeholders remain skipped. Full digest verification and the independent pre-removal checks remain unchanged.

The sorted inventory is published before duplicate/photo analysis so ordinary categories can be examined while content analysis continues. Derived categories display “In analisi”/“…” and removal remains disabled during the scan.

Dock icon is explicitly set from bundled AppIcon.icns (brand fallback for package builds). SwiftUI MenuBarExtra uses the brand image and offers Apri MacSweep/Esci da MacSweep. Closing the last window keeps the app available; the app owns the Model so reopening does not discard the scan state. No launch-at-login configuration is added.

## Validation
32 scanner, 13 safety and 20 junk fixture checks passed (65 total), including nested Unicode names and early-inventory ordering, sample collision, cancellation, symbolic links and ancestor replacement. Native production build and extracted archive signature verified. Strict UI audit: zero findings. Isolated native app launched as version 0.1.5; OS menu-bar icon rendering/reopening needs user-visible confirmation on the target desktop because the automation exposes the app window rather than the global menu bar. Production app was not interrupted or restarted.
