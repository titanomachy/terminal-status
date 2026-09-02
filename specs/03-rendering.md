# Pure rendering specification

All renderers return strings and perform no I/O. They receive one `now` value
and MUST use it consistently for every animated frame and metric in that call.

## Public presentation types (`terminal_status/themes`)

```nim
type
  StatusCharacters* = enum
    statusUnicode
    statusAscii

  StatusMarkers* = object
    pending*: string
    running*: string
    succeeded*: string
    failed*: string
    cancelled*: string
    barStart*: string
    barEnd*: string
    barComplete*: string
    barRemaining*: string
    detailSeparator*: string

  StatusTheme* = object
    spinnerStyle*: TerminalStyle
    runningStyle*: TerminalStyle
    successStyle*: TerminalStyle
    failureStyle*: TerminalStyle
    cancelledStyle*: TerminalStyle
    pendingStyle*: TerminalStyle
    labelStyle*: TerminalStyle
    detailStyle*: TerminalStyle
    completeBarStyle*: TerminalStyle
    remainingBarStyle*: TerminalStyle
    metadataStyle*: TerminalStyle

proc unicodeStatusMarkers*(): StatusMarkers
proc asciiStatusMarkers*(): StatusMarkers
proc defaultStatusTheme*(): StatusTheme
```

Marker values:

| Field | Unicode | ASCII |
| --- | --- | --- |
| pending | `○` | `o` |
| running | `●` | `>` |
| succeeded | `✓` | `+` |
| failed | `✗` | `x` |
| cancelled | `–` | `-` |
| barStart | `[` | `[` |
| barEnd | `]` | `]` |
| barComplete | `█` | `#` |
| barRemaining | `░` | `-` |
| detailSeparator | ` — ` | ` - ` |

Every marker except the detail separator MUST occupy exactly one terminal cell.
Preset constructor tests enforce that invariant.

The default theme is composed from TerminalStyle values:

- spinner and running: cyan;
- success and complete bar: green;
- failure: red;
- cancellation: yellow;
- pending, detail, remaining bar, and metadata: bright black/dim;
- label: the default/no-op style.

Use `initTerminalStyle` and exported TerminalStyle colors/attributes. Do not
embed raw SGR literals in theme definitions.

## Render options

```nim
type RenderOptions* = object
  width*: int
  barWidth*: int
  characters*: StatusCharacters
  useColor*: bool
  showCount*: bool
  showElapsed*: bool
  showRate*: bool
  showEta*: bool
  indeterminateIntervalMs*: int
  theme*: StatusTheme

proc defaultRenderOptions*(): RenderOptions
```

Defaults:

| Option | Default | Meaning |
| --- | --- | --- |
| width | `0` | Unbounded; renderer never queries the terminal. |
| barWidth | `20` | Desired inner width, excluding `[` and `]`. |
| characters | `statusUnicode` | Unicode markers and built-in spinner frames. |
| useColor | `true` | Apply theme styles and retain safe caller SGR/OSC-8. |
| showCount | `true` | Show determinate `completed/total` and optional unit. |
| showElapsed | `false` | Show an `elapsed` field when available. |
| showRate | `true` | Show average determinate rate when calculable. |
| showEta | `true` | Show running determinate ETA when calculable. |
| indeterminateIntervalMs | `100` | Time per pulse movement. |
| theme | `defaultStatusTheme()` | Default semantic colors. |

Every render call validates options before rendering:

- `width` MUST be zero or positive;
- `barWidth` MUST be positive;
- `indeterminateIntervalMs` MUST be positive;
- invalid options raise `ValueError` even when a particular component would not
  use the invalid field.

## Public renderer API (`terminal_status/rendering`)

```nim
proc render*(spinner: Spinner,
             options = defaultRenderOptions(),
             now = getMonoTime()): string

proc render*(bar: ProgressBar,
             options = defaultRenderOptions(),
             now = getMonoTime()): string

proc render*(multi: MultiProgress,
             options = defaultRenderOptions(),
             now = getMonoTime()): string

proc render*(tracker: StepTracker,
             options = defaultRenderOptions(),
             now = getMonoTime()): string
```

If default object values are not legal in the selected Nim compiler context,
provide overloads that construct defaults. Do not require callers to pass
options or time for ordinary use.

Common return rules:

- one component row contains no `\r` or `\n`;
- multi-progress and step-trackers separate rows with `\n`;
- no renderer appends a final newline;
- an empty `MultiProgress` renders `""`;
- `width == 0` does not pad or truncate;
- positive width is a maximum, not a padding target; every logical row has
  `displayWidth(row) <= width`;
- `useColor == false` returns no ANSI tokens, including tokens originally
  supplied inside labels/details;
- renderers never mutate or terminate their model.

## Safe text normalization

Before styling or measuring a label, title, detail, or unit, normalize it:

1. Iterate `tokenizeAnsi(value)`.
2. For `atkText`, decode text safely and replace CR, LF, CRLF, and tab runs with
   one ordinary space. Remove remaining C0/C1 control code points. Preserve all
   other valid Unicode text. A malformed UTF-8 sequence MAY be replaced with
   U+FFFD but MUST NOT crash or be treated as terminal control.
3. Retain an `atkCsi` token only when its final byte is `m` (SGR).
4. Retain an `atkOsc` token only when it is a well-formed OSC-8 open or close
   hyperlink token (`ESC ] 8 ; ... ; ... BEL/ST`).
5. Drop every `atkEscape`, non-SGR CSI, and non-OSC-8 OSC token.
6. Collapse whitespace introduced at a line/control boundary, but do not trim
   intentional ordinary spaces from an otherwise valid label.

Use `displayWidth`, `truncateAnsi`, and other TerminalStyle functions after
normalization. Do not slice UTF-8 by bytes. ANSI-aware truncation MUST leave SGR
and hyperlinks closed.

## Styling order

1. Normalize user text.
2. Select Unicode/ASCII glyphs.
3. Construct semantic segments (marker, label, bar, metadata).
4. Apply each `StatusTheme` style with `enabled = options.useColor`.
5. Join segments.
6. Apply width reduction and ANSI-aware truncation.

When `useColor` is false, TerminalStyle's disabled styling path is responsible
for removing existing ANSI. Do not add a second regex-based ANSI stripper.

## Numeric formatting

### Percentage

For determinate progress:

```text
percent = floor(completed * 100 / total)
```

Compute without overflowing `int64` (use floating point or divide before
multiplication). Clamp defensively to `0..100`. Format as a right-aligned
three-character integer followed by `%`: `"  0%"`, `"  7%"`, `" 50%"`,
`"100%"`.

### Count

The count token is `completed/total`. Append one space and the normalized unit
only when unit is non-empty:

```text
25/100
25/100 MB
```

Indeterminate progress has neither count nor percentage.

### Rate

Format the average rate with exactly one digit after the decimal point using a
locale-independent decimal point. Without a unit: `12.5/s`. With a unit:
`12.5 MB/s`. Suppress the token when the model returns no finite positive rate.

### Durations

Elapsed time rounds down to whole seconds. Positive ETA rounds up to the next
whole second. Use these forms without days:

| Range | Form | Example |
| --- | --- | --- |
| 0–59 seconds | `<s>s` | `9s` |
| 60–3599 seconds | `<m>m <ss>s` | `2m 05s` |
| 3600+ seconds | `<h>h <mm>m <ss>s` | `3h 02m 09s` |

Elapsed metadata is `elapsed <duration>`. ETA metadata is `ETA <duration>`.
All formatting is locale independent.

## Spinner rendering

Running form:

```text
<animated-frame> <label>
```

Terminal form:

```text
<state-marker> <label>
```

Use the spinner theme for an animated frame and the matching terminal state
theme for the terminal marker. Use ASCII frames when `characters ==
statusAscii`. The supplied `now` selects the running frame; a terminal spinner
uses its terminal marker rather than its frozen animation frame.

Uncolored examples:

```text
⠋ Fetching packages
✓ Fetching packages
x Fetching packages       # ASCII failed state
```

For positive `width`, reserve marker plus one separating cell first and give
the remaining cells to the label. Truncate with `…` in Unicode mode or `...`
in ASCII mode when the suffix fits. At extremely narrow widths, use
TerminalStyle truncation on the complete row; returning `""` for `width == 0`
is forbidden because zero means unbounded, while a positive width smaller than
one complete glyph MAY produce an empty row only if no whole grapheme fits.

## Determinate progress rendering

Base segment order:

```text
<marker> <label> [<bar>] <percent> <count> <rate> <eta> <elapsed>
```

Only enabled and available metadata appears. Exactly one space separates
non-empty segments. The bar's inner content contains exactly `barWidth`
terminal cells before responsive reduction.

Filled cells:

```text
filled = floor(completed * innerWidth / total)
```

Avoid integer overflow and clamp to `0..innerWidth`. A succeeded determinate
bar is completely filled. Other terminal states retain the frozen completion
fraction. Complete and remaining portions receive their respective theme
styles.

The marker is `running` while the task runs and the matching terminal marker
afterward. A determinate task never has pending state through the public API,
but a defensive renderer MAY render a pending marker if handed such an internal
snapshot.

Uncolored, unbounded example with default metadata and 10-cell requested bar:

```text
● Downloading [#####-----]  50% 50/100 MB 25.0 MB/s ETA 2s
```

The actual default bar uses Unicode glyphs and 20 inner cells. The example uses
ASCII options and an overridden width solely to make the structure obvious.

ETA is suppressed after any terminal transition. Rate and count remain
available in terminal rows. Elapsed appears only when `showElapsed` is true.

## Indeterminate progress rendering

Running form:

```text
<running-marker> <label> [<moving-pulse>] <elapsed>
```

There is no percentage, count, rate, or ETA even if their flags are true.

For an inner width `N`:

- pulse width is `max(1, min(3, N))`;
- `travel = N - pulseWidth`;
- if `travel == 0`, position is zero;
- otherwise `tick = floor(elapsedMs / indeterminateIntervalMs)`, cycle length
  is `2 * travel`, and the position bounces from zero to `travel` and back;
- pulse cells use complete-bar characters/style; other cells use remaining-bar
  characters/style.

A succeeded indeterminate bar renders fully complete. Failed or cancelled bars
freeze the pulse at `finishedAt` and use the respective state marker.

## Multi-progress rendering

Render each task with exactly the single-progress algorithm and join rows in
insertion order with `\n`. Use the one top-level `now` for every task. Width
reduction applies independently per row. No blank lines or aggregate summary
are added. An empty collection returns an empty string.

## Step-tracker rendering

If title is non-empty, render its normalized/styled value as the first row.
Then render exactly one row per step:

```text
<marker> <label><detail-separator><detail>
```

Omit the separator when detail is empty. Pending and terminal steps use their
semantic marker. A running step uses the `pulseSpinner()` frame selected from
`now - step.startedAt`, so a step tracker provides a visible loader without
mutating its state. Use its ASCII frames in ASCII mode.

Do not indent step rows in `0.1.x`. A title is styled with `labelStyle`; labels
use `labelStyle`; details use `detailStyle`; markers use the matching semantic
style.

For positive width, reserve marker and separator first. The label has priority
over detail: truncate/drop detail before truncating the label. Apply the final
whole-line bound defensively.

## Responsive width reduction

For each progress row with a positive `width`, use this deterministic order:

1. Construct all requested/available metadata.
2. Treat marker, one marker/label space, bar delimiters, percentage, and the
   spaces between present segments as fixed. Treat label as elastic with a
   desired width equal to its full display width and minimum one cell.
3. If fixed segments plus a one-cell label do not fit, remove metadata in this
   order: elapsed, rate, ETA, count. Percentage is not part of `count` and is
   retained at this stage.
4. If it still does not fit, shrink the inner bar one cell at a time to a
   minimum of four cells.
5. If it still does not fit, remove percentage.
6. If it still does not fit, remove the entire bar including delimiters.
7. Allocate all remaining cells to the label and truncate it with the
   mode-appropriate suffix. If a suffix does not fit, `truncateAnsi` returns
   only whole suffix/content graphemes that do fit.
8. As a final defensive step, ANSI-truncate the complete row to `width`.

When the fixed pieces already fit, keep the requested inner bar width and
truncate only an overlong label to the available cell budget. Optional fields
disabled by the caller are absent from the start and do not affect the order.

This reduction algorithm MUST NOT pad rows, split a wide grapheme, emit a
negative width, or throw merely because the terminal is narrow.

## Required renderer invariants

For every model state, option combination, and positive width:

- `displayWidth(line) <= width` for every returned logical line;
- stripping ANSI does not change visible characters other than removing
  styling/hyperlink controls;
- rendering twice with the same model/options/time returns byte-identical text;
- rendering does not mutate timestamps or state;
- no returned line contains caller-supplied cursor, erase, title, clipboard, or
  device-control sequences;
- every safe style/hyperlink open in a truncated row is closed before row end.

