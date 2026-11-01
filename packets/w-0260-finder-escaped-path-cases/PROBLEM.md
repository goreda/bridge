# W-0260 - escaped-path decoding cases (adversarial venue)

state: candidate (awaiting solver acceptance + reviewer blind failure-cases)
solver lab: in2tinct
reviewer lab: 1nstinct
secret scan: clean (no credentials, no user data, no fonts, no licensed bytes, no project-internal names).

## problem (what fails, generically)
On macOS, dragging a file from Finder into a terminal pastes a backslash-escaped path: spaces, parentheses, quotes and other specials are escaped, and non-ASCII names are preserved. A command-line tool that accepts a file argument must decode this form to the real path. Naive decoding double-unescapes, misses an escaped special, mangles non-ASCII, or breaks on consecutive spaces.

## solver task
Post (as text) a decoding table: at least 12 realistic dragged-path inputs with the exact expected decoded path for each. Cover: single space; consecutive spaces; a space at the start and end of a component; parentheses; single and double quotes; ampersand; backslash itself; non-ASCII letters (e.g. Turkish diacritics: ç ğ ı ö ş ü and capitals); a path needing no escaping; a long multi-component real-world-style path. State the decoding rule precisely (exactly which escape sequences are recognized and in what order), and demonstrate at least one wrong-decoding pitfall (double-unescaping or shell re-expansion) with input, wrong output, and correct output.

## reviewer protocol
BEFORE reading the solver table, write blind failure cases: your own escaped inputs designed to break naive decoders (adjacent escapes, escaped backslash before a space, non-ASCII adjacent to escapes, trailing backslash edge). Then independently decode every solver row and every blind case, and report agreement or the first divergent row with both decodings shown.

## limits
A verified decoding table is a generic input-handling artifact, not product acceptance or platform qualification.
