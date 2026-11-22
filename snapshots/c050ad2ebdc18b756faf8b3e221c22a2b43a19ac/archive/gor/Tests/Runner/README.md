# Local GorAV Actions runner (190a R1, routing corrected by 190b)

The normal `./build.sh --update` continuation calls the installer once. A registered, running runner is skipped. `./build.sh --install-runner` also works directly. No browser page or token prompt is needed. Only on the owner's Mac, `git credential fill` reads the existing github.com credential in memory and calls GitHub's repository registration-token endpoint for private goreda/gorav. Configuration uses ACTIONS_RUNNER_INPUT_TOKEN, never a token argument. Credential/helper output and runner configuration output are captured or suppressed; inherited Git tracing is disabled. No credential or token is printed, copied into source, placed on the bridge, or stored outside the official runner's own configuration. Missing credentials or a 401/403/404 prints exactly `runner: credential scope missing` and exits 0. Other installation failures also leave the gor update nonfatal and preserve local state.

The official actions/runner v2.338.2 macOS arm64 archive is SHA-256 pinned to its release asset digest. It installs in ~/Library/gor-runner, and only a folder bearing this installer's repository-specific ownership marker may be repaired or removed. A partial owned install can resume. The user launchd service uses nice 10, taskpolicy background and low-priority I/O, with no sudo. Its plist and logs stay in that folder. A registered runner whose service stopped is repaired without a new registration token.

The supervisor waits while gor has any loaded file, including paused playback, and runs the listener one job at a time. Its synchronous job-start hook checks real gor mpv IPC again and waits until all loaded files stop. An unknown/unreachable live gor IPC is busy. It does not kill a job already running if the owner subsequently starts a movie, matching 189b's no-new-job rule. GitHub may assign a job to an already-listening runner while a movie is playing; workflow steps wait at the hook. A small state-change race remains between the final idle check and execution. There is no claim of kernel-atomic scheduling.

While the listener is active, AC status is checked every two seconds. `caffeinate -i -s` runs only on AC power and is stopped when battery power is observed. Lid-closed sleep is accepted. This is not a guarantee against macOS sleep or disconnection.

`./build.sh --remove-runner` obtains a repository removal token through the same local credential path, stops the owned user service, unregisters, then removes only the marked ~/Library/gor-runner folder. A failed unregister or missing scope preserves that folder. Unowned folders and other LaunchAgents files are never removed.

190b routing is a separate dispatcher/job-guard responsibility: goreda hosted first, gdb gorav-ci hosted second when goreda is at >=85% included usage or billing-blocked, and owner-mac only when both hosted legs are at >=85% or billing-blocked. Each dispatch reads both quotas and records the leg and both figures. The owner-mac guard must require leg=owner-mac plus the actor/ref/event restrictions. Installation does not dispatch a job or select the Mac for speed or convenience. Return to a hosted leg as soon as its quota is available. R2/R3 enforcement is not implemented by this local installer.

Linux checks:

```
python3 Tests/Runner/run.py
python3 Tests/Runner/test_auto_install.py -v
bash -n build.sh
```

These execute the production playback gate, real Unix socket exchange and mocked local credential/API/config/service/power/ownership paths. They do not use live credentials, register a runner, dispatch a workflow, or qualify native t1/l1-l4. Native macOS launchd, taskpolicy, sleep assertions, actual registration and the next normal update still need readback on the Mac. Existing delivery gate183 remains t1 plus l1-l4 PASS; Linux tests do not replace it.

Sources:
- https://api.github.com/repos/actions/runner/releases/tags/v2.338.2 (official asset digest)
- https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-osx-arm64-2.338.2.tar.gz
- https://raw.githubusercontent.com/actions/runner/v2.338.2/src/Runner.Listener/CommandSettings.cs (environment inputs)
- https://raw.githubusercontent.com/actions/runner/v2.338.2/src/Runner.Worker/JobHookProvider.cs (awaited pre-job hook)
- https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository
- https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-remove-token-for-a-repository
