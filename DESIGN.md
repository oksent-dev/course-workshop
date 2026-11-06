# Reading Room

Course Workshop is a place to sit with a lesson. Give the reading column the most space, keep the course outline nearby, and place an exercise beside the idea it explains. Warm paper, sage accents, and rounded panels tie the library, reader, and lesson conversation together.

The library and site navigation use `reading-room`, the default light daisyUI theme. Edit its semantic colors, control sizes, and corner radii in the [Tailwind entry point](app/assets/tailwind/application.css). That file also defines the Tailwind font families and the muted ink text utility.

## Color and surfaces

| Role | Value | Use |
| --- | --- | --- |
| Paper · `base-100` | `#FBF8EF` | Reading surface and page background |
| Canvas · `base-200` | `#EFEFE3` | Course outline and secondary surfaces |
| Rule · `base-300` | `#D6D8C8` | Quiet dividers between groups |
| Ink · `base-content` | `#303B32` | Titles, lesson prose, and form labels |
| Muted ink | `#566350` | Captions, metadata, and secondary text |
| Sage · `primary` | `#435F48` | Main action, current lesson, links, and focus rings |
| On sage · `primary-content` | `#FFFDF7` | Text and icons on a filled primary action |
| Sage wash · `secondary` | `#E5EBDD` | Exercise and worked-example panels, with ink text |

Keep most of the viewport paper-colored. Use the wash to group things the learner can try. Reserve solid sage for the action or selection that matters most. A fine rule can separate paragraphs or panels. An input that needs a visible boundary uses a stronger stroke. Pair error messages with a text label, completion with a check and a label, and links in prose with an underline.

## Type, space, and shape

| Element | Typeface | Size and rhythm |
| --- | --- | --- |
| Lesson title | Spectral Medium, Georgia, serif | 32–48 px, line height 1.15 |
| Section heading | Spectral Semibold, Georgia, serif | 22–28 px, line height 1.3 |
| Lesson prose | Spectral Regular, Georgia, serif | 18–20 px, line height 1.6 |
| Navigation, forms, chat, and actions | DM Sans, Segoe UI, sans-serif | 15–16 px, line height 1.5 |
| Metadata and captions | DM Sans, Segoe UI, sans-serif | 13–14 px, line height 1.5 |
| Code and numerical output | System monospace | 15–16 px, line height 1.5 |

Use relative units and support browser zoom. Keep paragraphs around 60–70 characters wide. Ship Polish glyphs with any bundled font and keep the fallback usable while fonts load. Use 4, 8, 12, 16, 24, 32, and 48 px as the spacing scale. Put more space between sections than between a heading and its paragraph. Use a 10 px radius on controls and about 16 px on panels. Group ordinary prose with headings and whitespace. Reserve shadows for layers such as an open dialog.

Rails serves the [font files](app/assets/fonts) from the same origin as the application. The [font declarations](app/assets/tailwind/fonts.css) use Latin and Latin Extended subsets with `font-display: swap`. Spectral includes the regular, medium, and semibold weights. DM Sans uses a variable weight file per subset. The WOFF2 files come from Fontsource's `@fontsource/spectral` and `@fontsource-variable/dm-sans`, both version 5.3.0. Their licenses are included for [Spectral](docs/licenses/spectral.txt) and [DM Sans](docs/licenses/dm-sans.txt).

## Screens and components

| Surface | Composition and behavior |
| --- | --- |
| Library | Group courses by category. A course card shows its title, a short description, progress in words, and a link to start or resume. An empty library explains what will appear there. |
| Lesson reader | Put a compact course outline to the left of the reading column when both fit. Show the current lesson by name and position. On small screens, move the outline above the article behind a labeled disclosure. Keep the heading, prose, and exercises in reading order. |
| Worked example or exercise | Use a sage-wash panel with a short prompt, the material or control, and its result. Keep figures, equations, and code close to the text that introduces them. Label chart units and offer the values or a text summary. Give images meaningful alternative text and a caption when it adds context. |
| Progress | Pair a progress bar with a count such as “2 of 5 lessons completed.” Distinguish the open lesson from a completed one. Use a verb such as “Mark complete” for a change of state. |
| Lesson conversation | Keep the lesson heading and reading position available when opening or closing chat. On a narrow screen, open it on demand. Give the question field a visible label and distinguish sending, waiting, cancellation, and failure. |

Build with semantic HTML in ERB. Use daisyUI primitives such as `btn`, `card`, `input`, and `progress`. Define colors and radii once in the theme and use semantic utilities in templates. Prefer a Rails partial for repeated domain markup such as a course card. Use Stimulus for local behavior such as updating an exercise result. Keep interface strings in the locale dictionaries and preserve the content language when the reader changes the interface language.

Lesson Markdown uses the scoped `.lesson-content` rules in the Tailwind entry point. Section headings, lists, quotations, and code follow the same reading rhythm. Keep code and table overflow inside a keyboard-accessible `.lesson-scroll` region. Render a standalone image as a figure with its caption; a failed image keeps a readable description. See [lesson content](docs/lesson-content.md) for the supported source format.

Display formulas and flow diagrams in quiet, bordered canvas panels. Preserve their natural size and let the panel scroll when necessary. Mermaid uses the same paper, sage, ink, and UI typeface as the reader; node corners are rounded. Keep a visible text description beneath a diagram. Practice exercises use the sage wash, with a clear prompt and a keyboard-accessible answer disclosure. Validation and rendering failures show a text notice and escaped source without interrupting nearby material. Source formats and limits are documented in [learning blocks](docs/learning-blocks.md).

## Review a screen

- Check the primary action and heading at a narrow phone width (320 px) and a desktop width. At 200% zoom, text and controls must remain reachable. Confine overflow from a wide code sample or table to that element.
- Use the screen with a keyboard. Focus must be visible on paper, wash, and filled controls. Keep focus order aligned with reading order and restore it to the trigger when a dialog closes.
- Aim for at least 4.5:1 contrast for ordinary text and 3:1 for meaningful control boundaries and focus indicators. Check the actual foreground and background of hover, focus, selected, and error states.
- Aim for a touch target of at least 44 × 44 px for standalone controls. Keep progress and feedback understandable with motion reduced and color removed.
- Check Polish and English with a long course title. For a data-backed screen, review the populated, empty, and failure states. For a slow operation, check what the learner sees while waiting and how to retry.
