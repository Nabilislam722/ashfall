-- Minimal JSON for save files: tables with string keys (objects), sequences
-- (arrays), strings, numbers, booleans. Empty tables encode as []. Object keys
-- are sorted so the same game always produces the same text.
--
-- json.encode(value) -> string
-- json.decode(text)  -> value, or nil and an error message (never throws)

local json = {}

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n == #t
end

local function encode(value, depth)
    if depth > 32 then error("json: nested too deep") end
    local kind = type(value)
    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "0" end
        if value % 1 == 0 and math.abs(value) < 2 ^ 53 then return string.format("%d", value) end
        return string.format("%.6g", value)
    elseif kind == "string" then
        return encodeString(value)
    elseif kind == "table" then
        local parts = {}
        if isArray(value) then
            for i = 1, #value do parts[i] = encode(value[i], depth + 1) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(value) do
            if type(k) ~= "string" then error("json: object keys must be strings") end
            keys[#keys + 1] = k
        end
        table.sort(keys)
        for i, k in ipairs(keys) do
            parts[i] = encodeString(k) .. ":" .. encode(value[k], depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("json: can't encode a " .. kind)
end

function json.encode(value)
    return encode(value, 0)
end

-- ------------------------------------------------------------------ decoding

local function decodeError(pos, message)
    error({ json = true, message = message .. " at character " .. pos })
end

local function skip(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

local function utf8char(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local decodeValue

local function decodeString(text, pos)
    local parts = {}
    local i = pos + 1
    while true do
        local c = text:sub(i, i)
        if c == "" then decodeError(i, "unfinished string") end
        if c == '"' then return table.concat(parts), i + 1 end
        if c == "\\" then
            local e = text:sub(i + 1, i + 1)
            local simple = ({ ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[e]
            if simple then
                parts[#parts + 1] = simple
                i = i + 2
            elseif e == "u" then
                local hex = text:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then decodeError(i, "bad unicode escape") end
                parts[#parts + 1] = utf8char(tonumber(hex, 16))
                i = i + 6
            else
                decodeError(i, "bad escape")
            end
        else
            local j = text:find('["\\]', i) or #text + 1
            parts[#parts + 1] = text:sub(i, j - 1)
            i = j
        end
    end
end

local function decodeNumber(text, pos)
    local s, e = text:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not s then decodeError(pos, "bad number") end
    local n = tonumber(text:sub(s, e))
    if not n then decodeError(pos, "bad number") end
    return n, e + 1
end

local function decodeArray(text, pos, depth)
    local result = {}
    pos = skip(text, pos + 1)
    if text:sub(pos, pos) == "]" then return result, pos + 1 end
    while true do
        local value
        value, pos = decodeValue(text, pos, depth + 1)
        result[#result + 1] = value
        pos = skip(text, pos)
        local c = text:sub(pos, pos)
        if c == "]" then return result, pos + 1 end
        if c ~= "," then decodeError(pos, "expected , or ]") end
        pos = skip(text, pos + 1)
    end
end

local function decodeObject(text, pos, depth)
    local result = {}
    pos = skip(text, pos + 1)
    if text:sub(pos, pos) == "}" then return result, pos + 1 end
    while true do
        if text:sub(pos, pos) ~= '"' then decodeError(pos, "expected a key") end
        local key
        key, pos = decodeString(text, pos)
        pos = skip(text, pos)
        if text:sub(pos, pos) ~= ":" then decodeError(pos, "expected :") end
        local value
        value, pos = decodeValue(text, skip(text, pos + 1), depth + 1)
        result[key] = value
        pos = skip(text, pos)
        local c = text:sub(pos, pos)
        if c == "}" then return result, pos + 1 end
        if c ~= "," then decodeError(pos, "expected , or }") end
        pos = skip(text, pos + 1)
    end
end

decodeValue = function(text, pos, depth)
    if depth > 32 then decodeError(pos, "nested too deep") end
    pos = skip(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then return decodeObject(text, pos, depth) end
    if c == "[" then return decodeArray(text, pos, depth) end
    if c == '"' then return decodeString(text, pos) end
    if c == "-" or c:match("%d") then return decodeNumber(text, pos) end
    if text:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    if text:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    if text:sub(pos, pos + 3) == "null" then return nil, pos + 4 end
    decodeError(pos, "unexpected '" .. c .. "'")
end

function json.decode(text)
    if type(text) ~= "string" then return nil, "not text" end
    local ok, value, pos = pcall(decodeValue, text, 1, 0)
    if not ok then
        return nil, type(value) == "table" and value.message or tostring(value)
    end
    if skip(text, pos) <= #text then return nil, "extra text after the value" end
    return value
end

return json
