# Architecture

## Application

Course Workshop is a server-rendered Rails application. ERB produces HTML; Turbo handles navigation and partial updates; Stimulus provides focused browser behavior. esbuild bundles JavaScript, and the standalone Tailwind executable builds CSS.

PostgreSQL is the application database. Active Storage stores file metadata in PostgreSQL and file contents on disk. Production uses the standard Solid adapters, with separate cache, queue, and cable databases.

## Localization

The UI supports `pl` and `en`. URLs contain the selected locale, and an `around_action` applies it only for the current request. Locale dictionaries contain interface strings. Development and tests raise on missing translations.

The header's PL/EN disclosure generates the current route with the chosen locale, preserving category filters in the library and drafts, and `lesson_id` in draft previews. Category names, course titles and descriptions, and lesson text come from the catalog. The `courses.language` column identifies the content language, including for assistive technology in the reader.

`layouts/navigation` owns global navigation and the creation action. `navigation_section` maps published reading routes to Library, draft and generation-status routes to Drafts, and the creation form to Create a course. Existing local-access guards control the visibility of authoring links. The `language-menu` Stimulus controller adds Escape, outside-click and focus dismissal to a native disclosure; its links remain usable without JavaScript.

## Library and reader

| Record | Owns | Constraints and ordering |
| --- | --- | --- |
| Category | Named group of courses | Whitespace-normalized name with case-insensitive uniqueness. Authoring reuses stable IDs. Library filters include only categories with published courses, in name order. |
| Course | Category, unique URL slug, title, description, content language, optional Active Storage cover | The library sorts published cards by title and ID. The slug identifies the course independently of the interface locale. |
| Lesson | Parent course, title, body, position | A foreign key requires a course. PostgreSQL requires a positive position and enforces uniqueness of the course and position pair. |

The library links to `/:locale/courses/:slug` and offers a direct start, resume, or review action. The course page lists its lessons and offers the same action. The reader at `/:locale/courses/:course_slug/lessons/:id` looks up the lesson through that course. An unrelated lesson ID returns 404. The outline loads lesson headings in position order and supplies adjacent links even when the stored positions have gaps.

`LessonMarkdown` renders the current body with Commonmarker, resolves image references within the lesson, restricts link schemes, and sanitizes the HTML. `LessonCode` applies Rouge to bounded, explicitly labeled ordinary code fences before learning blocks are expanded. Token classes survive the final sanitizer, while code text stays inert. The view styles semantic elements within `.lesson-content`; wide code and tables have their own scroll containers.

`LessonBlock` validates the explicit `math`, `mermaid`, and `exercise` fence formats. Math and diagram components keep escaped source as a fallback and load browser renderers through Stimulus. KaTeX uses untrusted-input settings; Mermaid receives a limited flowchart syntax and its SVG is sanitized before insertion. Exercises render sanitized prompt/answer Markdown with a native disclosure. Special blocks do not recursively render inside exercises. See [learning blocks](learning-blocks.md) for the full contract.

esbuild splits the renderer bundles into content-hashed chunks. Chunk and font filenames use Propshaft's `.digested` convention so the browser can resolve imports after production precompilation. Rails provides the fingerprinted renderer entry URLs; ordinary library navigation does not fetch these modules.

`LessonImage` stores a unique key per lesson and alternative text, and owns one Active Storage file. `LessonImages::Import` validates local image contents and performs repeatable imports through a Rails task or the seed. Missing files produce a text fallback, including when a request fails in the browser. See [lesson content](lesson-content.md) for syntax, limits, and storage behavior.

The [seed script](../db/seeds.rb) loads the prepared course in a transaction. It reuses the category name and course slug, and updates the demo lessons by their one-based position in the source file. Those positions identify the seeded lessons across runs. Append new lessons or edit the material at its existing position to preserve the meaning of saved links.

The library uses `?category=ID` for filtering. Counts are computed from published courses before filtering. An unknown category, or one containing only drafts, returns 404. Covers, categories, lesson outlines, and learner progress are loaded in batches for the selected courses. `CourseCovers::Import` and `LessonImages::Import` share `ImageUpload` for content detection, size limits, and full image decoding. Course covers use a named 960 × 540 WebP variant. The browser's image-fallback controller is shared with lesson images. See [course covers](course-covers.md).

## Learning progress

`LearnerContext` resolves a shared local profile for loopback development requests or an anonymous browser profile from an encrypted persistent cookie. Production always uses browser profiles. `LearnerProfile` owns `LessonProgress` rows, unique per profile and lesson, with separate visit and completion timestamps.

`CourseProgress` calculates counts and resume targets from current lessons. Library queries batch outlines and progress across courses. `CompletionsController` scopes the lesson through its course and writes only to the current profile. Standard Rails forms provide CSRF protection and work with or without Turbo. Personalized responses disable caching; prefetch and HEAD requests do not record visits. See [learning progress](learning-progress.md) for behavior and persistence boundaries.

## Planned course features

Additional interactive components remain possible extensions.

The [course assistant design](course-assistant.md) separates the implemented history/recovery foundation from the planned shared tutor/editor interface, draft tools and activity cards. Course-level history and durable execution are available. The current panel still opens from published lessons and the tutor remains read-only.

Generated content is treated as input: HTML output is sanitized, and interactive blocks use validated data rather than arbitrary generated JavaScript.

## Draft authoring

Courses start as drafts. The migration preserves existing courses as published, and the demo seed explicitly publishes its prepared content. Public controllers only resolve published courses; local draft preview and approval use a separate controller guarded by `LocalAuthoring`.

The draft index shares `courses/course`, `courses/cover` and `courses/category_filters` with the library. Its category counts include drafts only, and `?category=ID` filters the collection. Cards show generation status and saved-lesson counts instead of learning progress. Covers, categories and generation records are preloaded; one grouped query counts lessons without loading their bodies. The most recently updated drafts appear first. Previewing a card does not record learning progress or publish the course.

Generated draft cards open `/:locale/generations/:id` as their overview, including after generation completes. `draft_entry_path` falls back to the lesson preview for manual drafts or when local generation is unavailable. The overview offers outlined lesson preview and final approval once complete; the preview offers a return to the overview beside approval. Both reuse `drafts/approve_button` and `DraftsController#update`, including its revision and completeness checks. Once published, overview lesson links target the public reader.

`bin/mcp` starts the Ruby MCP SDK over stdio. `CourseMcp::Server` defines strict tool schemas and maps errors to tool results. `Drafts::Catalog` returns bounded course metadata, outlines, and individual lessons. `Drafts::Editor` serializes edits and approval with a course row lock and revision check. `Drafts::LessonContent` applies authoring limits and reuses the learning-block validators.

`DraftOperation` atomically stores each successful mutation's request-key fingerprint and result. Its unique index coordinates concurrent retries across server processes. Reusing a key with different input fails; a matching retry replays the saved result. Failed operations leave no receipt or partial changes. No model call happens inside these transactions.

Publication is a human action in the local preview, outside the MCP tool set. See [course authoring](course-authoring.md) for the contracts, authority boundary, and examples.

## Course generation

`GenerationsController` reserves a draft and `CourseGeneration` in one transaction, then enqueues `CourseGenerationJob`. The form supplies a topic and language; the model chooses the lesson count when saving its plan. A submission UUID makes repeated requests idempotent. The plan must be approved before writing begins. A Stimulus controller polls stages, current lesson, bounded activity labels and saved results without restarting model work.

`Codex::CourseGenerator` uses the shared `Codex::Runtime` restrictions, then enables live web search and a dedicated `CourseMcp::GenerationServer`. This server is bound to one generation and a revocable step token. Planning and each lesson run as separate jobs and fresh threads. Only the current approved position is writable, with the same validation and receipts as ordinary authoring. A database step number guards duplicate/late delivery. No course identifier supplied by the model can change the scope.

Cancellation revokes the token immediately. Explicit resume starts a new attempt and thread while retaining the draft, plan and existing lesson IDs. Completeness is checked before approval. Development uses Solid Queue with a separate database and worker. Recovery checks committed material before starting another step; an uncertain result requires explicit resume. See [course generation](course-generation.md) for lifecycle, limits and recovery.

Each generated lesson needs a table, math block, diagram or attached image in its main material. A paired illustration brief/alternative text can reserve a separate image step after saving the lesson text. `Codex::LessonIllustrator` reuses the restricted image transport with an educational brief. The result becomes a local `LessonImage`; its reference is appended only after validated attachment. Image failures retain the text and retry the image step. Checking every lesson and its visual precedes final completion.

Generation state includes the existing category catalog. The model selects a suitable category ID before considering a new name; both scoped and ordinary MCP authoring share the same category resolver. PostgreSQL prevents duplicate names regardless of case.

Completed form generations reserve a `CourseCoverGeneration` in the completion transaction and enqueue its job after commit. `Codex::CoverGenerator` opens a separate restricted session with native image generation enabled and no MCP or web access. Validated inline image bytes become the course's local Active Storage attachment. Cover status, expiry and retries are independent of the completed lessons; old attempts cannot attach late results, and manual covers are preserved. The progress screen polls both records and offers a cover-only retry. See [course covers](course-covers.md).

## Lesson conversations and the agent boundary

The optional floating lesson panel separates interface and transport. `LessonChatController` opens a non-modal dialog, manages focus and viewport placement, and captures text selected within the current lesson body. `ConversationController` submits questions and polls Rails for saved outcomes while open, retaining an unsent question and optional quote across panel close/reopen. Navigation creates a fresh widget for the new lesson.

`ConversationsController` resolves the lesson through its course, then uses `LearnerContext` to find a course conversation for the current profile and tutor mode. A partial unique index protects this ownership. Legacy lesson conversations retain their IDs, messages and runtime links; only a matching old session key can associate them with a profile. `Conversation#history` includes that profile's retained legacy messages without moving records or merging runtime threads.

`Exchange` captures the course ID, description, outline, revision, mode, current lesson ID/body, locale and optional passage at submission. Moving between lessons does not change this snapshot. The passage is limited to 2,000 characters and is not inherited by later questions. The transcript labels saved questions with their original lesson. Course history survives deleting an individual lesson.

`LessonReplyJob` calls a replaceable tutor adapter outside the HTTP request. `Codex::Tutor` manages thread and turn semantics; `Codex::Connection` owns the stdio process, JSON-lines transport, deadline, and cleanup. The adapter pins GPT-6.1 Sol and resumes the conversation's Codex thread for follow-ups. Only final answer text is saved, never raw reasoning or tool events.

`AiRun` records each reply, generation step or image attempt with its job ID, operation key, submission marker, runtime IDs, result item IDs and recovery lease. `DurableDispatch` records queue delivery on the subject; the recurring sweep repairs the gap between a primary-database commit and a queue-database enqueue. Repeated jobs cannot claim the same request twice. `AiRecovery` imports a mapped completed turn or reconciles saved generation checkpoints. Unknown results are checked at most three times before becoming explicitly uncertain; recovery never sends a model turn or regenerates an image.

The integration is opt-in and restricted to local development. Production rejects all conversation endpoints. See [local AI](local-ai.md) for access checks, cancellation, data retention, recovery and verification. The separate MCP interface exposes course operations; the lesson tutor continues to disable all MCP tools.

## Development and production

Development runs Ruby on the host and PostgreSQL in Docker. The production image runs Rails on Linux and includes compiled assets. Dependency lockfiles cover Windows and Linux.

Development credentials and uploaded content are local runtime data. The public repository contains configuration examples, not credentials.
