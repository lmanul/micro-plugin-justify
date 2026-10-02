VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")

-- Comment and quote markers recognized at the start of a line. They may
-- repeat ("> > quoted", "# > quoted in a comment") and are repeated on every
-- line of the justified paragraph.
local CODE_MARKERS = { "//+", "#+", "%-%-+", ";+", "%%+", ">+" }
local C_STYLE_MARKERS = { "//+", "/%*+", "%*+", "#+", "%-%-+", ";+", "%%+", ">+" }
local TEXT_MARKERS = { ">+" }

-- Filetypes with /* ... */ block comments, where a leading "*" is a comment
-- continuation rather than a list bullet.
local C_STYLE_FILETYPES = {
    ["c"] = true, ["c++"] = true, ["csharp"] = true, ["css"] = true,
    ["d"] = true, ["dart"] = true, ["glsl"] = true, ["go"] = true,
    ["groovy"] = true, ["java"] = true, ["javascript"] = true,
    ["kotlin"] = true, ["less"] = true, ["objc"] = true, ["php"] = true,
    ["pony"] = true, ["proto"] = true, ["rust"] = true, ["scala"] = true,
    ["scss"] = true, ["swift"] = true, ["typescript"] = true, ["v"] = true,
}

-- Prose filetypes, where "#", "-", "*" etc. have their own meaning.
local TEXT_FILETYPES = {
    ["asciidoc"] = true, ["markdown"] = true, ["rst"] = true,
}

local BULLET_PATTERNS = { "^[-*+][ \t]+", "^%d+[.)][ \t]+", "^\226\128\162[ \t]+" }

-- Number of characters (not bytes) in a UTF-8 string.
local function charCount(s)
    return select(2, s:gsub("[^\128-\191]", ""))
end

-- Width of a string on screen, expanding tabs.
local function visualWidth(s, tabsize)
    local w = 0
    for chunk, tabs in s:gmatch("([^\t]*)(\t*)") do
        w = w + charCount(chunk)
        if #tabs > 0 then
            w = (math.floor(w / tabsize) + #tabs) * tabsize
        end
    end
    return w
end

-- Splits a line into the prefix to keep (indentation, comment markers, list
-- bullet) and the text to rewrap.
--   prefix: what the first line of a paragraph starting here begins with
--   cont:   what the following lines of that paragraph begin with
--   fixed:  the line is not part of any paragraph and is never touched
--   item:   the line starts a list item, and therefore a new paragraph
local function parseLine(line, markers, prose)
    local pos = #line:match("^[ \t]*") + 1
    local found = true
    while found do
        found = false
        for _, m in ipairs(markers) do
            local _, e = line:find("^" .. m .. "[ \t]*", pos)
            if e then
                pos = e + 1
                found = true
                break
            end
        end
    end

    local prefix = line:sub(1, pos - 1)
    local text = line:sub(pos):gsub("[ \t]+$", "")
    local entry = { prefix = prefix, cont = prefix, text = text, item = false }

    if text == ""
        or line:match("^[ \t]*%*+/[ \t]*$")              -- end of a /* */ comment
        or (text:match("^[-=*_~#+]+$") and #text >= 3)   -- horizontal rule
        or (prose and (text:match("^#") or text:match("^```")
                       or text:match("^~~~") or text:match("^|"))) then
        entry.fixed = true
        return entry
    end

    for _, p in ipairs(BULLET_PATTERNS) do
        local bullet = text:match(p)
        if bullet then
            entry.item = true
            entry.prefix = prefix .. bullet
            entry.cont = prefix .. string.rep(" ", charCount(bullet))
            entry.text = text:sub(#bullet + 1)
            break
        end
    end
    return entry
end

-- Last row of the paragraph that starts at row `start`.
local function paragraphEnd(entry, start, last)
    local cont = entry(start).cont
    local stop = start
    while stop < last do
        local e = entry(stop + 1)
        if e.fixed or e.item or e.prefix ~= cont then
            break
        end
        stop = stop + 1
    end
    return stop
end

-- First row of the paragraph that contains row `row`.
local function paragraphStart(entry, row, first)
    local start = row
    while start > first and not entry(start).item do
        local prev = entry(start - 1)
        if prev.fixed or prev.cont ~= entry(start).prefix then
            break
        end
        start = start - 1
    end
    return start
end

-- Greedily fills lines with words, up to `width` columns where possible.
local function fill(words, first, cont, width, tabsize)
    local out = {}
    local line, used = first, visualWidth(first, tabsize)
    local contWidth = visualWidth(cont, tabsize)
    local empty = true
    for _, w in ipairs(words) do
        local n = charCount(w)
        if empty then
            line, used, empty = line .. w, used + n, false
        elseif used + 1 + n <= width then
            line, used = line .. " " .. w, used + 1 + n
        else
            out[#out + 1] = line
            line, used = cont .. w, contWidth + n
        end
    end
    out[#out + 1] = line
    return out
end

-- Justifies text, independently of micro so that it can be tested.
--   getLine(row) returns the line at 0-based `row`; there are `nlines` lines.
--   With `to` set, every paragraph in rows from..to is justified. Otherwise,
--   the paragraph at or after row `from` is.
--   opts: { width = ..., tabsize = ..., markers = ..., prose = ... }
-- Returns the first and last rows that were considered and their new lines,
-- or nil if there is nothing to justify.
function reflow(getLine, nlines, from, to, opts)
    local cache = {}
    local function entry(row)
        if cache[row] == nil then
            cache[row] = parseLine(getLine(row), opts.markers, opts.prose)
        end
        return cache[row]
    end

    if to == nil then
        local row = from
        while row < nlines and entry(row).fixed do
            row = row + 1
        end
        if row >= nlines then
            return nil
        end
        from = paragraphStart(entry, row, 0)
        to = paragraphEnd(entry, from, nlines - 1)
    end

    local out = {}
    local row = from
    while row <= to do
        local e = entry(row)
        if e.fixed then
            out[#out + 1] = getLine(row)
            row = row + 1
        else
            local stop = paragraphEnd(entry, row, to)
            local words = {}
            for r = row, stop do
                local text = entry(r).text
                for w in string.gmatch(text, "%S+") do
                    words[#words + 1] = w
                end
            end
            for _, l in ipairs(fill(words, e.prefix, e.cont, opts.width, opts.tabsize)) do
                out[#out + 1] = l
            end
            row = stop + 1
        end
    end
    return from, to, out
end

local function targetWidth(buf, args)
    if args ~= nil and #args > 0 then
        local n = tonumber(args[1])
        if n == nil or n < 1 then
            return nil, "Invalid width: " .. args[1]
        end
        return math.floor(n)
    end
    local w = tonumber(buf.Settings["justify.width"]) or 0
    if w > 0 then
        return math.floor(w)
    end
    local cc = tonumber(buf.Settings["colorcolumn"]) or 0
    if cc > 0 then
        return math.floor(cc)
    end
    return 80
end

function justify(bp, args)
    local buf = bp.Buf
    if buf.Type.Readonly then
        micro.InfoBar():Error("Cannot justify a read-only buffer")
        return
    end
    local width, err = targetWidth(buf, args)
    if width == nil then
        micro.InfoBar():Error(err)
        return
    end

    local ft = buf.Settings["filetype"]
    local markers = CODE_MARKERS
    if TEXT_FILETYPES[ft] then
        markers = TEXT_MARKERS
    elseif C_STYLE_FILETYPES[ft] then
        markers = C_STYLE_MARKERS
    end
    local opts = {
        width = width,
        tabsize = tonumber(buf.Settings["tabsize"]) or 4,
        markers = markers,
        prose = TEXT_FILETYPES[ft] ~= nil,
    }

    local cursor = bp.Cursor
    local nlines = buf:LinesNum()
    local from, to
    if cursor:HasSelection() then
        local a, b = -cursor.CurSelection[1], -cursor.CurSelection[2]
        if a:GreaterThan(b) then
            a, b = b, a
        end
        from, to = a.Y, b.Y
        if b.X == 0 and to > from then
            to = to - 1
        end
    else
        from = cursor.Loc.Y
    end

    local first, last, lines = reflow(function(r) return buf:Line(r) end, nlines, from, to, opts)
    if first == nil then
        micro.InfoBar():Message("Nothing to justify")
        return
    end

    local old = {}
    for r = first, last do
        old[#old + 1] = buf:Line(r)
    end
    local text = table.concat(lines, "\n")
    if text ~= table.concat(old, "\n") then
        -- Replace whole lines, so that no column offsets need computing.
        if last + 1 < nlines then
            buf:Replace(buffer.Loc(0, first), buffer.Loc(0, last + 1), text .. "\n")
        else
            buf:Replace(buffer.Loc(0, first), buf:End(), text)
        end
    end

    -- Like nano, move to the line after the paragraph, so that justifying
    -- repeatedly walks through the following paragraphs.
    local after = first + #lines
    cursor:ResetSelection()
    if after < buf:LinesNum() then
        cursor:GotoLoc(buffer.Loc(0, after))
    else
        cursor:GotoLoc(buf:End())
    end
    cursor:Relocate()
    cursor:StoreVisualX()
    bp:Relocate()
end

function preinit()
    config.RegisterCommonOption("justify", "width", 0)
end

function init()
    config.MakeCommand("justify", justify, config.NoComplete)
    config.TryBindKey("Alt-j", "lua:justify.justify", false)
    config.AddRuntimeFile("justify", config.RTHelp, "help/justify.md")
end
