# Cleaner-App: targeted static symbol and resource findings

Inspected locally on 2026-10-26. These are **ordinary system-tool observations**, not REA Evidence and not decompilation. No target code was executed, no user folders were scanned, and the installed app was not modified. Strings, selectors and class fields establish their presence in this build; they do not prove that a particular feature executes them.

## Inspected artifacts and reproducible commands

- Main executable: `/Applications/Cleaner-App.app/Contents/MacOS/Cleaner-App` (universal x86_64 + arm64; inspection selected arm64).
- Supporting binaries: `/Applications/Cleaner-App.app/Contents/Frameworks/NKFoundation.framework/Versions/A/NKFoundation`, `/Applications/Cleaner-App.app/Contents/Frameworks/NKCocoa.framework/Versions/A/NKCocoa`, `/Applications/Cleaner-App.app/Contents/Frameworks/NektonyFallManager.framework/Versions/A/NektonyFallManager`.
- English settings text: `/Applications/Cleaner-App.app/Contents/Resources/en.lproj/PreferencesStringsLocalizable.strings`.

SHA-256 identities (full universal binaries): main executable `dd6c874b264f92f7fdf3e2fd432af914741849ea40c4906378a84bf9310faed8`; NKFoundation `79a612091620c3ac36590bc8c03705b64e71c3e6db4bfa5dd281fcd074702373`; NKCocoa `a635377fc4939e8348c3a1d38e242aa85bb10aeee1521a1b2d5cda44acf3a877`.

```sh
/usr/bin/strings -arch arm64 /Applications/Cleaner-App.app/Contents/MacOS/Cleaner-App
/usr/bin/nm -arch arm64 /Applications/Cleaner-App.app/Contents/MacOS/Cleaner-App
/usr/bin/otool -arch arm64 -ov /Applications/Cleaner-App.app/Contents/MacOS/Cleaner-App
/usr/bin/otool -L /Applications/Cleaner-App.app/Contents/MacOS/Cleaner-App
/usr/bin/nm -arch arm64 /Applications/Cleaner-App.app/Contents/Frameworks/NKFoundation.framework/Versions/A/NKFoundation
/usr/bin/plutil -p /Applications/Cleaner-App.app/Contents/Resources/en.lproj/PreferencesStringsLocalizable.strings
```

Targeted filters: `duplicate|hash|PhotoSessions|Exif|Screenshot|Cache|Logs|minLogicalFileSize|minDuplicateFilesSize|kMDItem`.

## Duplicates and minimum sizes

**Observed, high confidence:** Swift runtime type names `Cleaner_App.DuplicatesSearcherImpl`, `Cleaner_App.FileItemHash`, `Cleaner_App.StringFileItemHash`, and `Cleaner_App.DuplicatesModel` occur in the main executable. Objective-C runtime metadata for `DuplicatesSearcherImpl` lists:

- `itemsBySize`
- `itemsBySizeAndHash`
- `hashCalculationQueue`
- `minLogicalFileSize`

**Observed, high confidence:** the executable contains these selectors:

- `calculateHashForItem:fullHash:`
- `hashforFile:`
- `hashforFilePartly:withSize:hashPartBlockLength:forFilesGreatherThan:forkToRead:` (the spelling `Greather` is in the artifact)
- `isNeedFullHashBuildForItem:`
- `configureReadSystemHashBlockSizeOnce`
- `hashBlockSize`

The main executable imports `_CC_MD5_Init`, `_CC_MD5_Update`, `_CC_MD5_Final`, `_SHA1_Init`, `_SHA1_Update`, `_SHA1_Final`, and `_memcmp`. NKFoundation separately exports `Foundation.URL.unsafeMD5()`, `String.MD5()`, and `String.unsafeMD5()`; these utility exports alone do not identify the duplicate hash.

**Inference, medium confidence:** size bucketing followed by hashing and a partial/full hash distinction is consistent with this structure. It is not yet proved which digest is used for duplicates, how partial blocks are chosen, whether forks are included, or whether a final byte-by-byte comparison occurs. **Do not label MacSweep's full SHA-256 comparison as the recovered proprietary algorithm.** It is an independent implementation choice.

**Observed, high confidence:** settings strings state that files below **32 KB** can be skipped, and offer checking all files. `minDuplicateFilesSizeKey`, `changeMinDuplicateFilesSize:`, `minDuplicateFilesSizeItem`, and `minSameNamesFilesSize` occur. The exact byte constant (32,000 versus 32,768), default persistence value, and equality boundary are **unresolved**; UI prose alone does not establish them.

## Photo series

**Observed, high confidence:** `Cleaner_App.PhotoSessionsModel`, `PhotoSessionsPresenterImpl`, `SimpleExifParcer`, `ExifParcer`, `getFileItemCreationDateFromExif`, `getFileItemCreationDate`, `contentCreationDate`, and `useCreationDate` occur. The adjacent EXIF vocabulary contains `DateTimeOriginal`, `PixelXDimension`, `PixelYDimension`, and the date format `%Y:%m:%d %H:%M:%S`.

**Inference, medium confidence:** capture/creation timestamps likely participate in photo grouping. **Unresolved:** interval, directory boundary, EXIF fallback order, chaining versus fixed window, and whether visual comparison is also involved. No numeric photo interval was established by this inspection. MacSweep's 60-second window and directory grouping remain explicitly documented design choices.

## Screenshots

**Observed, high confidence:** the exact Spotlight predicate `kMDItemIsScreenCapture == 1` occurs next to `Cleaner_App.ScreenshotsScanner` and `init(category:predicate:searchScopes:)`. The extended attribute name `com.apple.metadata:kMDItemIsScreenCapture` also occurs.

`ScreenshotValidator` runtime metadata contains two fields, `prefixes` and `fileExt`. The selector `isNeedFullCheckPNGAtPath:` occurs.

**Inference, medium confidence:** metadata-based discovery plus a name/extension validator is plausible. The exact prefix list, accepted extensions, PNG check and fallback precedence remain **unresolved**. MacSweep's English/Italian filename fallback is not claimed to be identical.

## Installer discovery

**Observed, high confidence:** the main executable contains the predicate `(kMDItemFSName ENDSWITH[c] '.dmg') OR (kMDItemFSName ENDSWITH[c] '.pkg')`.

**Inference, medium confidence:** at least one installer search covers DMG and PKG, case-insensitively. This does not establish whether another path also handles ISO/MPKG. MacSweep's additional installer extensions are an independent extension unless further evidence establishes parity.

## Cache and log paths

**Observed, high confidence:** runtime types `JunkApplicationLogsModel`, `JunkApplicationCachesModel`, `JunkBrowserCachesModel`, `CachesFilesReader`, and `CacheCategoriesManager` occur. `CachesFilesReader` metadata contains `contentReader`, `onlyForQuickRemove`, `roots`, `collector`, and `lock`.

The following literal roots/subpaths occur in the main executable:

```text
~/Library/Caches
~/Library/Logs
~/Library/Logs/DiagnosticReports
/Library/Logs/DiagnosticReports
~/Library/Containers
Data/Library/Caches
Data/Library/Logs
~/Library/Caches/Google
~/Library/Caches/CloudKit
~/Library/Caches/Google/Chrome
~/Library/Application Support/Google/Chrome/ShaderCache
~/Library/Application Support/Google/Chrome/Default/GPUCache
~/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage
~/Library/Application Support/Google/Chrome/Default/Service Worker/ScriptCache
~/Library/Safari/Favicon Cache
~/Library/Safari/LocalStorage
~/Library/Application Support/com.operasoftware.Opera/Application Cache/Index-journal
~/Library/Application Support/deezer-desktop/Service Worker/CacheStorage
~/Library/Application Support/Spotify/PersistentCache/Storage
~/Dropbox/.dropbox.cache/old_files
~/Dropbox/.dropbox.cache/icons
```

**Limits:** literal presence does not establish deletion eligibility, traversal depth, age thresholds, running-app exclusion, or whether each path belongs to an active cleanup rule. In particular, `LocalStorage` and application-support paths can contain useful persistent data. Do not automatically add these to deletion rules from strings alone. The original app also contains shared extension-management/support vocabulary that is not exposed in the observed navigation; this is not evidence of a working uninstaller in this product.

## Best next Ghidra seeds

1. Find references to `minDuplicateFilesSizeKey`; recover stored default and exact byte threshold.
2. Find references to the selectors `hashforFilePartly:withSize:hashPartBlockLength:forFilesGreatherThan:forkToRead:` and `calculateHashForItem:fullHash:`; establish callers, crypto choice, and comparison stages.
3. Locate `DuplicatesSearcherImpl` through its Swift metadata; follow code manipulating `itemsBySizeAndHash` and `minLogicalFileSize`.
4. Locate `PhotoSessionsModel` and uses of EXIF `DateTimeOriginal`; inspect timestamp comparisons for grouping window/fallback rules.
5. Find references to `kMDItemIsScreenCapture == 1` and `com.apple.metadata:kMDItemIsScreenCapture`; resolve `ScreenshotValidator` initialization and prefix/extension list.
6. Follow references to `~/Library/Caches`, `Data/Library/Caches`, and `~/Library/Safari/LocalStorage` into cache-category builders; establish exclusions before changing MacSweep cleanup scope.

The system `otool -ov` warns that some relative Objective-C method pointers extend past the file. Therefore its automatically printed relative IMP targets have **not** been promoted to verified function addresses here. Resolve functions in Ghidra's loaded image before citing addresses.
