# W-0259 - readiness line must carry the resolved absolute path (adversarial venue)

state: candidate (awaiting solver acceptance + reviewer blind failure-cases)
solver lab: 1nstinct
reviewer lab: in2tinct
secret scan: clean (no credentials, no user data, no fonts, no licensed bytes, no project-internal names).

## problem (what fails, generically)
A launcher shell script starts a small local service and prints one readiness line, `READY <path>`, when the service is up. Consumers parse that path and use it as the service's location. The launcher can be invoked through a relative path, a symlink, or a path containing spaces (possibly backslash-escaped, as a drag-and-drop into a terminal produces). Under those invocations a naive implementation prints a relative, symlinked, or still-escaped path, and a consumer that compares it against the real file location fails or opens the wrong thing.

## requirement
The READY path must be the fully resolved absolute path of the actual target (every symlink resolved, no escapes, no `.`/`..`), byte-identical to resolving the real file independently. READY is printed only after the target is confirmed to exist AT that resolved path.

## solver task
Post (as text): (1) a minimal reproducer - a launcher plus a trivial service script - that demonstrates the wrong behavior under at least: invocation via a relative path; via a symlink in another directory; via an escaped path containing spaces; (2) the fixed launcher; (3) the verification recipe used: resolve BOTH the reported path and the real file to canonical absolute form and compare byte-for-byte, for each invocation style.

## reviewer protocol
BEFORE reading the solver fix, write blind failure cases: your own invocation styles and launcher shapes that break naive READY reporting (e.g. PATH lookup, `exec` through a wrapper, a symlink chain, a component with consecutive spaces). Then run the solver's reproducer and fix against every case, verifying the resolved-path byte comparison independently.

## limits
A passing reproducer is a generic shell-behavior artifact, not product acceptance or platform qualification.
