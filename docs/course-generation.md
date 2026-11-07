# Plan and generate a course

Open **Create a course**, describe your topic and learning goal, and choose Polish or English. GPT-6.1 Sol proposes a title, category, description and lesson outline. It chooses the number of lessons; the form does not ask the learner to estimate it. The application supports 1–60 lessons per course, matching the authoring limit.

**Approve plan and generate lessons** starts writing. Planning never grants permission to write lessons: the server enforces the approval boundary. Completed courses still remain drafts until separately reviewed and added to the library.

Open a generated draft card to return to **Course plan and status**. Use **Preview draft** to read the lessons, then **Approve and add to library** from either the overview or lesson preview. These are separate actions from approving the initial plan. Final approval remains unavailable until generation completes and submits the displayed course revision for validation.

## Local setup

Run `ruby bin/rails db:prepare`, configure the [local Codex runtime](local-ai.md), and enable both flags in the private `.env`:

```dotenv
LOCAL_AI_ENABLED=true
COURSE_AUTHORING_ENABLED=true
CODEX_EXECUTABLE=codex
```

Use an absolute executable path on Windows if needed. Restart `ruby bin/dev` after configuration changes. PostgreSQL and the local application must stay running. The generator launches its own scoped MCP child process; no global MCP registration is required. Native image generation must be available for covers and requested lesson illustrations. It uses the Codex account allowance, without a separate Image API key.

## What the learner sees

The progress page polls saved state every 1.5 seconds while work is pending. It shows:

- The proposed plan and its model-selected lesson count, followed by an explicit approval action.
- Planning, writing, completeness checks and cover stages.
- The current lesson and activity, including source research, saving and illustration generation.
- The time of the last recorded activity, saved-lesson count and links to available lesson previews.
- Cancel, resume, network refresh and the cover-only retry action where applicable.

Progress counts saved lesson text; a requested illustration may still be pending. It is not an ETA or a claim of factual correctness. Research labels come from actual `webSearch` items, and saving labels from write-tool starts. No raw model reasoning, transcripts or tool arguments are sent to the browser. Item events follow the [App Server event contract](https://learn.chatgpt.com/docs/app-server#events).

Leaving the page does not cancel work. Return through **Create a course → Recent generations**, or reopen its URL. Keep the computer and worker running for inference. Development uses Solid Queue in PostgreSQL with a separate worker started by `bin/dev`; queued work survives a restart. Plans, approvals, completed lessons, image requests and runtime identifiers are persisted. Recovery checks committed material and stored Codex results before advancing. If the outcome cannot be confirmed, inspect saved material and resume explicitly. Waiting in the queue or for plan approval does not expire.

## Stages and recovery

`CourseGeneration` owns one reserved draft, submission UUID, topic, language, nullable lesson count, plan, approval time, status, stage, attempt, step number, current lesson position, activity timestamp, deadline and token digest. Before planning, the lesson count is unknown. Legacy completed generations retain their content and approval eligibility.

| Status | Meaning | Action |
| --- | --- | --- |
| `queued` | A persisted step is waiting for a worker | Cancel or inspect |
| `running` | One planning, writing, illustration or checking step is active | Inspect or cancel |
| `awaiting_approval` | The plan is saved; no lesson writing is authorized | Review and approve, or cancel |
| `completed` | All planned lesson material and required visuals passed completeness checks | Review the draft; cover may still be pending |
| `failed` | A step failed or expired | Resume remaining work |
| `cancelled` | Scoped write access was revoked | Resume; an unapproved plan still requires approval |

Each model step gets a five-minute runtime deadline and a seven-minute write-token expiry after it starts. A long course is a sequence of separately queued steps, not one turn with a whole-course timeout. Every job claims its exact `(attempt, step)` under a row lock and creates an `AiRun` in the same transaction. Duplicate delivery and stale jobs cannot claim or complete newer work. Each text step uses a fresh Codex thread and token; previous MCP processes lose access when that step finishes. New runtime IDs are retained per step; pre-existing generation threads were not recorded and cannot be reconstructed as one original conversation.

An interrupted worker is detected through failed queue execution or the eight-minute run lease. Recovery revokes the old token and checks committed plans, lessons and image attachments first. A saved plan still stops at approval. A saved lesson advances without rewriting it. A completed mapped image turn can supply validated bytes without generating another image. If the image is absent from history, the existing image and text remain intact and an explicit retry is required. A new step after a recovered checkpoint may call the model as usual; reconciliation itself does not. See [local AI recovery](local-ai.md#durable-jobs-and-recovery) for queue repair, limits and operational commands.

Planning sets metadata and a fixed ordered outline, then stops. Approval checks the current attempt and course revision before queuing the first missing lesson. Writing grants access only to `current_position`; the agent reads the outline and saved lessons for continuity, writes that lesson, verifies it, and stops. A local checking step validates every title, position, body and visual before completion. There are no model calls inside database transactions.

Resume keeps saved lessons and their IDs. A lesson saved before an interrupted turn is not written again. If it requested an illustration, that image step is resumed first. A failed plan attempt that already saved a plan returns to approval rather than bypassing it. Cancellation clears the current token immediately; late activity and writes are rejected. Approval of the finished course remains a separate user action.

## Categories and visuals

`read_generation` supplies existing category IDs and names, excluding the reserved `Drafts` placeholder. Prefer a suitable existing ID, including broader subjects and names in another language. `plan_course` requires exactly one of `category_id` or a new `category` name. The model should create a new broad category only when none fits. Names are whitespace-normalized and case-insensitively unique in PostgreSQL. Semantic matching remains a model decision; existing labels are preserved.

Every newly generated lesson must contain at least one supported visual in the main material: a Markdown table, a display math fence, a valid Mermaid diagram or an attached image. Text, raw HTML and code fences pretending to contain a table do not qualify. Visuals should explain the subject and be discussed in the prose; semantic quality and numerical accuracy still require review. Exercises are additional learning material, not a substitute for the main visual.

When an image best explains a concept, `save_generated_lesson` can supply both `illustration_prompt` (up to 2,000 characters) and `illustration_alt` (up to 500, in the course language). The text is saved first. A separate illustration step calls native Codex image generation, validates the returned bytes, stores a `LessonImage` in local Active Storage and appends its stable `image:generated-illustration` reference. The agent must not insert an unattached image URL itself. Image failure keeps the text and request for retry. Repeated/late results cannot append duplicate illustrations. Body input is capped at 38,000 characters to leave room for the attachment markup within the 40,000-character content limit.

Remote image URLs are still rejected; automatic downloading/importing of web images is not implemented. Existing local attachments can be reused. Generated images are conceptual illustrations, not documentary evidence. The [content format](lesson-content.md) and [learning blocks](learning-blocks.md) describe renderer limits.

Successful course completion atomically reserves an independent `CourseCoverGeneration` unless a cover already exists. Its job starts after commit. Cover errors do not invalidate complete lessons; **Retry cover** affects only the cover. See [course covers](course-covers.md).

## Scoped MCP and access

`bin/generation-mcp` exposes five tools without caller-supplied course IDs:

| Tool | Purpose |
| --- | --- |
| `get_authoring_guide` | Formats, stage boundaries and retry rules |
| `read_generation` | Topic, stage, current position, approval, plan, category catalog and saved lessons |
| `plan_course` | Set metadata and 1–60 distinct lesson titles once, during planning only |
| `read_generated_lesson` | Read a saved lesson by planned position |
| `save_generated_lesson` | Write only the current approved lesson, with a visual or an illustration request |

Every distinct mutation requires a UUID `request_key`. The existing `DraftOperation` receipt protects identical retries; conflicting reuse is rejected. The token and generation ID travel only through the scoped child environment; PostgreSQL stores a digest. Every tool checks running state, expiry, token and local enablement, including receipt replay. A token cannot authorize plan approval or publication.

Text sessions enable only their MCP allow list and live web search. Image sessions enable only native image generation and receive a bounded visual brief. Both pin `gpt-6.1-sol`, disable unrelated MCP servers, shell, apps, plugins, project instructions and hooks, and use a read-only sandbox. Session-only MCP approval authorizes writes within the submitted workflow; global Codex configuration is unchanged. Unexpected interactive requests are rejected.

HTTP actions require both feature flags, development/test and loopback host/client addresses. Production rejects them regardless of flags. This is one local workspace, not a multi-tenant permission system. Topics are filtered from HTTP logs; local SQL logs and Codex history may contain course material and should stay outside Git.

## Verification

Run `ruby bin/rails test:all`. Model and image adapters are faked in automated tests. Coverage includes 18-lesson plans, approval boundaries, duplicate submissions/jobs, token revocation, per-step expiry, partial resume, image retry without rewriting lessons, visual validation, category reuse, stdio, local HTTP boundaries, polling, keyboard controls and focus changes without replaying entrance animations.

For a real smoke check, submit a short topic, wait for its plan, confirm no lessons were written, approve it, observe separate writing/image stages, then review the draft and its visuals after reload. Leave library approval to the learner.

The reviewed workflow was checked on Windows on 2026-11-07 with Codex App Server `0.167.0-alpha.3.2` and `gpt-6.1-sol`. The model proposed one lesson for a deliberately narrow composition topic, waited for approval, wrote the material and requested an illustration. Both the lesson image and cover were stored locally and displayed after reload. The draft remained unpublished.
