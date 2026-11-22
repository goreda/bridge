-- P29-LIVE-CONTROL authoritative Lua reference runner (DR-0021, lane c).
-- Executes the EXACT pinned photon-live-control.lua (M.VERSION=1, SHA256
-- 4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76 - the
-- driver regenerate-reference.sh verifies the hash before running) under
-- real LuaJIT, replaying the ops from live-control-vectors.json, and emits
-- live-control-lua-reference.json (raw captured outputs) on stdout.
-- This script is a runner only: it does not modify or re-implement the
-- pinned Lua; every expect below is captured from the pinned script's own
-- return values and instance fields. Harness config closures are test
-- fixtures (identical semantics in the Python model replay and the Swift
-- witness) - the pinned script takes them as injected config.
-- Usage: luajit run-live-control.lua VECTORS_JSON PINNED_SCRIPT_LUA

local vectorsPath, scriptPath = arg[1], arg[2]
assert(vectorsPath and scriptPath, "usage: luajit run-live-control.lua VECTORS_JSON SCRIPT_LUA")

-- ------------------------------------------------------------- JSON I/O --
local jsonNull = setmetatable({}, { __tostring = function() return "null" end })

local function decodeJson(text)
    local pos = 1
    local function fail(msg) error("json: " .. msg .. " at byte " .. pos, 0) end
    local parseValue
    local function ws()
        local _, e = text:find("^[ \t\r\n]*", pos)
        pos = (e or pos - 1) + 1
    end
    local function parseString()
        pos = pos + 1 -- opening quote
        local out = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unterminated string")
            elseif c == '"' then pos = pos + 1; return table.concat(out)
            elseif c == "\\" then
                local e = text:sub(pos + 1, pos + 1)
                local m = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
                            f = "\f", n = "\n", r = "\r", t = "\t" }
                if e == "u" then
                    local code = tonumber(text:sub(pos + 2, pos + 5), 16) or fail("bad \\u")
                    out[#out + 1] = utf8 and utf8.char(code) or string.char(code)
                    pos = pos + 6
                else
                    out[#out + 1] = m[e] or fail("bad escape " .. e)
                    pos = pos + 2
                end
            else
                out[#out + 1] = c; pos = pos + 1
            end
        end
    end
    local function parseObject()
        local o = {}
        pos = pos + 1; ws()
        if text:sub(pos, pos) == "}" then pos = pos + 1; return o end
        while true do
            ws()
            if text:sub(pos, pos) ~= '"' then fail("object key expected") end
            local k = parseString()
            ws()
            if text:sub(pos, pos) ~= ":" then fail("':' expected") end
            pos = pos + 1; ws()
            o[k] = parseValue()
            ws()
            local c = text:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "}" then pos = pos + 1; return o
            else fail("',' or '}' expected") end
        end
    end
    local function parseArray()
        local a = {}
        pos = pos + 1; ws()
        if text:sub(pos, pos) == "]" then pos = pos + 1; return a end
        while true do
            ws()
            a[#a + 1] = parseValue()
            ws()
            local c = text:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "]" then pos = pos + 1; return a
            else fail("',' or ']' expected") end
        end
    end
    parseValue = function()
        ws()
        local c = text:sub(pos, pos)
        if c == "{" then return parseObject()
        elseif c == "[" then return parseArray()
        elseif c == '"' then return parseString()
        elseif c == "t" then assert(text:sub(pos, pos + 3) == "true", "bad literal"); pos = pos + 4; return true
        elseif c == "f" then assert(text:sub(pos, pos + 4) == "false", "bad literal"); pos = pos + 5; return false
        elseif c == "n" then assert(text:sub(pos, pos + 3) == "null", "bad literal"); pos = pos + 4; return jsonNull
        else
            local s, e = text:find("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if not s or e < pos then fail("value expected") end
            pos = e + 1
            return tonumber(text:sub(s, e)) or fail("bad number")
        end
    end
    local v = parseValue()
    ws()
    return v
end

local function encodeJson(v)
    local t = type(v)
    if v == jsonNull or v == nil then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
        assert(v == v and math.abs(v) < math.huge, "non-finite number in reference output")
        return string.format("%.17g", v)
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
            return m[c] or string.format("\\u%04x", string.byte(c))
        end) .. '"'
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = encodeJson(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = encodeJson(k) .. ":" .. encodeJson(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("json: cannot encode " .. t)
end

-- ------------------------------------------------------------- fixtures --
-- Harness config closures (test fixtures; identical semantics in the Python
-- model replay and the Swift witness). The pinned script injects these.
local function baseConfig()
    local cfg = {
        initial_gamma = 1.0,
        qualified = true,
        rate = 0.5,
        stale_age = 0.5,
        callback_gap = 0.5,
        reference_interval = 1.0 / 24.0,
        retention = 0.5,
        max_settlement_samples = 3,
        feed_calls = 0,
    }
    cfg.classify_cut = function(old, new)
        local d = math.abs(new.pbs - old.pbs)
        if d > 30 then return "confirmed" elseif d > 15 then return "candidate" end
        return nil
    end
    cfg.settled = function(profiles)
        if #profiles < 2 then return false end
        local lo, hi = profiles[1].pbs, profiles[1].pbs
        for _, p in ipairs(profiles) do
            if p.pbs < lo then lo = p.pbs end
            if p.pbs > hi then hi = p.pbs end
        end
        return hi - lo < 5
    end
    cfg.target = function(profile, velocity)
        return math.max(0.5, math.min(2.0, 1.0 + (profile.pbs - 100.0) / 100.0))
    end
    cfg.velocity = function(old, new, prev)
        return (new.pbs - old.pbs) / (new.t - old.t)
    end
    cfg.feed = function(profile) cfg.feed_calls = cfg.feed_calls + 1 end
    return cfg
end

local function buildProfile(raw)
    if raw == nil or raw == jsonNull then return nil end
    local p = {}
    for k, v in pairs(raw) do
        if v ~= jsonNull then p[k] = v end  -- `a and nil or b` would keep the sentinel
    end
    return p
end

local function captureExpect(s, cfg, returned)
    local d = s:diagnostics()
    return {
        state = d.state,
        reason = (d.reason ~= nil) and d.reason or jsonNull,
        cut_pending = d.cut_pending,
        settlement_samples = d.settlement_samples,
        held_gamma = d.held_gamma,
        velocity = (s.velocity ~= nil) and s.velocity or jsonNull,
        target = (s.target ~= nil) and s.target or jsonNull,
        feed_calls = cfg.feed_calls,
        returned = (function() if returned == nil then return jsonNull else return returned end end)(),
    }
end

-- ----------------------------------------------------------------- main --
local M = dofile(scriptPath)
assert(type(M) == "table" and M.VERSION == 1, "pinned script did not return M.VERSION=1")

local fh = assert(io.open(vectorsPath, "r"))
local input = decodeJson(fh:read("*a"))
fh:close()

local outVectors = {}
local compared = 0
for _, vector in ipairs(input.vectors) do
    local cfg = baseConfig()
    if vector.config and vector.config.rate then cfg.rate = vector.config.rate end
    local s = M.new(cfg)
    local outSteps = {}
    for _, step in ipairs(vector.steps) do
        local op = step.op
        local expect = nil
        if op == "observe" then
            expect = captureExpect(s, cfg, s:observe(buildProfile(step.profile)))
        elseif op == "observeRaw" then
            expect = captureExpect(s, cfg, s:observe(buildProfile(step.profile)))
        elseif op == "observeNaN" then
            local p = buildProfile(step.profile)
            p[step.nanField] = 0 / 0
            expect = captureExpect(s, cfg, s:observe(p))
        elseif op == "tick" then
            expect = captureExpect(s, cfg, s:tick(step.nowUs / 1e6))
        elseif op == "tickRaw" then
            expect = captureExpect(s, cfg, s:tick(0 / 0))
        elseif op == "setTargetNaN" then
            cfg.target = function(profile, velocity) return 0 / 0 end
        elseif op == "freshUnqualified" then
            local cfg2 = baseConfig(); cfg2.qualified = false
            local s2 = M.new(cfg2)
            expect = captureExpect(s2, cfg2, s2:observe(buildProfile(step.profile)))
        elseif op == "freshUnqualifiedTick" then
            local cfg2 = baseConfig(); cfg2.qualified = false
            local s2 = M.new(cfg2)
            s2:observe(buildProfile(step.profile))
            expect = captureExpect(s2, cfg2, s2:tick(step.nowUs / 1e6))
        elseif op == "freshStaleTick" then
            local cfg2 = baseConfig()
            local s2 = M.new(cfg2)
            s2:tick(step.nowUs / 1e6 - 0.1)
            expect = captureExpect(s2, cfg2, s2:tick(step.nowUs / 1e6))
        else
            error("unknown op " .. tostring(op))
        end
        local outStep = { op = op }
        for k, v in pairs(step) do outStep[k] = v end
        if expect ~= nil then outStep.expect = expect; compared = compared + 1 end
        outSteps[#outSteps + 1] = outStep
    end
    outVectors[#outVectors + 1] = { name = vector.name, config = vector.config, steps = outSteps }
end

print(encodeJson({
    source = input.source,
    derivation = "lua-execution (AUTHORITATIVE): raw outputs captured by running the exact pinned script under real LuaJIT",
    executedLua = true,
    runtime = jit.version .. " (built from source, github.com/LuaJIT/LuaJIT branch v2.1)",
    scriptSha256 = "4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76",
    runner = "Sources/live-control-tests/lua-reference/run-live-control.lua",
    comparedSteps = compared,
    vectors = outVectors,
}))
io.write("\n")
