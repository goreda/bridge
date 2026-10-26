item: gor r14 whole-resource safe materializer and tests
owner: SJF kit integration; lab writes only proposed new Python module+tests, not AppDelegate/build.sh
source: attached exact accepted build.sh/test_staging.py/GOR-CLOSURE.json. Official archive https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos.zip SHA25607e54b0865303c864006925913bce2604f8ee8cc6f18699bac9c309f9328a6d8 size53923637.
interface: materialize_verified_zip(archive_path, destination_path, expected_zip_sha, manifest_dict) using stdlib only, offline after explicitarchiveinput. Produce newdir atomically, preserve ZIP executable modes. No user paths/network/defaultinstall/overwrite/deleteexistingtree. Caller controls final apply after fullkitbackup.
tests: actual134filemanifest; reject traversal/absolute/duplicate/symlink/nonregular/extra/missing/hashmismatch/wrongZIPsha, pathancestor symlink, destinationexisting; clean interruption no halfvisiblefinaltree; executablemode preserved. Use tempfixtures, no credentials.
target: proposed kit helper under isolated gor-r14 package, NOTproductrepo unknown; integrator owns final owner-localkit. No push/merge/deploy.
done-when: actual Pythonimplementation+unitregressions+recorded command/exit, no mocks pretending actual134filearchive; tests may use smaller syntheticfixtures plus optional actualofficialarchivecase. No Mac/codesign/CDN403claim.
