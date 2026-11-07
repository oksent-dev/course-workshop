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
| Library | Use a grid of cover cards: one column on phones, two from 640 px, three from 1024 px. Each card shows a 16:9 cover, category badge, title, three-line description, content language, progress, and a start/resume action. Place category filters with counts above the grid. An empty library explains what will appear there. |
| Lesson reader | Put a compact course outline to the left of the reading column when both fit. Show the current lesson by name and position. On small screens, move the outline above the article behind a labeled disclosure. Keep the heading, prose, and exercises in reading order. |
| Worked example or exercise | Use a sage-wash panel with a short prompt, the material or control, and its result. Keep figures, equations, and code close to the text that introduces them. Label chart units and offer the values or a text summary. Give images meaningful alternative text and a caption when it adds context. |
| Progress | Pair a progress bar with a count such as “2 of 5 lessons completed.” Distinguish the open lesson from a completed one. Use a verb such as “Mark complete” for a change of state. |
| Lesson conversation | Open a floating, non-modal panel from a 64 px chat button at the bottom right, leaving space around its 32 px icon. Keep the lesson available behind it and preserve reading position. Show the current lesson title and a labeled close button. Fit the visible viewport on phones. Give the question field a visible label and distinguish sending, waiting, cancellation, and failure. |

Build with semantic HTML in ERB. Use daisyUI primitives such as `btn`, `card`, `input`, and `progress`. Define colors and radii once in the theme and use semantic utilities in templates. Prefer a Rails partial for repeated domain markup such as a course card. Use Stimulus for local behavior such as updating an exercise result. Keep interface strings in the locale dictionaries and preserve the content language when the reader changes the interface language.

Lesson Markdown uses the scoped `.lesson-content` rules in the Tailwind entry point. Section headings, lists, quotations, and code follow the same reading rhythm. Keep code and table overflow inside a keyboard-accessible `.lesson-scroll` region. Render a standalone image as a figure with its caption; a failed image keeps a readable description. See [lesson content](docs/lesson-content.md) for the supported source format.

Code fences use Rouge tokens with the palette in [code.css](app/assets/tailwind/code.css): plum keywords, terracotta strings, ochre numbers, blue function/type names, teal variables and muted-ink comments. All token colors have at least 5.5:1 contrast on the canvas background. Keep the original spacing and text, use semibold keywords and italic comments sparingly, and retain neutral inline code. Do not use color to imply that a code example has been checked or executed.

Display formulas and flow diagrams in quiet, bordered canvas panels. Preserve their natural size and let the panel scroll when necessary. Mermaid uses the same paper, sage, ink, and UI typeface as the reader; node corners are rounded. Keep a visible text description beneath a diagram. Practice exercises use the sage wash, with a clear prompt and a keyboard-accessible answer disclosure. Validation and rendering failures show a text notice and escaped source without interrupting nearby material. Source formats and limits are documented in [learning blocks](docs/learning-blocks.md).

Progress uses a native daisyUI progress bar paired with an explicit count. Course outlines keep the current-page treatment and add a check with a translated completion label independently. Put the completion action after the lesson material in a sage-wash panel, with a reversible action after completion. The library and course outline offer start, resume, or review according to the current state; reviewing never clears progress.

The chat panel uses paper for the transcript and composer, canvas for its heading, and a sage wash for the learner's messages and pending quote. Reserve its soft shadow for this floating layer. Escape and the close button return focus to the launcher; opening focuses the question without scrolling the lesson. Keep long transcripts and quotes scrollable by keyboard. New messages must not pull someone away from older conversation content they are reading.

The first chat opening shows a labeled skeleton while the conversation loads, then gently reveals the empty-state guidance or saved history. Keep loaded content visible on later refreshes. A failed initial request replaces the loading indicator with the error and retry action; retrying restores it. Reduced motion stops the skeleton animation as well as the content entrance.

An empty question keeps the send button disabled. Once the conversation has loaded, refreshing its history must not make a ready question flicker between enabled and disabled. Disable sending for an actual submission or pending reply, and preserve the question while a refresh finishes.

Place an expand/restore icon immediately before the chat's close button. The larger mode may cover the lesson: grow the same panel to at most 64 rem wide and the available viewport height, retaining a 12 px outer margin. Keep message and composer text within 75 characters. Animate width and height over 240 ms, with no animation when reduced motion is requested. The toggle keeps keyboard focus, the current conversation, and unsent content. Remember its size while closing and reopening the current lesson's panel; a new lesson starts compact.

A selection action appears beside text selected within the lesson body after the pointer is released, without interrupting a drag. It opens chat with a removable quote above the question. A selection never submits a question automatically. Display the full quoted text in the saved exchange and preserve whitespace; do not render it as HTML. Keep the action within the viewport and offer Alt+Enter while it is visible. Closing chat retains its unsent draft on the current page; changing lessons starts with that lesson's conversation.

Draft previews reuse the reader's typography, material renderer, and nearby outline. Label the page as a draft and place a clear approval panel above its lessons. Keep the regular library for approved courses. Previewing material does not display completion controls or count toward learning progress. A stale approval presents an inline text error and the current draft for another review.

Course creation uses a labeled topic field and content language in one quiet panel. The model chooses the lesson count. Show the proposed course title, category, description and ordered plan for explicit approval before writing lessons. Explain the model's use of the topic and draft, including image allowance usage, before submission.

The progress screen distinguishes planning, writing, completeness checks and the cover. Show the current lesson, last recorded activity and links to saved lessons. A lesson illustration is a visible substep of writing. Display saved lessons against the approved count only once a plan is approved; do not invent a percentage or ETA for planning, research or images. Keep keyboard focus stable during polling, offer cancel/resume, and provide manual refresh after a connection failure. Explain that users can return later while the local app and computer stay running. A completed course still requires draft review and approval.

Every newly generated lesson needs a visual that explains its subject: a table, a displayed formula, a diagram or an attached image. Place it in the main learning material and explain its meaning. Avoid decorative filler and invented data. A generated illustration includes meaningful alternative text and must never be presented as documentary evidence. Image failure retains the written material and offers resume of the image step.

Show cover creation as a separate section beneath the saved lesson plan. Keep completed lessons available while the image is pending. Use a concise waiting message, then a 16:9 preview; a failed image offers a clearly labeled cover-only retry. Explain image allowance usage on the creation form. Cover failure must not make a completed course appear to have lost its lessons.

Course covers use a consistent, quiet editorial illustration style: warm paper, sage accents, soft light, and no embedded titles or logos. Treat them as decorative next to the visible title. Reserve the image's aspect ratio before loading; reuse the bookshelf illustration if a cover is absent or fails. Keep every card within one column, even when there is only one course. Titles remain complete; descriptions may be clamped because the course outline exposes the full text.

Category filters are wrapping links with at least 44 px touch targets, visible selected styling, and `aria-current`. Counts include published courses only. Preserve the selected category in the URL, browser history, and language switch. Category names are catalog content; changing the interface language does not translate them.

## Motion

Use a short fade-up to introduce a new screen, not to pace the learner's reading. Page headings, library filters and result counts, course cards, outlines, lesson articles, and forms enter once when rendered, including Turbo navigation. Animate the lesson article as one surface; scrolling does not hide or reveal individual paragraphs. The site header stays steady. Never transform an ancestor of the fixed chat widget.

| Interaction | Duration | Vertical movement |
| --- | --- | --- |
| Screen content | 520 ms | 16 px upward |
| Adjacent cards and panels | Same entrance, with 60–180 ms stagger | 16 px upward |
| Open chat or add a message | 220 ms | 10 px for the panel, 6 px for messages |
| Close chat | 140 ms | 6 px downward |
| Attach a quote / show selection action | 180 / 160 ms | 6 px upward |
| Reveal an exercise answer | 240 ms | 6 px upward |

Use `cubic-bezier(0.25, 0.1, 0.25, 1)` for entrances. CSS rules live in [motion.css](app/assets/tailwind/motion.css); transient chat effects use the browser's animation API through [motion.js](app/javascript/motion.js). Animate opacity and transforms without changing layout dimensions. Chat resizing retains its separate width/height transition.

Keep controls usable throughout. Keyboard focus permanently finishes an entering region for its current DOM lifetime; moving focus between fields or opening native selects must never restart it. All content is visible after the entrance, even without JavaScript. Reduced motion disables these effects. Do not replay existing chat messages or generation status panels on every poll; animate only newly added messages or changed reply states while the reader is following the latest message.

## Review a screen

- Check the primary action and heading at a narrow phone width (320 px) and a desktop width. At 200% zoom, text and controls must remain reachable. Confine overflow from a wide code sample or table to that element.
- Use the screen with a keyboard. Focus must be visible on paper, wash, and filled controls. Keep focus order aligned with reading order and restore it to the trigger when a dialog closes.
- Aim for at least 4.5:1 contrast for ordinary text and 3:1 for meaningful control boundaries and focus indicators. Check the actual foreground and background of hover, focus, selected, and error states.
- Aim for a touch target of at least 44 × 44 px for standalone controls. Keep progress and feedback understandable with motion reduced and color removed.
- Check Polish and English with a long course title. For a data-backed screen, review the populated, empty, and failure states. For a slow operation, check what the learner sees while waiting and how to retry.
