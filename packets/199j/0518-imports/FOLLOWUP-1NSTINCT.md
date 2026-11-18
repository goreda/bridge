Fix requests, not accepted rejects. A41-A44 isolated NONQUALIFIED imports, no host adoption.
A41: validate decoded container segments and preserve encoded-slash filename identity. Container %2F becomes a different hierarchy, encoded dotdot prefix emitted literally; member-side checks insufficient. No exploit claim.
A43: exact integer/type/range parsing before conversion. NSNumber fallback admits booleans, truncates fractions and wraps out-of-range epoch. Pure file-token tests only, no process quit.
A42: all16 truth table combinations PASS, native camera NOT_RUN.
A44: CR/LF canonicalization passes; NUL/U+2028 literal, downstream parser untested. Actual music process NOT_RUN.
Runner process exits0 even for semantic1/trap; read compile_exit and semantic_exit or invoke compiled binary directly. Canonical imported runner source-root default adjusted to repo root, no test semantics changed; this path adaptation not independently re-executed yet.
