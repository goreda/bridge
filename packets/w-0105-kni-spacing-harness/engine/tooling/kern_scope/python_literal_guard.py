#!/usr/bin/env python3
"""AST guard for numeric literals in Python production code (companion of the Rust kern_scope_guard).

Rule: production Python code holds no bare numeric constant. A numeric literal is
allowed only (a) as the value of a module-level assignment whose targets are all UPPER_SNAKE names (a named
constant), or (b) when its value is listed as structural for that file in the scope manifest (a declared
CONVENTION with a derivation). Constants named TEST_* are exempt only in files named test_*.py; a TEST_ name
anywhere else is a finding. The guard reads source text only; it never imports or runs the scanned file.

Scope manifest (TSV, columns below): every non-test .py file under the scanned root must be listed, either
`scoped` (scanned) or `unscoped` with a written reason (counted and reported, never silently skipped).
Usage: python_literal_guard.py ROOT MANIFEST.tsv     Exit 0 clean, 1 findings (stderr), 2 input error."""
import ast
import os
import re
import sys

MANIFEST_COLUMNS = ["file", "scope", "structural_values", "derivation"]
SCOPES = ["scoped", "unscoped"]
NUMBER_TYPES = (int, float, complex)
CONSTANT_NAME = re.compile(r"[A-Z][A-Z0-9_]*")
PREFIXED_NAME = re.compile(r"TEST_[A-Z0-9_]*")
TESTFILE_NAME = re.compile(r"test_[^/]*\.py")
SEPARATOR = ","
HEADER_LINES = 1
EXIT_CLEAN, EXIT_FINDINGS, EXIT_INPUT = 0, 1, 2
ARG_ROOT, ARG_MANIFEST, ARG_SUBDIRS = 1, 2, 3
GENERATE_FLAG = "--generate"
GENERATED_REASON = "not yet audited"


class GuardError(Exception):
    pass


def parse_manifest(text):
    lines = [l for l in text.split("\n") if l.strip()]
    if not lines or lines[0].split("\t") != MANIFEST_COLUMNS:
        raise GuardError("manifest: bad header")
    out = {}
    for n, l in enumerate(lines[HEADER_LINES:], HEADER_LINES + 1):
        f = l.split("\t")
        if len(f) != len(MANIFEST_COLUMNS):
            raise GuardError("manifest line %d: wrong field count" % n)
        name, scope, values, why = f
        if scope not in SCOPES:
            raise GuardError("manifest line %d: scope must be scoped or unscoped" % n)
        if not why.strip():
            raise GuardError("manifest line %d: derivation or reason required" % n)
        if name in out:
            raise GuardError("manifest line %d: duplicate file" % n)
        try:
            structural = {int(v) for v in values.split(SEPARATOR)} if values.strip() else set()
        except ValueError:
            raise GuardError("manifest line %d: structural_values must be integers" % n)
        if scope == "unscoped" and structural:
            raise GuardError("manifest line %d: unscoped file carries no structural values" % n)
        out[name] = (scope, structural)
    return out


def _is_constant_expr(node):
    if isinstance(node, ast.Constant):
        return True
    if isinstance(node, ast.UnaryOp):
        return _is_constant_expr(node.operand)
    if isinstance(node, ast.BinOp):
        return _is_constant_expr(node.left) and _is_constant_expr(node.right)
    if isinstance(node, (ast.Tuple, ast.List)):
        return all(_is_constant_expr(e) for e in node.elts)
    if isinstance(node, ast.Name):
        return bool(CONSTANT_NAME.fullmatch(node.id))
    return False


def _target_names(node):
    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
    names = []
    for t in targets:
        parts = t.elts if isinstance(t, ast.Tuple) else [t]
        for p in parts:
            if not isinstance(p, ast.Name):
                return None
            names.append(p.id)
    return names


def scan(source, filename, structural, is_test):
    """Return a list of (line, message). Pure function of the source text."""
    tree = ast.parse(source, filename=filename)
    findings, allowed_nodes = [], set()
    for node in tree.body:
        if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None:
            names = _target_names(node)
            if not names:
                continue
            if all(CONSTANT_NAME.fullmatch(n) for n in names):
                if any(PREFIXED_NAME.fullmatch(n) for n in names) and not is_test:
                    findings.append((node.lineno, "TEST_ constant outside a test_*.py file"))
                if _is_constant_expr(node.value):
                    allowed_nodes.update(id(x) for x in ast.walk(node.value))
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, NUMBER_TYPES) \
                and not isinstance(node.value, bool) and id(node) not in allowed_nodes:
            if isinstance(node.value, int) and node.value in structural:
                continue
            findings.append((node.lineno, "bare numeric literal %r" % (node.value,)))
    return sorted(findings)


def discover(root):
    out = []
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for f in sorted(files):
            if f.endswith(".py"):
                out.append(os.path.relpath(os.path.join(base, f), root).replace(os.sep, "/"))
    return out


def within(path, subdirs):
    return not subdirs or any(path == d or path.startswith(d.rstrip("/") + "/") for d in subdirs)


def run(root, manifest_text, subdirs=()):
    """Scan root; with subdirs, only files under those directories (relative to root) are in scope."""
    manifest = parse_manifest(manifest_text)
    found = [f for f in discover(root) if within(f, subdirs)]
    for f in manifest:
        if not within(f, subdirs):
            raise GuardError("%s: manifest entry lies outside the scan roots" % f)
    problems = []
    for f in found:
        if f not in manifest:
            problems.append("%s: python file not listed in the scope manifest" % f)
    for f in manifest:
        if f not in found:
            problems.append("%s: listed in the scope manifest but not found" % f)
    scoped = unscoped = 0
    for f in found:
        if f not in manifest:
            continue
        scope, structural = manifest[f]
        if scope == "unscoped":
            unscoped += 1
            continue
        scoped += 1
        with open(os.path.join(root, f), encoding="utf-8") as fh:
            src = fh.read()
        for line, msg in scan(src, f, structural, bool(TESTFILE_NAME.fullmatch(os.path.basename(f)))):
            problems.append("%s:%d: %s" % (f, line, msg))
    return problems, scoped, unscoped


def generate(root, manifest_text, subdirs=()):
    """Manifest text listing every .py under root: existing rows kept, new files added as unscoped."""
    manifest = parse_manifest(manifest_text) if manifest_text.strip() else {}
    lines = ["\t".join(MANIFEST_COLUMNS)]
    for f in (x for x in discover(root) if within(x, subdirs)):
        if f in manifest:
            continue
        lines.append("\t".join([f, "unscoped", "", GENERATED_REASON]))
    return lines


def main_generate(args):
    """--generate ROOT [EXISTING_MANIFEST]: print the manifest rows still missing (new files as unscoped)."""
    try:
        text = ""
        if len(args) > 1:
            with open(args[1], encoding="utf-8") as fh:
                text = fh.read()
        rows = generate(args[0], text)
    except (OSError, GuardError, IndexError) as e:
        sys.stderr.write("input error: %s\n" % e)
        return EXIT_INPUT
    print("\n".join(rows))
    return EXIT_CLEAN


def main(argv):
    if len(argv) > ARG_ROOT and argv[ARG_ROOT] == GENERATE_FLAG:
        return main_generate(argv[ARG_ROOT + 1:])
    try:
        with open(argv[ARG_MANIFEST], encoding="utf-8") as fh:
            problems, scoped, unscoped = run(argv[ARG_ROOT], fh.read(), tuple(argv[ARG_SUBDIRS:]))
    except (OSError, GuardError, SyntaxError, IndexError) as e:
        sys.stderr.write("input error: %s\n" % e)
        return EXIT_INPUT
    for p in problems:
        sys.stderr.write(p + "\n")
    print("scoped=%d unscoped=%d findings=%d" % (scoped, unscoped, len(problems)))
    return EXIT_FINDINGS if problems else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main(sys.argv))
