# Justify plugin

The justify plugin rewraps the current paragraph so that its lines are as
long as possible without going past a given width, like `^J` (Justify) in
nano.

Press `Alt-j`, or run the command:

```
> justify
```

To use a different width just this once, give it as an argument:

```
> justify 72
```

After justifying, the cursor moves to the line after the paragraph, so that
pressing `Alt-j` repeatedly justifies the following paragraphs one by one.
Undo restores the paragraph as it was.

## What counts as a paragraph

A paragraph is a run of consecutive lines which start with the same prefix.
It ends at an empty line, or at a line whose prefix differs. The prefix is
kept on every line of the justified paragraph, and is made of:

* indentation,
* comment markers: `//`, `#`, `--`, `;`, `%`, and also `/*` and `*` in
  languages with C-style block comments,
* `>` quote markers, as in emails and Markdown,
* a list bullet (`-`, `*`, `+`, `•`, `1.`, `1)`), which starts a new
  paragraph. Following lines are indented to line up with the text after the
  bullet.

In Markdown, reStructuredText and AsciiDoc files, only `>` is a marker, and
headings (`#`), code fences, and table rows are left alone. Lines made only of
`-`, `=`, `*`, `_`, `~`, `#` or `+` (horizontal rules) are always left alone.

If the cursor is not in a paragraph, the next paragraph is justified.

If there is a selection, every paragraph in the selected lines is justified
instead.

## Options

* `justify.width`: the maximum line width. When it is `0`, the value of
  `colorcolumn` is used, or 80 if that is not set either.

    default value: `0`

## Key binding

The plugin binds `Alt-j` if it is not already bound. To use another key, add
something like this to `bindings.json`:

```json
"Alt-q": "lua:justify.justify"
```
