# GorFit recovered regression suites
Run `bash Tests/Harness/GorFit/run.sh` from the gor root with Swift available. The runner compiles the production Sources/gor/GorFit.swift directly. SWIFTC can select the compiler. Output is kept in a new temporary directory, not deleted.
The only integration change to the reviewed runner is the default source path for this repository layout. Original archived sources and the two fence lexical spacing fixes are documented in PROVENANCE.txt and suite provenance/adaptations files.
Worker Swift5.10.1 Linux execution: fit21/21 and fence9/9; compiled before/after stdout identical. Ops independently checked source and logs, not compiler execution. This integration does not claim a new execution in the writer environment.
Native AppKit bridge/AppDelegate extension are excluded on Linux. Native Mac build and actual window behavior remain unverified; D3 is source-only pending normal native build. Fence tests use a glue replica, not native AppDelegate.
