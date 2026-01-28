# VoiceFox Markdown Voice Commands

Complete reference for voice-to-markdown conversion commands.

## Headings

| Voice Command | Output |
|---------------|--------|
| `h1 text` | `# text` |
| `h2 text` | `## text` |
| `h3 text` | `### text` |
| `h4 text` | `#### text` |
| `h5 text` | `##### text` |
| `h6 text` | `###### text` |
| `heading 1 text` | `# text` |
| `heading 2 text` | `## text` |
| `heading 3 text` | `### text` |
| `heading 4 text` | `#### text` |
| `heading 5 text` | `##### text` |
| `heading 6 text` | `###### text` |

---

## Inline Formatting

All inline formatting supports multiple trigger variants:
- `on/off` (e.g., `bold on`, `bold off`)
- `start/end` (e.g., `bold start`, `bold end`)
- `start X/end X` (e.g., `start bold`, `end bold`)

| Voice Command | Output | Notes |
|---------------|--------|-------|
| `bold on text bold off` | `**text**` | Strong emphasis |
| `italic on text italic off` | `*text*` | Emphasis |
| `bold italic on text bold italic off` | `***text***` | Combined strong + emphasis |
| `code on text code off` | `` `text` `` | Inline code |
| `strike on text strike off` | `~~text~~` | Strikethrough |
| `strikethrough on text strikethrough off` | `~~text~~` | Strikethrough (alternate) |
| `highlight on text highlight off` | `==text==` | Highlight (extended markdown) |
| `mark on text mark off` | `==text==` | Highlight (alternate) |
| `subscript on text subscript off` | `~text~` | Subscript (extended markdown) |
| `sub on text sub off` | `~text~` | Subscript (short form) |
| `superscript on text superscript off` | `^text^` | Superscript (extended markdown) |
| `super on text super off` | `^text^` | Superscript (short form) |

### Example Usage

Say: "This is bold on important bold off information"
Output: `This is **important** information`

Say: "Use code on const x code off for variables"
Output: ``Use `const x` for variables``

---

## Block Elements

| Voice Command | Output | Notes |
|---------------|--------|-------|
| `bullet text` | `- text` | Unordered list item |
| `list item text` | `- text` | Unordered list item (alternate) |
| `numbered text` | `1. text` | Ordered list item |
| `number text` | `1. text` | Ordered list item (alternate) |
| `quote text` | `> text` | Blockquote |
| `block quote text` | `> text` | Blockquote (alternate) |
| `checkbox text` | `- [ ] text` | Unchecked task |
| `todo text` | `- [ ] text` | Unchecked task (alternate) |
| `checked text` | `- [x] text` | Checked task |
| `horizontal rule` | `---` | Horizontal rule |
| `divider` | `---` | Horizontal rule (alternate) |

### Example Usage

Say: "bullet first item"
Output: `- first item`

Say: "checkbox remember to call mom"
Output: `- [ ] remember to call mom`

---

## Code Blocks (Fenced)

| Voice Command | Output |
|---------------|--------|
| `code block python` | `` ```python `` |
| `code block javascript` | `` ```javascript `` |
| `code block swift` | `` ```swift `` |
| `codeblock rust` | `` ```rust `` |
| `end code block` | `` ``` `` |
| `end codeblock` | `` ``` `` |

### Example Usage

Say: "code block python"
Say: "def hello world"
Say: "end code block"

Output:
```python
def hello world
```

---

## Links

Links use a three-part structure: open, separator, close.

| Voice Command | Output |
|---------------|--------|
| `open link` or `link text` | `[` |
| `link to` or `link url` | `](` |
| `end link` or `close link` | `)` |

### Example Usage

Say: "link text Click here link to https://example.com end link"
Output: `[Click here](https://example.com)`

Say: "open link my website link url https://mysite.com close link"
Output: `[my website](https://mysite.com)`

---

## Images

Images use a similar three-part structure to links.

| Voice Command | Output |
|---------------|--------|
| `open image` or `image alt` | `![` |
| `image source` or `image url` | `](` |
| `end image` or `close image` | `)` |

### Example Usage

Say: "image alt A cute cat image source https://example.com/cat.jpg end image"
Output: `![A cute cat](https://example.com/cat.jpg)`

---

## Line Breaks & Paragraphs

| Voice Command | Output | Notes |
|---------------|--------|-------|
| `new line` | Two spaces + newline | Soft line break |
| `line break` | Two spaces + newline | Soft line break (alternate) |
| `new paragraph` | Double newline | Paragraph break |

---

## Footnotes

| Voice Command | Output |
|---------------|--------|
| `footnote 1 end footnote` | `[^1]` |
| `footnote note end footnote` | `[^note]` |

---

## Additional Symbol Conversions

These work in all modes, not just markdown:

| Voice Command | Output |
|---------------|--------|
| `hash` | `#` |
| `hash hash` | `##` |
| `dash` | `-` |
| `dash dash` | `--` |
| `dot` | `.` |
| `colon` | `:` |
| `semicolon` | `;` |
| `open paren` | `(` |
| `close paren` | `)` |
| `open bracket` | `[` |
| `close bracket` | `]` |
| `greater than` | `>` |
| `less than` | `<` |

---

## Mode Activation

Say these commands alone to activate markdown mode:

| Voice Command | Effect |
|---------------|--------|
| `markdown` | Activates Markdown mode |
| `md` | Activates Markdown mode |
| `plain` | Returns to plain text mode |
| `plain text` | Returns to plain text mode |
| `clear mode` | Returns to plain text mode |
| `normal` | Returns to plain text mode |

The current mode is displayed in the overlay badge.

---

## Tips

1. **Punctuation tolerance**: Commands work even if followed by punctuation (period, comma)
2. **Case insensitive**: All commands work regardless of capitalization
3. **Natural flow**: Say commands as part of your sentence - "This is bold on important bold off info"
4. **Multiple formats**: Combine formats - "This is bold on italic on very important italic off bold off"
