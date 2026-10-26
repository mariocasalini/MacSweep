# Navigation performance — 0.1.4

Root causes: repeated category filtering/group flattening, sidebar byte reductions, sorting the entire selected category repeatedly for counts/empty state/pagination/list, scanning empty selections, and per-path Finder icon lookup during row rendering.

Model now caches category collections and badge formatting; each section keeps its last query/sort projection. Selection affects sorting only in selected-first order. Empty selection is constant-time; selected entries are cached otherwise. Any scan-result, junk, enabled-category or custom download-root mutation invalidates the derived inventory. Mutating nested result arrays also triggers invalidation. A bounded native file-type icon cache avoids per-file path metadata lookups during rendering.

## Benchmark
80,000 synthetic entries, 1,000 three-entry groups. Three passes through five sections, six render-style reads of filtered/visible/selection/badges per section (90 reads). Native -O builds, same fixture. Previous model: 30.1451 seconds. Updated model: 0.5171 seconds. Checksums match (4,390,020). This measures model computations, not end-to-end click latency; it is a single local synthetic run.

The harness also asserts default/reverse sorting, search, selection-first ordering and changes, removal invalidation, disabled/re-enabled categories, new inventory, junk mutation, and custom download-root mutation. All passed for both versions.

## Runtime and regression checks
A separate native preview seeded with 80,000 synthetic entries opened Largest (80,000 results), Duplicates (3,000 results), then Largest again successfully. No real file access or removal was triggered. Production app was not restarted. Native production build and all 63 existing scanner/safety/junk fixture checks passed. Strict UI audit: no findings.

The caches retain additional in-memory derived collections in exchange for avoiding repeated work; they are discarded on inventory changes. First visits still perform the necessary initial ordering.
