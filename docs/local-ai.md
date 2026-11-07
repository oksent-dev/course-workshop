# Local lesson conversations

A lesson can send its current text, course outline and a question to a local Codex App Server. The tutor uses **GPT-6.1 Sol** (`gpt-6.1-sol`) with low reasoning effort. A follow-up resumes the stored Codex thread. Saved history is shared across a course's lessons for the same learner profile and mode. The tutor is read-only; draft editing and panels outside published lessons are later features.

## Enable the tutor

Install Codex CLI and sign in using `codex login`. The account must list `gpt-6.1-sol` in App Server's `model/list` response. The adapter checks this before starting a turn and does not substitute another model.

Add these settings to the private `.env`:

```dotenv
LOCAL_AI_ENABLED=true
CODEX_EXECUTABLE=codex
```

`CODEX_EXECUTABLE` is one executable path, not a shell command or a list of arguments. On Windows, an absolute path to `codex.exe` is recommended, especially if a package-manager shim points to an older CLI. Use the executable available on your machine; do not commit a personal installation path.

A desktop update can replace a versioned runtime directory. If generation reports an unavailable runtime, confirm that the configured executable still exists, update the private path if needed, and restart Rails before resuming the saved generation.

Then run:

```sh
ruby bin/rails db:prepare
ruby bin/dev
```

Open the application through `http://localhost:3000` or `http://127.0.0.1:3000`. In a published lesson, use the floating **Ask about this lesson** button in the bottom-right corner. The panel opens beside the reading surface without blocking it. Enter a question and send it; the app shows a queued, running or recovering state, then the answer. **Cancel reply** requests interruption. Closing the panel or navigating does not cancel a reply; any lesson in the same course shows its result. A different course has a separate history.

Select text within the lesson body and choose **Ask about this passage**, or press **Alt+Enter** while the selection action is visible. The passage appears above the question field. You can remove it or select a different passage before sending. Selection alone never sends a request to the model. Each question may include one passage of up to 2,000 characters; longer selections show a prompt to choose a shorter passage. The full lesson still accompanies the question.

Use **Expand conversation**, beside the close button, for a larger conversation window that can cover the lesson. The same button restores the compact panel. Resizing preserves the conversation, any pending reply, the question draft, and its quote. The size is retained when reopening the panel on the same page; another lesson starts compact. The transition respects the system's reduced-motion preference.

**Escape** or the close button returns focus to the launcher without moving the reading position. Closing and reopening preserves the unsent question and passage on the current page. Navigating or reloading still clears this unsent draft; saved exchanges remain in the course history. Preserving the composer across navigation belongs to the next interface stage. The selected passage is shown with its saved question and is not automatically attached to a later question. The panel fits narrow screens and follows the visible viewport when the on-screen keyboard reduces available space.

Development uses Solid Queue with a separate PostgreSQL queue database and worker. `bin/dev` starts the worker automatically. Each tutor connection has a three-minute deadline. Queued requests survive downtime; interrupted requests are reconciled without automatically repeating inference.

Set `LOCAL_AI_ENABLED=false` and restart Rails to disable the integration.

## Access and data boundary

The server requires all of the following for every conversation endpoint: development (or test) environment, explicit enablement, a loopback client IP, and a localhost/loopback host. The background job checks enablement again. Production rejects these routes even if the flag is accidentally enabled. This local boundary is not a user authentication system: do not expose the development server through a tunnel or reverse proxy.

Rails owns the conversation and exchange records in PostgreSQL. With the default development setting `LOCAL_PROGRESS_ENABLED=true`, loopback requests use the shared local learner profile, including after browser restart or cookie removal. With that setting disabled, the existing encrypted, persistent learner cookie identifies a separate browser profile; losing it starts a new identity. Neither mode is an account or synchronization service.

The migration retains every legacy lesson conversation, message and runtime thread link. On a request with a matching old session key, only that identity's legacy conversations for this course are associated with the current profile and included in its history. Unidentified legacy rows stay in the database; they are not silently assigned to the shared profile. Tutor and editor histories are separated by mode. Publishing a draft will not expose its private editing transcript to readers.

Each exchange stores the question, immutable course/outline/revision and lesson snapshot, optional passage, response language, answer and outcome. The passage is user-supplied text, not an independently verified reference. A unique partial index permits only one queued, running or recovering exchange per conversation. A per-submission UUID makes repeated HTTP delivery idempotent; changing the question or passage creates a new key. Cancellation and completion are serialized so a late answer cannot replace a cancelled exchange. Navigating while a reply runs does not change its target lesson.

The model receives this explicit lesson snapshot and question. Codex stores its own thread history using the existing local Codex account. The application does not copy login credentials or expose Codex thread identifiers to the browser. Questions and lesson content leave the machine for model inference; “local” refers to the runtime and application, not the model.

The adapter overrides project instructions, disables shell execution, image viewing, search, memories, hooks, multi-agent work, apps, plugins, and configured MCP servers, and requests a read-only sandbox. Unexpected interactive tool requests fail the exchange. This tutor explains supplied material; the separate [course-authoring MCP server](course-authoring.md) is available to local clients but is not connected to lesson conversations. [Course generation](course-generation.md) uses its own scoped writing tools and web research. Codex configuration and protocol are evolving, so re-run the smoke check after upgrading the CLI.

Question and selected-passage parameters are filtered from request logs. Development SQL logs and Codex session storage can still contain conversation content; these are local runtime data and must remain outside Git. Runtime exception details are not shown in the UI. Questions, quoted passages, and answers are escaped plain text; Markdown rendering is a separate reader feature. The tutor receives the passage as learning material, with an instruction to focus the current answer on it while retaining the full lesson context.

## Durable jobs and recovery

Run `ruby bin/rails db:prepare` after updating the checkout, then restart `ruby bin/dev`. Development has a primary database and `course_workshop_development_queue`. Back up both together with local Active Storage files when preserving a development installation.

The worker can also run separately:

```sh
ruby bin/jobs --mode async
```

This is Solid Queue's threaded supervisor, including its database persistence, not Active Job's in-memory Async adapter. Native Windows does not support the default forked supervisor. The recurring `AiRecoverySweepJob` runs every minute. To check saved requests immediately after restarting the worker:

```sh
ruby bin/rails runner "AiRecoverySweepJob.perform_now"
```

The sweep re-enqueues accepted requests that have no live queue job. A crash between committing a request in the primary database and enqueueing in the queue database is therefore recoverable. A duplicate queue delivery cannot claim an already-started request. Waiting requests have no downtime expiry. No work runs while the computer or worker is stopped.

Each started reply, generation step and image attempt has an `AiRun`. It stores the Active Job ID, operation key, submission timestamp and request marker, runtime thread/turn IDs, final item IDs and recovery lease. IDs are recorded before/after the relevant protocol calls; no application transaction spans model inference.

Recovery begins when the queue reports a failed execution or the eight-minute run lease expires. A recovery claim lasts one minute; history reads have a 30-second deadline. At most three history checks are attempted. Recovery only reads threads mapped to the application; it never lists or imports unrelated account conversations.

- A completed reply is imported by its recorded turn ID. If the `turn/start` acknowledgement was lost, the persisted application marker in the user message identifies the turn. Item IDs prevent duplicate answer fragments.
- Generation first checks committed plans, lessons and attachments. It revokes old tool access and advances only a saved checkpoint, preserving the plan approval boundary. A completed image can be restored from its recorded turn when validated image bytes remain available.
- An interrupted turn or failure before submission becomes a visible failure. A result that cannot be established becomes **uncertain**, retaining the question and saved material. It is not automatically submitted again. Explicit resubmission/resume may perform unfinished work again.
- Cancelling stops further work and prevents late output from overwriting the cancellation. Recovery does not undo committed material.

For a missing tutor thread, the next explicit question starts a replacement with the current snapshot and up to 12 recent completed exchanges, each saved answer bounded to 4,000 characters. The full application transcript is retained. A transient resume error does not create a replacement. An uncertain or interrupted tutor run retires its thread from future reuse while retaining its identifiers in `AiRun`.

The application does not promise exactly-once execution across a runtime/network crash. It provides idempotent job claims, persistent operation receipts for generation tools, bounded reconciliation and an explicit uncertain outcome. Restoring Codex history is supplemental; losing runtime storage never deletes PostgreSQL messages.

## Verification

Automated tests use fake adapters and a small JSON-lines process. They cover course/profile/mode isolation, immutable context, preserved legacy records, duplicate submissions/jobs, cancellation, paginated history, lost acknowledgements, missing threads, saved generation checkpoints and bounded unknown outcomes. Widget tests cover focus, selection, quotes, unsent drafts, network failure, mobile layout and Turbo navigation. They do not require a Codex login or make model requests.

```sh
ruby bin/rails test:all
```

For a manual check with the seeded course:

1. Open **Średnia i mediana**.
2. Ask why changing 12 to 32 leaves the median unchanged.
   Alternatively, select the passage about the median, open the selection action, and ask why it stays unchanged. Confirm that the quote appears before sending and beside the saved question.
3. Ask what the mean was before that change.
4. Reload the lesson and confirm both answers remain.
5. Open another lesson in the same course and confirm the saved history remains, with the original lesson labels. Open a different course and confirm its history is separate. With the default local profile, repeat in a new browser session.
6. Disable local AI, restart Rails, and confirm the chat is hidden and direct requests return 404.

The integration was checked on Windows with Codex App Server `0.166.0-alpha.6` and the requested `gpt-6.1-sol` model. Protocol references: [App Server](https://learn.chatgpt.com/docs/app-server) and [Codex configuration](https://developers.openai.com/codex/config-reference). The client uses stdio JSON lines and the initialize → thread/start or thread/resume → turn/start lifecycle. It renders final agent messages after turn completion and polls Rails for the saved outcome.

The durable-worker check on 2026-11-07 used App Server `0.167.0-alpha.3.2` and an isolated learner profile. A request was enqueued from a process that exited before the worker started. The worker obtained one real Sol answer, then was forcibly stopped before the Rails answer commit. A new worker recovered that answer from the recorded turn without starting another model turn. Only that test run's lease was advanced to avoid the eight-minute wait. No course material was changed.
