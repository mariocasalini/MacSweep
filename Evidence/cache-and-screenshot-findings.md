# Cleaner-App: cache/log paths and screenshot evidence

Inspected 2026-10-26 with the existing, user-authorized REA/Ghidra session. This was a bounded **static** investigation: 10 read-only probes (`150`–`159`). No target process was launched, no cleanup was invoked, no user data was scanned or modified, and no analysis settings or session lifecycle were changed.

## Target and evidence scope

- Target: arm64 slice of Cleaner-App 9.7, SHA-256 `bd31b4f0845e8fe1e413c5658d75b14d2adac366e33e9cc655ef9723990cadd4`.
- Provider: REA using Ghidra 12.1.4, source-immutable ephemeral import.
- Canonical request/response records: `work/rea-session/150-cache-screenshot.*.json` through `159-cache-root-biased.*.json` in the project at `/Users/mariolone/Documents/progettiPersonali/MacSweep`.
- These findings extend `static-symbol-findings.md`; they do not turn every literal listed there into a valid cleanup rule.

## Verified static observations

### Cache and log path construction — partially answered

The literal search for `~/Library/Caches` returned four provider-defined string objects:

| Address | Literal |
|---|---|
| `0x1003c8bb0` | `~/Library/Caches/Google` |
| `0x1003c8bd0` | `~/Library/Caches/CloudKit` |
| `0x1003c8d50` | `~/Library/Caches/Google/Chrome` |
| `0x1003c92d0` | `~/Library/Caches` |

Evidence: `ev_7d561feb240ead0940fc0ebbb784aa7313675d79dace5f5bc219369fc245b79a` (`150`).

A reference at `0x1000bce10` led to the concrete function `FUN_1000bc8e8`, with Ghidra function body `0x1000bc8e8`–`0x1000bdb67` (4,736 bytes). Its recovered code accesses the runtime fields `GroupsBuilder.rootTreeCheker`, `GroupsBuilder.searchItems`, and `GroupsBuilder.containersFolderURL`. Within a loop associated with the container URLs, it calls Foundation's URL path-component append operation with these **decoded Swift literals**:

| Call address | Decoded value | Literal bytes address |
|---|---|---|
| `0x1000bce7c` | `Data/Library/Caches` | `0x1003c92f0` |
| `0x1000bcef0` | `Data/Library/Logs` | `0x1003c9310` |
| `0x1000bd03c` | `~/Library/Caches/CloudKit` | `0x1003c8bd0` |

The first two calls establish actual suffix construction beyond mere literal presence. The third passes a CloudKit path literal to an indirect method. A subsequent URL loop invokes `NSFileManager.fileExistsAtPath:isDirectory:` and appends entries when the directory flag is true. Its broader role is consistent with constructing search/group inputs; the unresolved indirect methods prevent asserting a complete cleanup eligibility policy.

Evidence: `ev_6db6bb9ad87718d5ff1d0719d3d70be2e908f5f151cf0add1b8c15cffb27620e` (`153`, string reference) and `ev_a6d077486690133f7a47a6c9152942c63c3f1a895cd3fa4a9cf8dbf4119ecd52` (`156`, full function dossier).

**Important representation limitation:** a Swift large-string bridge word can point 32 bytes before the string's bytes. The reference to the nominal `~/Library/Caches` object led to a call whose decoded value is actually `Data/Library/Caches`. The REA dossier's `swift_string_literals` identifies the register pair and actual bytes address. Raw cross-references to adjacent string objects therefore do **not** alone establish which path is passed to a function.

The log literal search also found `~/Library/Logs/DiagnosticReports` at `0x1003c8a60` and a provider-defined `~/Library/Logs` object at `0x100593380`. This search does not establish active rules for either location. Evidence: `ev_2ccde3e4c51d50dea8594be6b3b3e8f407a8b9eb64e8e9ecce8d420e0284be54` (`158`).

### Screenshot detection — literal presence answered; validator unresolved

Earlier retained evidence `ev_7190434d3f3d457b22b30f964f499b1147b908b0aca414066ad78b09fad667fc` (`010`) identified:

- `kMDItemIsScreenCapture == 1` at `0x1003c84a0`.
- `com.apple.metadata:kMDItemIsScreenCapture` at `0x1003c1872`.

The predicate's exact-address reference query returned no analyzed references (`151`, `ev_01ec6b9da45b2eac6a8d7091dcd5b66daa947483bb18734105fd6cd467ac8cae`). The metadata string had one data reference at `0x1004fcc40` (`152`, `ev_9b67dddaebd39a0bcae0ec8cb64e6195feb6705cf94b76d3d95317e8c3fb6bd6`), but querying that object's references returned none (`154`, `ev_50fc100671063389bb0b340b18112d4788b82f294e1df99b10eb4e80a365495a`). A procedure-name search including `ScreenshotValidator` returned no names (`155`, `ev_106966a33da24bf1f5289c3a6c85a8d4e905fc5ea72b75da1e6aea9bd293aaca`). These negative results are bounded to the provider's recovered name/reference inventory; they do not demonstrate that the validator is absent or unused.

The exact screenshot prefix list, allowed extensions, PNG validation, fallback precedence, and execution path remain unresolved. MacSweep's metadata/name heuristic must remain labeled as an independent implementation.

## Deletion eligibility — unresolved; no scope expansion justified

This pass did **not** establish any of the following:

- Whether every file below a cache/log root is eligible.
- Age thresholds, locked-file rules, quick-removal versus manual-removal distinctions, or running-app exclusions.
- Whether CloudKit is included, excluded, or treated specially after the observed directory discovery.
- The full consumer of the constructed container-cache/container-log arrays.
- Whether any Safari `LocalStorage`, application-support data, DiagnosticReports, or other literal from the earlier strings report can safely be deleted.

The analyzed function has **16 unresolved computed/indirect call references**; REA explicitly marks callee relationship coverage partial. Ghidra pseudocode has low-confidence recovered parameter types and compiler-generated variables, and is neither original source nor guaranteed compilable. No runtime behavior was observed.

**Implementation consequence:** preserve MacSweep's conservative, user-reviewed user-cache/log scope. Do not add container paths, LocalStorage, application-support folders, system logs, or special browser locations merely from this pass. The recovered suffix construction improves the evidence map but does not establish faithful deletion parity.

## Probe ledger and bounded negatives

| Probe | Operation | Result / Evidence ID |
|---|---|---|
| 150 | `search_strings` literal `~/Library/Caches` | Four objects; `ev_7d561feb240ead0940fc0ebbb784aa7313675d79dace5f5bc219369fc245b79a` |
| 151 | `xrefs` screenshot predicate | Empty; `ev_01ec6b9da45b2eac6a8d7091dcd5b66daa947483bb18734105fd6cd467ac8cae` |
| 152 | `xrefs` screen-capture metadata name | Data reference; `ev_9b67dddaebd39a0bcae0ec8cb64e6195feb6705cf94b76d3d95317e8c3fb6bd6` |
| 153 | `xrefs` cache-root string address | Code reference; `ev_6db6bb9ad87718d5ff1d0719d3d70be2e908f5f151cf0add1b8c15cffb27620e` |
| 154 | `xrefs` metadata data object | Empty; `ev_50fc100671063389bb0b340b18112d4788b82f294e1df99b10eb4e80a365495a` |
| 155 | `search_procedures` cache/log model and screenshot-validator names | Empty; `ev_106966a33da24bf1f5289c3a6c85a8d4e905fc5ea72b75da1e6aea9bd293aaca` |
| 156 | `analyze_function` code reference | `FUN_1000bc8e8`; `ev_a6d077486690133f7a47a6c9152942c63c3f1a895cd3fa4a9cf8dbf4119ecd52` |
| 157 | `xrefs` nominal Google-cache string | Empty; `ev_a39c47efed378889ba5e8d7ad74581befb340ce54b8241f94aed94c0a34fcba7` |
| 158 | `search_strings` literal `~/Library/Logs` | Two objects; `ev_2ccde3e4c51d50dea8594be6b3b3e8f407a8b9eb64e8e9ecce8d420e0284be54` |
| 159 | `xrefs` cache-root address minus Swift large-string bias | Empty; `ev_5a0c7764496e1769083959b930d858c8be2708cdf3b01924172f18a3b369344c` |

All negative searches remain bounded. A future focused pass could trace the consumers of the constructed arrays or recover the cache-reader type's indirect dispatch; no additional rules should be inferred before that evidence exists.

## Independent candidate inventory added after this investigation

MacSweep offers a separate, off-by-default container cache/log inventory. It
constructs only the verified Data/Library/Caches and Data/Library/Logs suffixes
under immediate user container directories. This does not copy or certify the
original automatic deletion rules: every candidate still requires user selection
and exact-path confirmation. No LocalStorage, Documents, arbitrary Data or
Group Containers traversal is added. Twenty isolated fixture checks cover scope.

## Later runtime evidence
The 0.2.0 native UI investigation in cleaner-runtime-ui.md supersedes the earlier
static-only limitation for the three observed Chrome support-cache suffixes.
Scope remains an explicit allowlist; no arbitrary support data was added.
