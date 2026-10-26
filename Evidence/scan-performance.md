# Scanner optimization — 0.1.3

- Large same-size candidates (>192 KiB) are prefiltered by SHA-256 of three 64 KiB regions. Only candidate buckets containing at least two entries receive a full content SHA-256. Sample equality never establishes duplicate equality. The secure descriptor open and before/after identity and timestamp checks apply to both passes.
- Spotlight screen-capture metadata is queried only for supported image extensions. Photo date parsing reuses one DateFormatter per photo-analysis pass.
- Scan status now identifies inventory, duplicate comparison and photo metadata phases.
- Cancellation, symlink/cloud checks and fresh full-content verification before removal remain in place.

## Measurement
Native optimized compiler builds of the preceding scanner and new scanner on the same generated local fixture: 64 distinct 4 MiB files, one exact copy, one file with equal samples but a byte changed outside the samples, and 1,000 small text files (1,066 total). Six runs each, reversed order for the second batch. Both versions always returned exactly one identical pair with no issues.

Median before: 0.9163 s. Median after: 0.6489 s. Elapsed-time reduction: 29.2%. These are local warm-cache synthetic results, not a Cleaner-App comparison or a prediction for every user dataset. Exact duplicate-heavy datasets still require full reads and may gain little or incur sampling overhead.

## Validation
30 scanner fixture checks, 13 safety checks and 20 junk checks passed (63 total). New regressions cover sample collisions, preserved inventory and cancellation during sampling. Native app built and signed archive verified after extraction. Existing user app was not restarted.
