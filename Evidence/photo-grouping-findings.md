# Photo series: focused REA/Ghidra findings

Static analysis on 2026-10-26, Ghidra 12.1.4 through REA 6.8.0. Target: extracted arm64 slice of installed Cleaner-App 9.7, SHA-256 `bd31b4f0845e8fe1e413c5658d75b14d2adac366e33e9cc655ef9723990cadd4`. The app was not executed by these probes. Results describe shipped code, not observed runtime behaviour.

## Findings

1. **Exact temporal threshold: strictly less than 60 seconds.** The comparison function at `0x100118ac0` reads two photo dates, returns false if either is missing, and compares their Unix timestamps. ARM64 at `0x100118c40` subtracts the second timestamp from the first; `0x100118c44` loads `0x404e000000000000` (IEEE-754 `60.0`); `0x100118c4c` compares; `0x100118c50` emits `cset w0, mi`. Thus equality at exactly 60 seconds is excluded. Pseudocode Evidence: `ev_66f411f4d127545ce8f802dd986e3478d2b329202f99ba46c3b1239d94e11586`; corroborating assembly Evidence: `ev_da5568e284f6250606e006a62c336aba8f32116da7ccb68ceb32f87a04c3bb21`.

2. **Consecutive chaining, not a fixed window from the first photo.** Group builder `0x100194cf4` explicitly loads input elements at index `i` and `i + 1`, invokes the supplied comparator, and starts/extends a group when the adjacent comparison succeeds. Therefore a chain of photos with adjacent gaps of 50 seconds can span more than 60 seconds in total. Evidence: `ev_a67ea1610ceef9954016e50316ba0d9fb788527991eaefa3bc1d91efc8f49ade`; assembly `ev_03b4cbdcb284121d83df74cb3a7eab506b2569d9ce5d968bd5fb64c8d2a65b03`.

3. **Date order is descending in the inspected sort path.** Insertion-sort helper `0x10011a0f8` obtains current and previous dates. ARM64 at `0x10011a2b0` compares the previous timestamp (`d9`) against the current timestamp (`d8`); it stops moving the current entry when the previous date is greater than or equal, otherwise swaps it left. This supports newest-first ordering, making the grouping subtraction nonnegative. Evidence: pseudocode `ev_0556c9df5053b1c8c2ab9fdb8f6967d0f1db321a1f6b879fcc9b512e1699eca4`; assembly `ev_ea20818e2fdfdbae6c0e68001feb3e0cb1f6f42c0d01e56ef39250a4c469c733`. The main sort dispatcher is `0x10011899c`, Evidence `ev_4370cbccc4cefd2a2f0e694cb636038a1f732b11e129297f73b63d240eb3e0f7`; only its small-input insertion path was instruction-checked, not every merge-sort branch.

4. **The compared date is the EXIF/parser date.** The comparator dispatches via stub `0x100397b20`, which loads selector slot `0x10054c778`. REA memory reads resolve that slot to string `0x100401745`, `getFileItemCreationDateFromExif`. Evidence: stub assembly `ev_2118b82b5857d70947772ef50bef5ad011eea7a62c0b72c99550ebcc710db2e9`; slot read `ev_655deb9f6810a9541bcec78dc0a51195ab198dfce2be629a50d7f0c9a3feff8c`; string read `ev_1553ddcc303d60273306fdcbd5c9a9e2996352eb03f318390a3ee0dfb7be14b7`.

5. **Parser fallback exists; filesystem creation-date fallback was not found in this path.** `FileSystemItem::getFileItemCreationDateFromExif` at `0x100015a30` lazily caches `NPHPictureItem`, calls `loadFromExif`, and returns its `creationDate`. `NPHPictureItem::loadFromExif` at `0x1000133d4` tries `ExifParcer`; if initialization fails, it tries `SimpleParcerISOBMFF`; if both fail, it returns false. On success it assigns the selected parser's `creationDate`. Evidence: `ev_8ea4277a372ad8d43699fb617c3a143383782254601d0b59e8f36a311d29a21b` and `ev_dcdb94a117835d5c015aeec97ee695abf0da51a7ed74332b8613383dcf88c423`. `SimpleExifParcer::prepareContentForURL:` at `0x10000a1ec` contains ImageIO metadata reads for EXIF `DateTimeOriginal`, `Orientation`, `PixelXDimension`, and `PixelYDimension`, plus `strptime_l` format `%Y:%m:%d %H:%M:%S` and `mktime` (local-time interpretation). Evidence `ev_bceb900fc3e01a5b86a781a346e1f706c41732c39577ca04a7143b08572aacb6`. Exact ISOBMFF date extraction and all malformed-metadata cases remain unexamined. A missing parser date cannot pass the grouping comparator; no filesystem date is substituted there.

6. **No same-directory requirement in the examined grouping stage.** Model `0x1001181d0` sorts one collected array and passes it to the adjacent grouping builder. The builder and date comparator do not compare file paths or parent folders. Hence this stage can chain photos from different folders when they are in the same input array. This is a bounded code-path finding, not proof of every upstream discovery/root-selection rule. Evidence: model `ev_198cedb1a9416c419df8f286e19ad77e1c8d5a4a7385e15c9b9e265b002624eb`; grouping and comparator Evidence above.

7. **Group size and an additional rejection predicate matter.** Model `0x1001181d0` ignores groups containing fewer than two entries. It also calls `0x10011acd0` and discards groups for which that predicate returns true. The predicate returns true when every entry has the first entry's logical size and the same optional parser date; unequal logical sizes or unequal dates cause false. No content hash is checked in this predicate. It is consistent with suppressing groups indistinguishable on those attributes, but the business intent is inference. Evidence: predicate `ev_06693fde244064fdce57c65fd373b96eef2c2be0e4b89fe997aabcf299be0d5b`; model `ev_198cedb1a9416c419df8f286e19ad77e1c8d5a4a7385e15c9b9e265b002624eb`.

## How the stripped Swift model was located

String inventory `ev_7190434d3f3d457b22b30f964f499b1147b908b0aca414066ad78b09fad667fc` identifies `PhotoSessionsModel` at `0x1004450d0`. Xrefs lead to class descriptor `0x100489530` (`ev_e190ff78b03c5df471694fb40bb0569309edaaa8a5213db0a26509ae3e198106`, `ev_8fc578f3d4c2402bda3a21932f29ca93205b0d0e10324fe46ba1a1181bf446d3`). Class metadata at `0x1005997d8` points to the concrete methods used above (`ev_9cb3f877755a088bdead5e810c7c9e423c587db46ca9ba0f5e20865eba9a9404`). The apparently related string reference at `0x10038cab0` was only an unimplemented-initializer trap, and was not used as grouping evidence.

## Consequences for MacSweep parity

- The initial 60-second setting was directionally correct, but its `<= 60` boundary differed from the observed strict `< 60`.
- Grouping by parent folder is an independent restriction; it is not present in the inspected original grouping stage.
- Falling back to filesystem creation time changes which photos participate. The observed path prefers EXIF/parser date and has an ISOBMFF parser fallback.
- Keep the additional same-size/same-date group rejection separate from byte-identical duplicate detection.
- These findings alone do not establish visual-similarity matching, support for every image format, all upstream photo selection rules, or complete behavioural equivalence.

Investigation was bounded to 32 photo-only static requests (100–131), plus existing date/EXIF outputs 013/014. No target switch, configuration mutation, bulk decompilation, or app execution occurred.

## Applied implementation alignment

Scanner.swift now applies strict `<60`, global consecutive capture-date chains,
missing-EXIF exclusion and the observed equal-size/equal-date group rejection.
ImageIO reads through a verified descriptor. ISOBMFF-only capture metadata is
still an explicit coverage gap. Scanner fixture tests include these boundaries.
