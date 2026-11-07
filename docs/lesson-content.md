# Lesson Markdown and images

Lessons store Markdown source in PostgreSQL. The reader renders it with Commonmarker, resolves image references against the current lesson, and sanitizes the resulting HTML. Existing plain paragraphs remain valid Markdown.

New AI-generated lessons must include a table, display formula, supported diagram or local image in their main material. A requested AI illustration is generated in a separate resumable step, attached with meaningful alternative text and inserted as `image:generated-illustration`. It uses the same byte, format and pixel checks as imported images. Existing lessons and manual imports are not rewritten by this rule. See [course generation](course-generation.md) for the visual requirement and recovery flow.

## Supported content

Use `##` for a section and `###` for a subsection. A source `#` heading is rendered as `h2` so the lesson title remains the page's only `h1`.

The reader supports paragraphs, emphasis, strong text, strikethrough, ordered and unordered lists, blockquotes, horizontal rules, inline code, fenced code blocks, links, and tables. A single newline continues the same paragraph. Separate paragraphs with a blank line.

````markdown
## Measure consistently

Record **all five days**, including delays.

- Start at the front door.
- Stop at the library entrance.

> Keep the original observations.

```ruby
times = [8, 4, 12, 6, 10]
puts times.sum.fdiv(times.length)
```

| Day | Minutes |
| --- | --- |
| Monday | 8 |

[Reference](https://example.com/guide)
````

Ordinary code is displayed as text and never executed. Code blocks and wide tables scroll inside labeled regions that can receive keyboard focus. The dedicated `math`, `mermaid`, and `exercise` fences render validated learning components; see [learning blocks](learning-blocks.md) for their formats and limits.

### Syntax highlighting

Specify the language after the opening fence, such as `ruby`, `sql`, or `typescript`. Rouge generates token spans on the server; colors come from the Reading Room stylesheet. Highlighting works in the reader, draft preview, and exercise prompts/answers, including after Turbo navigation, without a client-side highlighting runtime. Inline code keeps its neutral styling.

Supported languages include Ruby/ERB, JavaScript/TypeScript/JSX/TSX, Python, SQL, HTML/CSS, JSON/YAML, shell, PowerShell, Java, C/C++/C#, Go, Rust, Dockerfile, TOML, Markdown and diff. Rouge aliases such as `rb`, `js`, `ts`, `py`, `yml`, `bash` and `sh` are accepted. Language detection is explicit; missing or unsupported labels leave plain text.

`LessonCode` limits highlighting to 20,000 bytes per block. The renderer considers the first 32 ordinary fenced blocks per Markdown fragment. Larger blocks, unsupported languages and highlighting failures retain their full escaped source. Generated token HTML passes through the same final sanitizer as the rest of the lesson; inline styles and executable HTML remain prohibited. Math, diagrams and exercise JSON keep their dedicated renderers.

Rouge was selected for its Ruby integration, class-based HTML output, and language coverage. The bundled Commonmarker highlighter was also evaluated: its class-based mode removes the fence language attribute used by the learning-block renderer, and the installed grammar set does not highlight TypeScript. Highlight.js and Shiki are viable JavaScript alternatives; this implementation keeps highlighting in the existing server rendering path.

Links allow HTTP, HTTPS, root-relative paths beginning with one slash, and fragment references. Unsupported URLs lose their link target while retaining the visible text. Raw HTML is displayed as text. Scripts, inline styles, event handlers, and arbitrary embedded media cannot enter the rendered document.

## Attach a local image

Use the importer through the Rails task:

```sh
ruby bin/rails lessons:attach_image LESSON=1 KEY=commute-times "FILE=C:/Images/commute-times.png" "ALT=Daily commute times in minutes"
```

Replace the lesson ID and file path with your own values. Unix absolute paths work too. This command runs locally with the application's database access; there is no public upload endpoint or editing UI.

The task prints a reference to place in the lesson body:

```markdown
![](image:commute-times)
```

An empty Markdown description uses the stored alternative text. You can override it at a particular occurrence and add a visible caption using the Markdown title:

```markdown
![Monday 8, Tuesday 4, Wednesday 12, Thursday 6, Friday 10 minutes.](image:commute-times "Five observations from one week.")
```

Put the image on its own line, separated by blank lines, to produce a figure and caption. Inline images use a span container. The key is unique within the lesson, uses lowercase letters, digits, and single hyphens, and has at most 80 characters. Alternative text is required and has at most 500 characters.

Reimporting an existing key updates that image without changing its Markdown references. An unchanged file keeps its existing blob; a missing file is restored on reimport. Use `LessonImages::Import.call(lesson:, key:, path:, alt_text:)` for future internal integrations so they share the same validation and replacement behavior.

The importer reads at most 5 MB plus one byte, detects the type from the file contents, and decodes the image with libvips. It accepts PNG, JPEG, and WebP up to 5 MB and 20 million pixels. SVG, other formats, corrupt files, and oversized images are rejected before attachment. A filename extension alone is not trusted. The model also checks attachment presence, MIME type, and byte size.

## Storage and rendering

A `LessonImage` belongs to one lesson and owns one Active Storage attachment. Its key and alternative text live in PostgreSQL. File bytes use the Disk service: `storage/` in development and production, `tmp/storage/` in tests. libvips is required for import validation; the production Dockerfile and CI install it.

The renderer only accepts `image:key` references to images attached to the current lesson. It generates the Active Storage URL itself. External image URLs, data URLs, unknown keys, and missing files show a localized placeholder with the available description. A Stimulus controller provides the same fallback if an image fails after the page is rendered.

Active Storage serves these library images through signed URLs. The current library is public and does not implement per-user media authorization. Back up PostgreSQL and the storage directory together. Runtime uploads stay outside Git; the repository includes only the original prepared demo chart under `db/seeds/images/`.

## Prepared example and checks

`ruby bin/rails db:seed` refreshes the existing statistics course and imports its chart. Repeating the seed preserves course, lesson, image, and unchanged blob identities. The first lesson combines prose, a list, a chart, a caption, a data table, and a quotation. The second includes Ruby code and a documentation link.

The chart is original project material, rendered with Chart.js from the five values 8, 4, 12, 6, and 10. Its text alternative and adjacent table provide the same data without depending on the image.

Tests cover Markdown structure, unsafe markup and URLs, local image scoping, rejected uploads, idempotent imports, missing files, browser reloads, Turbo navigation, client-side image failures, and narrow-screen code scrolling:

```sh
ruby bin/rails test:all
```

Implementation references: [Commonmarker](https://github.com/gjtorikian/commonmarker), [Rouge](https://github.com/rouge-ruby/rouge), and [Active Storage](https://guides.rubyonrails.org/active_storage_overview.html).
