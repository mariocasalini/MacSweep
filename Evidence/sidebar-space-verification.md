# Sidebar space — 0.1.2

Native build and 60 existing fixture checks passed. Ten additional Model checks passed (source: SidebarChecks.swift, compiled with the app source after removing its @main annotation in a temporary copy). These cover unknown, scanning, duplicate retention (three 2 MB copies yield 4 MB), total candidates, search/selection independence, empty, junk not scanned/scanned, disabled, and management rows.

Isolated native preview verified trailing alignment and empty placeholders. Clicking the value area of Duplicati opened that section. The existing app was not restarted. Strict UI audit: zero findings.

Candidate sizes use logical file bytes and are potential estimates, not guaranteed allocated disk savings. Duplicate values omit one retained copy per group. Other categories require user review. Categories overlap and must not be summed. Management rows have no estimate.
