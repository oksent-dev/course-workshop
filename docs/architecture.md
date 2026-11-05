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

The library links to `/:locale/courses/:slug`. The course page lists its lessons and links to the first one. The reader at `/:locale/courses/:course_slug/lessons/:id` looks up the lesson through that course. An unrelated lesson ID returns 404. The outline loads lesson headings in position order and supplies adjacent links even when the stored positions have gaps. The current body is rendered as escaped paragraphs.

The [seed script](../db/seeds.rb) loads the prepared course in a transaction. It reuses the category name and course slug, and updates the demo lessons by their one-based position in the source file. Those positions identify the seeded lessons across runs. Append new lessons or edit the material at its existing position to preserve the meaning of saved links.

## Planned course features

Upcoming features include exercises, learning progress, and lesson conversations. Markdown rendering will extend the reader. Math, diagrams, and supported interactive elements will use dedicated components.

Generated content will be treated as input: HTML output must be sanitized, and interactive blocks must use validated data rather than arbitrary generated JavaScript.

## Planned agent boundary

The embedded chat will use an adapter to a local Codex runtime, initially evaluated through Codex App Server. A separate MCP interface will expose focused course operations to the agent.

This integration is not implemented in the foundation. It must keep application access rules in the application, pass explicit lesson context, and handle cancellation and failures. Public demonstration deployments will need an explicit policy for disabling live AI operations.

## Development and production

Development runs Ruby on the host and PostgreSQL in Docker. The production image runs Rails on Linux and includes compiled assets. Dependency lockfiles cover Windows and Linux.

Development credentials and uploaded content are local runtime data. The public repository contains configuration examples, not credentials.
