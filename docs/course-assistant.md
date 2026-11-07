# Course assistant: implementation and planned design

Status: the durable execution foundation and shared interface are implemented as of 2026-11-07. The panel follows outlines, lessons and drafts, with context labels, preserved composers, persisted generation/cover status cards and explicit content refresh. Draft editing tools, operation receipts, refresh tools and undo remain planned. [Local AI](local-ai.md) documents the implemented lifecycle and limits.

The assistant should follow a course from its outline into individual lessons. Published courses offer tutoring; drafts offer editing through bounded tools. The panel, quote interaction and navigation remain consistent, while permissions and conversation ownership remain explicit.

## Current behavior and verified capabilities

- `Conversation` belongs to a course, learner profile and mode. Legacy lesson records remain intact. `Exchange` persists questions, selected passages, immutable context snapshots, answers and statuses in PostgreSQL. A permanent panel and per-tab session storage retain unsent input, quote origin, open/expanded state and scroll through navigation and reloads.
- `Codex::Tutor` resumes a stored thread. Recovery can restore completed answers from mapped runtime history; a missing thread is replaced on the next explicit question with a bounded application-history handoff.
- `Codex::CourseGenerator` still starts a fresh thread per step. New executions persist runtime identifiers in `AiRun`. Pre-existing generation identifiers were not recorded, so there is no single original generation conversation to resume.
- Development uses Solid Queue with a separate database and threaded worker. Queued work survives restarts. Recovery reconciles completed turns and saved generation checkpoints; unresolved outcomes require explicit resubmission/resume. A local Codex process is not an independently durable service.
- The configured runtime successfully returned an existing tutor thread through `thread/read` and its stored messages through `thread/turns/list` with `itemsView: "full"`. This read-only check did not start a model turn or change course content.

The official [App Server documentation](https://learn.chatgpt.com/docs/app-server#read-a-stored-thread-without-resuming) describes stored history, pagination and `thread/resume`. Reading history does not restart work. Availability still depends on the stored thread being present and accessible to the configured runtime.

## Conversation and context

Use one course-level transcript per owner and mode. Locally, use the existing shared learner profile rather than a session-cookie identity. Keep tutor and authoring histories separate so publishing a course never exposes its private editing conversation to readers. Preserve existing lesson conversations during migration; do not silently merge browser identities or delete history.

| Surface | Context supplied for a new message | Capability |
| --- | --- | --- |
| Published course outline | Title, description, language and ordered lesson titles | Explain the course and suggest a learning path |
| Published lesson | Outline plus the current lesson and optional selected passage | Explain and discuss; no writes |
| Draft plan/status | Topic, current metadata, outline, generation state and revision | Discuss the draft and suggest improvements; editing tools are planned |
| Draft lesson | Draft overview plus the current lesson and optional selected passage | Discuss the lesson; scoped mutations are planned |

Do not attach every lesson body to every message. The draft editor may explicitly read a relevant lesson through a scoped tool when a course-level request requires it; display that read as activity. Context scope controls newly supplied material, not forgetting material already seen in the conversation.

Each submitted message captures its course, mode, optional lesson ID, interface language, material revision and quote. The composer shows its current context and a separate source label for a retained quote. Saved messages show their original context. A running request keeps its original context if the user navigates. A changed course material version rejects a new quoted submission and preserves its composer for review; accepted request keys still replay their original result.

The same panel is available on the plan/status and lesson pages. Preserve its open/expanded state, scroll position and unsent input while moving within a course. A different course has its own transcript and composer. Existing selection timing and keyboard shortcuts remain unchanged.

## Continuity with generation

Present one authoring history to the user even when work uses multiple runtime threads. Record the initial topic, proposed/approved plan, completed steps and later editing requests as application events. Associate runtime thread, turn and item IDs with the particular run that produced them.

Keep short generation steps; do not concatenate every worker transcript into the user's chat. Establish a persistent authoring thread for subsequent requests and initialize it with the topic, approved decisions, current outline and a concise generation handoff. Later requests resume that thread. If a stored thread is missing, create a replacement with application history and current course state, clearly recording that recovery.

For old courses, construct the handoff from persisted course and generation records. Do not claim to have recovered the original generation dialogue: its runtime identifiers were not recorded. Retain existing tutor thread links where available.

## Draft editing boundary

Authorize the mode on the server for every request and every mutation. A read-only tutor cannot gain write permissions through its prompt. The editor gets a token scoped to one draft and one active run; it cannot modify other courses or publish anything.

Proposed capabilities:

- Read the current course outline, revision, individual lessons and attached-image metadata.
- Update title, description and category, using the existing category catalog.
- Add or replace a lesson, reorder lessons and remove a lesson recoverably.
- Request a new cover or lesson illustration through the existing native image mechanism.
- Request a view refresh for the committed course revision.

Keep content validation, required lesson visuals, attachment validation and category reuse. Store a revision and operation receipt with every successful mutation. Validate the expected revision before committing. Replayed tool requests return their original receipt instead of creating duplicate lessons or image jobs.

Allow only one writer per course across generation, assistant editing, image attachment, external authoring and final approval. Enforce this through a persisted run lease and short database transactions; never hold a database transaction open during inference. Active generation and editing must not race. While initial generation runs, show a clear waiting state for edit requests; a user may explicitly stop generation before changing its plan. Awaiting plan approval is an editable boundary. Any plan change invalidates an earlier approval before more lessons are generated.

Separate the current editable outline from the historical plan of the initial generation. Add/remove/reorder operations update the live outline and readiness checks without rewriting the record of what was originally approved. New or changed material must satisfy current completeness rules before final approval. Approval stays a user action and is unavailable while an editor has pending mutations.

## Recoverable changes and images

Record the before/after material and the related run for each change. Keep removed lessons recoverable, with stable IDs and retained assets. Offer an application-owned undo action for a change or the latest editing run. Undo creates a new revision and refuses to overwrite later unrelated edits without reconciliation. Codex thread rollback is not a database rollback.

Do not detach a usable cover while a replacement is being generated. Validate the new image before swapping it. Retain previous blobs while revisions reference them. Image generation has a separate persisted job, status and attempt identity; a failed image does not erase successful text changes. Cancellation revokes write access so a late image cannot replace a newer cover.

Multi-operation requests can finish partially. Show which changes were saved and which failed. Cancellation stops further work; it does not silently reverse completed changes. Undo is an explicit separate action.

## Activity and refreshing the view

The current panel reconstructs generation and cover cards from persisted records with stable IDs. Exchange states show queued, running, recovering and terminal reply outcomes. These are current status cards, not a complete audit trail of earlier transitions. An open panel polls for changes; version mismatches offer explicit content refresh while retaining the permanent panel, unsent text and quote. Each tab compares its own displayed material version. Publishing rejects further requests from the old editor mode and offers a route to the published overview.

The editing stage will add compact activity cards for scoped tools and committed receipts, for example:

- Reading lesson 3.
- Updating the example — saved.
- Adding a practice lesson — saved.
- Generating a new cover — running / failed / saved.

Use runtime tool events for started/running activity and committed application receipts for saved results. Never infer a successful write from an assistant sentence. Show readable summaries and optional change previews, not raw tool JSON, credentials or model reasoning. Persist events with stable IDs so reconnecting does not duplicate them.

Expose a bounded `refresh_course_view` tool. It accepts the affected course revision and resources, not JavaScript or an arbitrary URL. The tool records a refresh request; it does not claim the user's browser has already applied it. Committed writes and turn completion also announce changes, so visibility does not depend entirely on the model remembering to call the tool.

The browser refreshes relevant material, outline and cover through Turbo while retaining the assistant panel and composer. Coalesce multiple changes and defer disruptive refresh while a selection or edit is in progress, with a visible “Updates available” action. Maintain the current lesson and approximate reading position; if that lesson was removed, return to the overview with an explanation. Each tab tracks its own event cursor. Closing every tab leaves the job running, and reopening loads the newest state.

## Durable execution and history recovery

PostgreSQL remains authoritative for user-visible messages, accepted requests, operations, revisions and job state. Codex history is an additional recovery source, not the only transcript store.

Relevant jobs use Solid Queue with a separate local worker. Its documented [threaded supervisor mode](https://github.com/rails/solid_queue#fork-vs-async-mode) was verified on native Windows with a real worker termination and restart. Solid Queue's supervisor `async` mode still uses a database queue and is distinct from Active Job's in-memory Async adapter.

Persist thread and turn identifiers as soon as the runtime returns them. Record outgoing submissions before sending them. A recovery pass checks the run lease, operation receipts and stored runtime turns before deciding whether a request completed, remains active, failed or has an uncertain outcome. History import only accepts mapped application threads and deduplicates by thread/turn/item ID; it never scans and imports unrelated account conversations.

There is no cross-system exactly-once guarantee around a lost `turn/start` response. Do not blindly create another turn or regenerate an image when acknowledgement is missing. Reconcile identifiable results; otherwise mark the outcome as uncertain and offer an explicit resume after inspecting saved work. Use bounded retries for known transient failures. A missing thread must not remove application history.

Solid Queue [does not automatically retry work abandoned by a crashed worker](https://github.com/rails/solid_queue#jobs-interrupted-by-non-graceful-process-death). Add application recovery for failed/stale runs rather than assuming a durable queue resumes every interrupted model call. Closing the browser is different from stopping the worker or computer: stopped processes cannot continue inference locally.

## Delivery slices and acceptance

1. **Durable conversation foundation — implemented.** Course-level ownership, context snapshots, runtime identifiers, retained legacy history, database queue and recovery states. Covers new browser sessions, duplicate submission, lost response and worker restart. Generation conversations are recorded as separate runs.
2. **Shared assistant interface — implemented.** Outline, published lesson, draft overview and draft lesson; mode/context labels, selected passages with origin, persisted generation/cover cards and explicit content refresh. Preserves tab-specific composers and pending reply context. Draft discussion is read-only; its history and runtime thread are separate from generation runs and the published tutor.
3. **Draft editing and recovery.** Scoped editor tools, metadata and lesson changes, recoverable removal, image replacement, operation receipts, revision previews and undo. Verify isolation, stale quotes/revisions, edit/generation/approval conflicts, image failure, cancellation and recovery after a write whose response was lost.

Finish with a real local workflow on an isolated draft: change a quoted passage, add and remove a lesson, replace the cover, leave and reopen the page, and undo a change. Automated tests use fake model/image adapters; genuine checks remain explicit and bounded. The public demo milestone remains separate.
