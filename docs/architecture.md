# Architecture

## Application

Course Workshop is a server-rendered Rails application. ERB produces HTML; Turbo handles navigation and partial updates; Stimulus provides focused browser behavior. esbuild bundles JavaScript, and the standalone Tailwind executable builds CSS.

PostgreSQL is the application database. Active Storage stores file metadata in PostgreSQL and file contents on disk. Production uses the standard Solid adapters, with separate cache, queue, and cable databases.

## Localization

The UI supports `pl` and `en`. URLs contain the selected locale, and an `around_action` applies it only for the current request. Locale dictionaries contain interface strings. Development and tests raise on missing translations.

The language switcher generates the current route with the chosen locale. Category names, course titles and descriptions, and lesson text come from the catalog. The `courses.language` column identifies the content language, including for assistive technology in the reader.

## Library and reader

| Record | Owns | Constraints and ordering |
| --- | --- | --- |
| Category | Named group of courses | Unique name. The library shows groups with courses, in name order. |
| Course | Category, unique URL slug, title, description, content language | The library sorts courses by title within a category. The slug identifies the course independently of the interface locale. |
| Lesson | Parent course, title, body, position | A foreign key requires a course. PostgreSQL requires a positive position and enforces uniqueness of the course and position pair. |

The library links to `/:locale/courses/:slug` and offers a direct start, resume, or review action. The course page lists its lessons and offers the same action. The reader at `/:locale/courses/:course_slug/lessons/:id` looks up the lesson through that course. An unrelated lesson ID returns 404. The outline loads lesson headings in position order and supplies adjacent links even when the stored positions have gaps.

`LessonMarkdown` renders the current body with Commonmarker, resolves image references within the lesson, restricts link schemes, and sanitizes the HTML. The view styles semantic elements within `.lesson-content`; wide code and tables have their own scroll containers.

`LessonBlock` validates the explicit `math`, `mermaid`, and `exercise` fence formats. Math and diagram components keep escaped source as a fallback and load browser renderers through Stimulus. KaTeX uses untrusted-input settings; Mermaid receives a limited flowchart syntax and its SVG is sanitized before insertion. Exercises render sanitized prompt/answer Markdown with a native disclosure. Special blocks do not recursively render inside exercises. See [learning blocks](learning-blocks.md) for the full contract.

esbuild splits the renderer bundles into content-hashed chunks. Chunk and font filenames use Propshaft's `.digested` convention so the browser can resolve imports after production precompilation. Rails provides the fingerprinted renderer entry URLs; ordinary library navigation does not fetch these modules.

`LessonImage` stores a unique key per lesson and alternative text, and owns one Active Storage file. `LessonImages::Import` validates local image contents and performs repeatable imports through a Rails task or the seed. Missing files produce a text fallback, including when a request fails in the browser. See [lesson content](lesson-content.md) for syntax, limits, and storage behavior.

The [seed script](../db/seeds.rb) loads the prepared course in a transaction. It reuses the category name and course slug, and updates the demo lessons by their one-based position in the source file. Those positions identify the seeded lessons across runs. Append new lessons or edit the material at its existing position to preserve the meaning of saved links.

## Learning progress

`LearnerContext` resolves a shared local profile for loopback development requests or an anonymous browser profile from an encrypted persistent cookie. Production always uses browser profiles. `LearnerProfile` owns `LessonProgress` rows, unique per profile and lesson, with separate visit and completion timestamps.

`CourseProgress` calculates counts and resume targets from current lessons. Library queries batch outlines and progress across courses. `CompletionsController` scopes the lesson through its course and writes only to the current profile. Standard Rails forms provide CSRF protection and work with or without Turbo. Personalized responses disable caching; prefetch and HEAD requests do not record visits. See [learning progress](learning-progress.md) for behavior and persistence boundaries.

## Planned course features

Upcoming features include in-app course generation and additional interactive components.

Generated content will be treated as input: HTML output must be sanitized, and interactive blocks must use validated data rather than arbitrary generated JavaScript.

## Draft authoring

Courses start as drafts. The migration preserves existing courses as published, and the demo seed explicitly publishes its prepared content. Public controllers only resolve published courses; local draft preview and approval use a separate controller guarded by `LocalAuthoring`.

`bin/mcp` starts the Ruby MCP SDK over stdio. `CourseMcp::Server` defines strict tool schemas and maps errors to tool results. `Drafts::Catalog` returns bounded course metadata, outlines, and individual lessons. `Drafts::Editor` serializes edits and approval with a course row lock and revision check. `Drafts::LessonContent` applies authoring limits and reuses the learning-block validators.

`DraftOperation` atomically stores each successful mutation's request-key fingerprint and result. Its unique index coordinates concurrent retries across server processes. Reusing a key with different input fails; a matching retry replays the saved result. Failed operations leave no receipt or partial changes. No model call happens inside these transactions.

Publication is a human action in the local preview, outside the MCP tool set. See [course authoring](course-authoring.md) for the contracts, authority boundary, and examples.

## Lesson conversations and the agent boundary

The optional lesson panel uses a Stimulus controller to submit questions and poll Rails for saved outcomes. `ConversationsController` resolves the lesson through its course, then scopes the conversation to a random key in the browser session. `Conversation` owns ordered `Exchange` records containing question, lesson snapshot, answer, and status.

`LessonReplyJob` calls a replaceable tutor adapter outside the HTTP request. `Codex::Tutor` manages thread and turn semantics; `Codex::Connection` owns the stdio process, JSON-lines transport, deadline, and cleanup. The adapter pins GPT-6.1 Sol and resumes the conversation's Codex thread for follow-ups. Only final answer text is saved, never raw reasoning or tool events.

The integration is opt-in and restricted to local development. Production rejects all conversation endpoints. See [local AI](local-ai.md) for access checks, cancellation, data retention, queue limitations, and the verification procedure. The separate MCP interface exposes course operations; the lesson tutor continues to disable all MCP tools.

## Development and production

Development runs Ruby on the host and PostgreSQL in Docker. The production image runs Rails on Linux and includes compiled assets. Dependency lockfiles cover Windows and Linux.

Development credentials and uploaded content are local runtime data. The public repository contains configuration examples, not credentials.
