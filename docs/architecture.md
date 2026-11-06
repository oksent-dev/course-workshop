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

The library links to `/:locale/courses/:slug`. The course page lists its lessons and links to the first one. The reader at `/:locale/courses/:course_slug/lessons/:id` looks up the lesson through that course. An unrelated lesson ID returns 404. The outline loads lesson headings in position order and supplies adjacent links even when the stored positions have gaps.

`LessonMarkdown` renders the current body with Commonmarker, resolves image references within the lesson, restricts link schemes, and sanitizes the HTML. The view styles semantic elements within `.lesson-content`; wide code and tables have their own scroll containers.

`LessonImage` stores a unique key per lesson and alternative text, and owns one Active Storage file. `LessonImages::Import` validates local image contents and performs repeatable imports through a Rails task or the seed. Missing files produce a text fallback, including when a request fails in the browser. See [lesson content](lesson-content.md) for syntax, limits, and storage behavior.

The [seed script](../db/seeds.rb) loads the prepared course in a transaction. It reuses the category name and course slug, and updates the demo lessons by their one-based position in the source file. Those positions identify the seeded lessons across runs. Append new lessons or edit the material at its existing position to preserve the meaning of saved links.

## Planned course features

Upcoming features include exercises and learning progress. Math, diagrams, and supported interactive elements will extend the reader through dedicated components.

Generated content will be treated as input: HTML output must be sanitized, and interactive blocks must use validated data rather than arbitrary generated JavaScript.

## Lesson conversations and the agent boundary

The optional lesson panel uses a Stimulus controller to submit questions and poll Rails for saved outcomes. `ConversationsController` resolves the lesson through its course, then scopes the conversation to a random key in the browser session. `Conversation` owns ordered `Exchange` records containing question, lesson snapshot, answer, and status.

`LessonReplyJob` calls a replaceable tutor adapter outside the HTTP request. `Codex::Tutor` manages thread and turn semantics; `Codex::Connection` owns the stdio process, JSON-lines transport, deadline, and cleanup. The adapter pins GPT-6.1 Sol and resumes the conversation's Codex thread for follow-ups. Only final answer text is saved, never raw reasoning or tool events.

The integration is opt-in and restricted to local development. Production rejects all conversation endpoints. See [local AI](local-ai.md) for access checks, cancellation, data retention, queue limitations, and the verification procedure. A future MCP interface will expose focused course operations separately.

## Development and production

Development runs Ruby on the host and PostgreSQL in Docker. The production image runs Rails on Linux and includes compiled assets. Dependency lockfiles cover Windows and Linux.

Development credentials and uploaded content are local runtime data. The public repository contains configuration examples, not credentials.
