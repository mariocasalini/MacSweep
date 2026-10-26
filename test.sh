#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/tests build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Scanner.swift Tests/ScannerTests.swift -o build/tests/scanner-tests
build/tests/scanner-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Safety.swift Tests/SafetyTests.swift -o build/tests/safety-tests
build/tests/safety-tests

swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Scanner.swift Sources/Safety.swift Sources/JunkScanner.swift Tests/JunkScannerTests.swift -o build/tests/junk-tests
build/tests/junk-tests
