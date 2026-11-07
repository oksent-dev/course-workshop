# Recoverable draft editing

The local draft assistant uses GPT-6.1 Sol to improve an existing draft. Ask from its generation overview or a lesson; a selected passage retains its source lesson after navigation. Published courses keep a separate, read-only tutor. Enable both local AI and course authoring, migrate the primary database, and restart `ruby bin/dev` after updating the application.

## User workflow

Ask for a specific change, such as clarifying an example, adding practice, removing a redundant lesson, reordering the course, or replacing its cover. Saved operations appear in the conversation with their revision and a **Review change** preview. Completed reading steps are grouped under **Assistant activity**. The assistant's answer is a summary; database receipts determine which changes actually succeeded.

**Undo this change** reverses the latest eligible operation. Repeated undo walks backward through the saved edits. Each undo creates a new revision and keeps the original record. Undo does not discard subsequent unrelated work: a later external edit or material mismatch makes it unavailable. There is no redo or whole-message rollback; a message containing several operations produces several independently recorded changes.

**Cancel reply** revokes further editor writes and cancels its pending cover request. Changes already saved remain visible and undoable after the request stops. A replacement cover also has its own cancel and retry actions. Leaving the page does not cancel accepted work. Reopening reconstructs messages, operation cards and image status from PostgreSQL.

## Scope and lifecycle

`LessonReplyJob` selects `Codex::Editor` for editor conversations and `Codex::Tutor` for published tutoring. The editor resumes the course/profile/editor thread. Generation remains a sequence of separate threads: the editor receives the saved topic, plan and current outline as a handoff, not a fabricated original dialogue. Lesson bodies are supplied for the current lesson or explicitly read through a scoped tool.

`bin/editor-mcp` receives a credential bound to an active exchange. Only its digest is stored in the database; its seven-minute expiry is checked on every tool call. Cancellation, completion and recovery revoke it. The runtime's filesystem sandbox remains read-only. Shell, other MCP servers, apps and plugins stay disabled; approval is enabled only for this thread's editor server. No tool accepts an arbitrary course ID, filesystem path, URL to execute, or publication instruction.

| Tool | Behavior |
| --- | --- |
| `get_authoring_guide`, `read_draft`, `read_lesson` | Read supported formats, this draft, categories and attached-image keys |
| `update_draft` | Change supplied title, description or category fields |
| `save_lesson` | Replace a complete lesson or append one; retain unaffected material and useful visuals |
| `remove_lesson` | Archive a lesson and normalize remaining positions |
| `reorder_lessons` | Include every active lesson ID exactly once |
| `revise_plan` | Revise the initial plan before lessons exist; require new human approval |
| `request_cover` | Queue a validated replacement through native image generation |
| `undo_change` | Undo the latest eligible change from this editor conversation |
| `refresh_course_view` | Record that the current revision is ready for display; no script or URL |

Material changes require a UUID request key and exact `expected_revision`. `DraftOperation` stores the result atomically with the change. Identical retries replay that receipt, including image queue requests; changed arguments under the same key fail. `AssistantActivity` can reconcile a missing tool response from the receipt without another mutation.

## Writer coordination and plans

`Drafts::Access` locks generation first, then course, for short state transitions. A pending editor exchange reserves the course across learner profiles. Initial generation, pending image work, external authoring, attachment imports, approval and another editor cannot overwrite it. Database transactions never span model inference. The UI explains the active operation; the server remains authoritative if an older tab still offers a button.

An awaiting, failed or cancelled plan can be revised only while no lessons exist and generation is stopped. Revising it clears approval and advances its attempt and revision, so old approval forms cannot start writing. Once lessons have been partially generated, finish or resume generation before editing them. Completed generations retain their original `plan` and `approved_plan`; later edits change the live lessons. The overview displays that current outline. Publication remains an explicit human action.

## Snapshots, images and recovery

`CourseChange` captures metadata, active lesson IDs/content/order, cover blob, and initial plan state before and after each material operation. Removed lessons are archived in place; their images and IDs remain recoverable. Undo verifies both the current revision and snapshot before restoring. External imports advance the course revision when they change content or an image.

`DraftCoverRequest` runs separately in Solid Queue. It preserves the previous cover until a new image passes `ImageUpload` validation and the revision check. The swap and its `CourseChange` commit together. Old and new blobs are retained by the change record, so attachment replacement cannot purge an image needed for undo. Cover failure or cancellation leaves earlier text edits intact. Retained history and assets currently have no automatic pruning policy; back up the database and local storage together.

Recovery revokes stale editor credentials, reconciles committed receipts and reads mapped Codex turns. It can restore a final answer without repeating saved edits. Image recovery checks for an already committed replacement first; otherwise it imports a completed image result. Unidentifiable results become uncertain after bounded checks and require explicit retry. A lost acknowledgement is never permission to blindly rerun an editing turn or image generation.

Each tab compares its displayed material version with the database version. A tool-requested refresh applies only to its recorded revision and is deferred while typing, quoting, selecting text, or inspecting an expanded preview. The permanent panel and composer survive Turbo refresh; a removed lesson returns to the course overview. A manual refresh remains available for later changes, including a newly finished cover, and when the assistant omitted the refresh tool.

## Verification

Automated tests exercise scoped writes, revision conflicts, idempotency, single-writer exclusion, stale selections, plan approval invalidation, recoverable removal, undo, image failure/cancellation, receipt reconciliation, native protocol configuration and browser interactions. They use fake inference and image adapters.

A separate bounded local check used real GPT-6.1 Sol on an isolated draft: quoted editing, lesson addition/removal/reordering, native cover replacement, reopening the conversation and browser undo. It did not publish or modify existing learning courses. Public demo deployment is a separate milestone.
