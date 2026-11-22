#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

// W-gdb-033 vector file model + minimal JSON reader (no Foundation dependency,
// so the checker builds fast and stays portable).
//
// Op shapes (all clock times are virtual seconds):
//   {"firstFrame": {"anchor": A, "t": T, "playing?": Bool}}
//   {"read": {"t": T}, "expect": V-or-null}
//   {"seekCommitted": {"anchor": A-or-null, "t": T, "playing?": Bool}}
//   {"pause": {"t": T}} / {"resume": {"t": T}}

struct Vector {
    let name: String
    let duration: Double?
    let ops: [Op]
    let asserts: [String]
}

/// Per-read duration override: absent = inherit the vector duration,
/// null = uncapped for this read, number = cap this read.
enum DurationOverride {
    case inherit
    case value(Double?)
}

enum Op {
    case firstFrame(anchor: Double, t: Double, playing: Bool)
    case read(t: Double, expect: Double?, duration: DurationOverride)
    case seekCommitted(anchor: Double?, t: Double, playing: Bool)
    case pause(t: Double)
    case resume(t: Double)
}

enum JSON {
    case num(Double)
    case str(String)
    case bool(Bool)
    case null
    case arr([JSON])
    case obj([(String, JSON)])

    var asObj: [(String, JSON)]? { if case .obj(let o) = self { return o }; return nil }
    var asArr: [JSON]? { if case .arr(let a) = self { return a }; return nil }
    var asNum: Double? {
        if case .num(let n) = self { return n }
        return nil
    }
    var asStr: String? { if case .str(let s) = self { return s }; return nil }
    var asBool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    subscript(key: String) -> JSON? {
        guard case .obj(let o) = self else { return nil }
        for (k, v) in o where k == key { return v }
        return nil
    }
}

struct JSONParser {
    var chars: [Character]
    var i: Int = 0

    init(_ s: String) { chars = Array(s) }

    mutating func parse() -> JSON? {
        skipWS()
        let v = parseValue()
        skipWS()
        return v
    }

    private mutating func skipWS() {
        while i < chars.count, chars[i] == " " || chars[i] == "\t" || chars[i] == "\n" || chars[i] == "\r" { i += 1 }
    }

    private mutating func parseValue() -> JSON? {
        guard i < chars.count else { return nil }
        switch chars[i] {
        case "{": return parseObj()
        case "[": return parseArr()
        case "\"": return parseStr().map { JSON.str($0) }
        case "t":
            guard match("true") else { return nil }; return .bool(true)
        case "f":
            guard match("false") else { return nil }; return .bool(false)
        case "n":
            guard match("null") else { return nil }; return .null
        default: return parseNum()
        }
    }

    private mutating func match(_ word: String) -> Bool {
        let w = Array(word)
        guard i + w.count <= chars.count else { return false }
        for j in 0..<w.count where chars[i + j] != w[j] { return false }
        i += w.count
        return true
    }

    private mutating func parseObj() -> JSON? {
        i += 1 // {
        var out: [(String, JSON)] = []
        skipWS()
        if i < chars.count, chars[i] == "}" { i += 1; return .obj(out) }
        while true {
            skipWS()
            guard let k = parseStr() else { return nil }
            skipWS()
            guard i < chars.count, chars[i] == ":" else { return nil }
            i += 1
            skipWS()
            guard let v = parseValue() else { return nil }
            out.append((k, v))
            skipWS()
            guard i < chars.count else { return nil }
            if chars[i] == "," { i += 1; continue }
            if chars[i] == "}" { i += 1; return .obj(out) }
            return nil
        }
    }

    private mutating func parseArr() -> JSON? {
        i += 1 // [
        var out: [JSON] = []
        skipWS()
        if i < chars.count, chars[i] == "]" { i += 1; return .arr(out) }
        while true {
            skipWS()
            guard let v = parseValue() else { return nil }
            out.append(v)
            skipWS()
            guard i < chars.count else { return nil }
            if chars[i] == "," { i += 1; continue }
            if chars[i] == "]" { i += 1; return .arr(out) }
            return nil
        }
    }

    private mutating func parseStr() -> String? {
        guard i < chars.count, chars[i] == "\"" else { return nil }
        i += 1
        var s = ""
        while i < chars.count, chars[i] != "\"" {
            if chars[i] == "\\", i + 1 < chars.count {
                i += 1
                switch chars[i] {
                case "n": s.append("\n")
                case "t": s.append("\t")
                case "r": s.append("\r")
                case "\"": s.append("\"")
                case "\\": s.append("\\")
                case "/": s.append("/")
                case "u":
                    // \uXXXX basic-plane escape
                    guard i + 4 < chars.count else { return nil }
                    var code = 0
                    for j in 1...4 {
                        guard let d = chars[i + j].hexDigitValue else { return nil }
                        code = code * 16 + d
                    }
                    i += 4
                    if let scalar = Unicode.Scalar(code) { s.append(Character(scalar)) }
                default: return nil
                }
            } else {
                s.append(chars[i])
            }
            i += 1
        }
        guard i < chars.count else { return nil }
        i += 1 // closing quote
        return s
    }

    private mutating func parseNum() -> JSON? {
        let start = i
        if i < chars.count, chars[i] == "-" { i += 1 }
        while i < chars.count, chars[i].isNumber || chars[i] == "." || chars[i] == "e" || chars[i] == "E" || chars[i] == "+" || chars[i] == "-" {
            i += 1
        }
        guard i > start, let d = Double(String(chars[start..<i])) else { return nil }
        return .num(d)
    }
}

enum VectorLoadError: Error {
    case unreadable(String)
    case badJSON
    case badShape(String)
}

func loadVectors(from path: String) throws -> [Vector] {
    guard let text = readWholeFile(path) else { throw VectorLoadError.unreadable(path) }
    var parser = JSONParser(text)
    guard let root = parser.parse(), let arr = root["vectors"]?.asArr else { throw VectorLoadError.badJSON }
    var vectors: [Vector] = []
    for (vi, vj) in arr.enumerated() {
        guard let name = vj["name"]?.asStr else { throw VectorLoadError.badShape("vector[\(vi)] missing name") }
        let duration = vj["duration"].flatMap { $0.isNull ? nil : $0.asNum }
        guard let opsJSON = vj["ops"]?.asArr else { throw VectorLoadError.badShape("\(name): missing ops") }
        let asserts = vj["asserts"]?.asArr?.compactMap { $0.asStr } ?? []
        var ops: [Op] = []
        for (oi, oj) in opsJSON.enumerated() {
            if let f = oj["firstFrame"] {
                guard let a = f["anchor"]?.asNum, let t = f["t"]?.asNum else { throw VectorLoadError.badShape("\(name) op[\(oi)]: firstFrame needs anchor,t") }
                let playing = f["playing"].flatMap { $0.asBool } ?? true
                ops.append(.firstFrame(anchor: a, t: t, playing: playing))
            } else if let r = oj["read"] {
                guard let t = r["t"]?.asNum else { throw VectorLoadError.badShape("\(name) op[\(oi)]: read needs t") }
                guard let expectJSON = oj["expect"] else { throw VectorLoadError.badShape("\(name) op[\(oi)]: read missing expect") }
                let expect = expectJSON.isNull ? nil : expectJSON.asNum
                if expect == nil && !expectJSON.isNull { throw VectorLoadError.badShape("\(name) op[\(oi)]: expect not a number/null") }
                var dur: DurationOverride = .inherit
                if let dj = r["duration"] { dur = .value(dj.isNull ? nil : dj.asNum) }
                ops.append(.read(t: t, expect: expect, duration: dur))
            } else if let s = oj["seekCommitted"] {
                guard let t = s["t"]?.asNum else { throw VectorLoadError.badShape("\(name) op[\(oi)]: seekCommitted needs t") }
                let anchor = (s["anchor"]?.isNull ?? true) ? nil : s["anchor"]?.asNum
                let playing = s["playing"].flatMap { $0.asBool } ?? true
                ops.append(.seekCommitted(anchor: anchor, t: t, playing: playing))
            } else if let p = oj["pause"] {
                guard let t = p["t"]?.asNum else { throw VectorLoadError.badShape("\(name) op[\(oi)]: pause needs t") }
                ops.append(.pause(t: t))
            } else if let r = oj["resume"] {
                guard let t = r["t"]?.asNum else { throw VectorLoadError.badShape("\(name) op[\(oi)]: resume needs t") }
                ops.append(.resume(t: t))
            } else {
                throw VectorLoadError.badShape("\(name) op[\(oi)]: unknown op")
            }
        }
        vectors.append(Vector(name: name, duration: duration, ops: ops, asserts: asserts))
    }
    return vectors
}

// Whole-file read via Glibc (no Foundation).
func readWholeFile(_ path: String) -> String? {
    guard let f = fopen(path, "rb") else { return nil }
    defer { fclose(f) }
    fseek(f, 0, SEEK_END)
    let n = ftell(f)
    fseek(f, 0, SEEK_SET)
    guard n >= 0, let buf = malloc(n + 1) else { return nil }
    defer { free(buf) }
    let got = fread(buf, 1, n, f)
    guard got == n else { return nil }
    let cbuf = buf.assumingMemoryBound(to: CChar.self)
    cbuf[n] = 0
    return String(validatingCString: cbuf)
}
