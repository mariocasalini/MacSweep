# Many-small-file Trash performance — 0.1.6

Previous completed changes were committed/pushed first as e6408f4.

## Root causes
The old store serialized the entire growing history to an atomic JSON replacement before and after every move, synchronizing both the file and directory. Updating Model.history on every file also forced array copies and repeated UI work. Cache/log operations repeatedly searched all exact capabilities for each individual file. Regular file moves unnecessarily queried running applications.

## Change
The legacy JSON remains readable and unchanged. New per-record revisions append to .json.events; startup replays records by UUID in linear time. Intent is still synchronized before every move and completion afterward. First journal creation also synchronizes its parent directory. Torn/corrupt journals and any persistence failure block further moves. No delayed batch durability, parallel moves, permanent deletion or loss of preflight/identity/duplicate keeper verification.

Progress is limited to roughly 10 updates/second and history publishes once on completion or cancellation. Each cache/log move receives only its individually reviewed capability. Workspace running-app checks are skipped only for regular files, which cannot contain an application bundle; directory and explicit application-owner checks remain. Production continues to use Foundation trashItem and verified restoration.

## Measurement and validation
500 simulated journaled operations, with 1,000 prior history records, same local filesystem. Old persistence: 4.5075 s, 245,525,210 encoded/written bytes. Append persistence: 1.8421 s including reload verification, 186,680 appended bytes. This measures persistence only, not total Finder/Trash latency.

77 fixture checks passed: 32 scanner + 25 safety + 20 junk. Added 200 generated tiny-file moves into a separate fixture Trash, replay, actual restoration from the replayed journal, occupied destination rejection, legacy preservation, intent/completion replacement, private permissions, truncated journal, symlink journal, and failed-intent no-move checks. Real user files/real Trash were not used. Native build and extracted archive signature verified; strict UI audit zero findings.

The event log grows linearly with operations and is replayed on launch. Both the legacy JSON and its .events companion must be kept together for complete history; older app versions do not read new journal events. Native Trash calls still run sequentially, so per-file filesystem/cloud latency remains possible.
