-- Tests for the text logic of justify.lua, run outside micro:
--   lua tests/test.lua

function import()
    return {}
end
dofile((arg[0]:gsub("tests/test.lua$", "")) .. "justify.lua")

local CODE = { "//+", "#+", "%-%-+", ";+", "%%+", ">+" }
local C_STYLE = { "//+", "/%*+", "%*+", "#+", "%-%-+", ";+", "%%+", ">+" }
local TEXT = { ">+" }

local failures = 0

-- Runs reflow on `input` (a list of lines) and compares the whole resulting
-- buffer with `expected`.
local function check(name, input, expected, opts)
    opts.tabsize = opts.tabsize or 4
    opts.markers = opts.markers or CODE
    local first, last, lines = reflow(function(r) return input[r + 1] end,
        #input, opts.row or 0, opts.to, opts)
    local result = {}
    if first == nil then
        result = input
    else
        for i = 1, first do result[#result + 1] = input[i] end
        for _, l in ipairs(lines) do result[#result + 1] = l end
        for i = last + 2, #input do result[#result + 1] = input[i] end
    end
    local got, want = table.concat(result, "\n"), table.concat(expected, "\n")
    if got == want then
        print("ok    " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. "\n--- expected:\n" .. want .. "\n--- got:\n" .. got)
    end
end

check("plain paragraph", {
    "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.",
}, {
    "The quick brown fox jumps over the",
    "lazy dog. The quick brown fox jumps",
    "over the lazy dog.",
}, { width = 36 })

check("joins short lines", {
    "one",
    "two",
    "three",
}, {
    "one two three",
}, { width = 80 })

check("stops at blank lines, cursor in second paragraph", {
    "first paragraph",
    "stays",
    "",
    "second",
    "paragraph",
    "",
    "third",
    "too",
}, {
    "first paragraph",
    "stays",
    "",
    "second paragraph",
    "",
    "third",
    "too",
}, { width = 80, row = 4 })

check("cursor on blank line justifies the next paragraph", {
    "",
    "",
    "a",
    "b",
}, {
    "",
    "",
    "a b",
}, { width = 80, row = 0 })

check("nothing to justify", { "", "  ", "" }, { "", "  ", "" }, { width = 80 })

check("keeps indentation", {
    "    alpha beta gamma delta epsilon",
    "    zeta",
}, {
    "    alpha beta gamma",
    "    delta epsilon zeta",
}, { width = 24 })

check("indentation change ends the paragraph", {
    "alpha beta",
    "    gamma delta",
}, {
    "alpha beta",
    "    gamma delta",
}, { width = 80 })

check("tab width counts towards the width", {
    "\talpha beta gamma",
}, {
    "\talpha beta",
    "\tgamma",
}, { width = 18, tabsize = 8 })

check("hash comments", {
    "# Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod",
    "# tempor.",
    "#",
    "# Next paragraph.",
}, {
    "# Lorem ipsum dolor sit amet,",
    "# consectetur adipiscing elit, sed",
    "# do eiusmod tempor.",
    "#",
    "# Next paragraph.",
}, { width = 36 })

check("indented double-slash comments, code above and below untouched", {
    "int x;",
    "    // aaa bbb ccc",
    "    // ddd eee fff ggg",
    "    return;",
}, {
    "int x;",
    "    // aaa bbb ccc ddd eee",
    "    // fff ggg",
    "    return;",
}, { width = 26, row = 2 })

check("repeated markers", {
    "### one two three four five six",
}, {
    "### one two three",
    "### four five six",
}, { width = 20 })

check("nested email quotes", {
    "> > aaa bbb ccc ddd eee",
}, {
    "> > aaa bbb ccc",
    "> > ddd eee",
}, { width = 16, markers = TEXT })

check("different markers are different paragraphs", {
    "> quoted text",
    "unquoted text",
}, {
    "> quoted text",
    "unquoted text",
}, { width = 80, markers = TEXT })

check("C-style block comment body", {
    "/**",
    " * aaa bbb ccc ddd eee fff ggg",
    " * hhh",
    " */",
}, {
    "/**",
    " * aaa bbb ccc",
    " * ddd eee fff",
    " * ggg hhh",
    " */",
}, { width = 16, row = 1, markers = C_STYLE })

check("list item with hanging indent", {
    "- aaa bbb ccc ddd eee fff",
    "  ggg",
    "- second item",
}, {
    "- aaa bbb ccc",
    "  ddd eee fff",
    "  ggg",
    "- second item",
}, { width = 14, row = 1, markers = TEXT, prose = true })

check("numbered list item", {
    "10. aaa bbb ccc ddd",
}, {
    "10. aaa bbb",
    "    ccc ddd",
}, { width = 12, markers = TEXT, prose = true })

check("list item inside a comment", {
    "# - aaa bbb ccc ddd",
}, {
    "# - aaa bbb",
    "#   ccc ddd",
}, { width = 12 })

check("text right after a list item is part of it only if indented", {
    "* item",
    "not part of it",
}, {
    "* item",
    "not part of it",
}, { width = 80, markers = TEXT, prose = true })

check("markdown heading and fence are left alone", {
    "# A heading",
    "some",
    "text",
    "```",
}, {
    "# A heading",
    "some text",
    "```",
}, { width = 80, row = 1, markers = TEXT, prose = true })

check("horizontal rule in a comment is left alone", {
    "# ----------",
    "# aaa",
    "# bbb",
}, {
    "# ----------",
    "# aaa bbb",
}, { width = 80, row = 2 })

check("words longer than the width get their own line", {
    "a https://example.com/a/very/long/url b",
}, {
    "a",
    "https://example.com/a/very/long/url",
    "b",
}, { width = 10 })

check("multi-byte characters count as one column", {
    "éééé ààà ççç",
}, {
    "éééé ààà",
    "ççç",
}, { width = 8 })

check("trailing whitespace and extra spaces are normalized", {
    "aaa    bbb   ",
    "ccc ",
}, {
    "aaa bbb ccc",
}, { width = 80 })

check("selection justifies every paragraph in range only", {
    "outside",
    "aaa bbb",
    "ccc",
    "",
    "- ddd",
    "  eee",
    "outside",
}, {
    "outside",
    "aaa bbb ccc",
    "",
    "- ddd eee",
    "outside",
}, { width = 80, row = 1, to = 5, prose = true, markers = TEXT })

check("selection starting mid-paragraph starts a paragraph there", {
    "aaa",
    "bbb",
    "ccc",
}, {
    "aaa",
    "bbb ccc",
}, { width = 80, row = 1, to = 2 })

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
