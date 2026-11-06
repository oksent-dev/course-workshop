# Generate a course from a topic

Open **Create a course** from the local library. Describe the topic, your current knowledge, and the outcome you want, select Polish or English, and request three to six lessons. **Generate course** starts a background job with GPT-6.1 Sol through the local Codex account. The result remains a draft for review and explicit approval.

## Local setup

Prepare the database with `ruby bin/rails db:prepare`. Configure the existing [local Codex runtime](local-ai.md) and enable both flags in the private `.env`:

```dotenv
LOCAL_AI_ENABLED=true
COURSE_AUTHORING_ENABLED=true
CODEX_EXECUTABLE=codex
```

On Windows, use an absolute path to the installed Codex executable when needed. Restart `ruby bin/dev` after changing configuration. Both PostgreSQL and the local application must remain running. The generator launches its own scoped MCP child process; it does not require registering a global MCP server.

The form explains that the topic and draft are sent to the model, that it can research online and save this draft, and that a cover uses the account's image allowance. Submitting it authorizes these operations for that generation. Course content language is independent of the interface language.

## State and recovery

`CourseGeneration` owns one reserved draft, a UUID submission key, topic, content language, requested lesson count, saved plan, status, attempt number, deadline, error code, and a temporary token digest. It does not store raw reasoning or model transcripts. Recent generations are listed on the creation screen, including after a browser reload.

| State | Meaning | Available action |
| --- | --- | --- |
| `queued` | Persisted and waiting for an Active Job worker | Cancel or inspect the draft |
| `running` | The current attempt owns scoped write access | Inspect progress or cancel |
| `completed` | The application checked the plan, lesson count, positions, titles and content format | Review and approve the draft |
| `failed` | Runtime failure, timeout or incomplete result | Resume the same draft |
| `cancelled` | Write access was revoked by cancellation | Resume the same draft |

The progress count means **lessons saved**, not a prediction of remaining time or an assessment of teaching quality. The page polls saved state and preserves keyboard focus when progress changes. A network error offers a manual refresh; leaving the page does not cancel generation.

Development uses the existing two-thread Async job executor. The queue is not durable across a Rails restart. Each model attempt has a ten-minute deadline; queued or running records older than their twelve-minute expiry become retryable failures when their status page is read. Restarting the application does not automatically restart model work. Resume explicitly after the old attempt expires.

Cancellation immediately marks the attempt cancelled and clears its token digest. Tool calls check this state within the generation's row lock, so writes serialized after cancellation are rejected. The runtime receives an interruption request when its cancellation check observes the change. An in-flight model request may take a short time to stop; already committed lessons remain saved.

Resume increments the attempt number and starts a fresh Codex thread with a new token. It reads the existing plan and lessons. Lessons are saved by their planned position, preserving their IDs even if a new request key is used. Old jobs cannot complete or cancel a newer attempt, and old MCP processes cannot write with an expired token. Resume does not start a second course.

## Persistence and completeness

Submission atomically creates the generation and its draft. Repeated delivery of the same UUID and inputs returns that generation; different inputs with the same key are rejected. A database unique index also protects concurrent submissions. Duplicate job delivery is guarded by the queued state and attempt number.

The model sets metadata and an ordered plan once. That plan must contain exactly the requested number of nonempty, distinct titles. The model then saves complete lesson bodies into those positions. Each mutation uses the existing `DraftOperation` receipt mechanism, inside a short transaction with the generation and course locks. There are no model or network calls inside database transactions.

`read_generation` includes all available category IDs and names, excluding the temporary `Drafts` placeholder. The instructions prefer an existing suitable subject, including broader categories and names in another language. `plan_course` accepts exactly one of `category_id` (reuse) or `category` (a new broad name when none fits). Names are whitespace-normalized and matched case-insensitively; a database unique index prevents concurrent case variants. Semantic matching is a model decision, not a deterministic synonym dictionary. Existing labels are preserved when the content language changes.

Completion requires every planned position exactly once, titles matching the plan, at least 200 characters per body, and the existing Markdown, image and learning-block validation. Educational accuracy, sufficient depth, and full browser math rendering still require review. The prompt requests examples, practice exercises and relevant primary-source links. The model can use live web search to check current or uncertain facts. Inline lesson images must already be attached; the lesson generator does not import them.

Successful completion atomically reserves an independent `CourseCoverGeneration` unless the course already has a cover. After commit, a separate job asks Codex to generate one illustration and stores its validated bytes in Active Storage. Progress keeps polling until both jobs settle. An image failure leaves the completed lessons ready for review and offers **Retry cover**. Approval does not wait for the image. Existing completed courses are not backfilled automatically; use the [cover importer](course-covers.md) for those.

Incomplete drafts remain hidden from the regular library. Ordinary authoring tools and approval cannot modify a generated draft until generation completes. Partial content can be inspected in the preview. Approval remains a separate action; neither the job nor its MCP tools can publish.

## Scoped MCP and runtime access

`bin/generation-mcp` differs from the general-purpose [authoring launcher](course-authoring.md). Its five tools have no caller-supplied course IDs:

| Tool | Purpose |
| --- | --- |
| `get_authoring_guide` | Content formats, limits and generation workflow |
| `read_generation` | This topic, saved plan, draft metadata, lesson outline and category catalog |
| `plan_course` | Set metadata, one category selection and ordered lesson titles once |
| `read_generated_lesson` | Read one saved lesson by planned position |
| `save_generated_lesson` | Insert or replace one lesson at its planned position |

The job passes a random per-attempt token and generation ID through the child process environment. PostgreSQL stores only the token digest. Every tool call checks local enablement, running state, expiry and the token before accessing content, including before replaying a receipt. The token is cleared on completion, failure or cancellation and never sent to the browser.

`Codex::Runtime` disables unrelated configured servers, apps, plugins, shell, file/image tools, memories and hooks. `Codex::CourseGenerator` enables only its scoped MCP allow list and live web search, pins `gpt-6.1-sol` with low reasoning effort, and requests a read-only sandbox. Its session-only MCP approval setting permits the writes authorized by the form; global Codex configuration is unchanged. The application does not grant unexpected interactive requests. The lesson tutor continues to disable all MCP tools and web search.

HTTP generation endpoints require both local feature flags, development/test, and loopback client and host addresses. Production rejects them regardless of flags. Local generations share the same workspace; this is not an account or multi-tenant permission system. Topics are filtered from HTTP logs. Development SQL logs and Codex runtime history can contain course material and local process configuration; keep them outside Git. Finished attempts no longer accept their tokens.

## Verification

Run `ruby bin/rails test:all`. Tests cover submission concurrency and duplicate delivery, the scoped stdio handshake, token revocation, disallowed tool arguments, invalid content and rollback, partial failure and resume without duplicated lessons, cancellation and late results, stale jobs, HTTP boundaries, PL/EN navigation, focus preservation and phone-width layouts. A fake generator uses the real MCP handlers; automated tests do not call a model.

For a real smoke check, submit a small course through the form, observe the saved plan and lesson count, reload the page, and review every lesson in the draft preview. Check its examples, exercise disclosures and source links. Approve when satisfied, then open the first lesson through the library. Generation was verified on Windows with Codex App Server `0.166.0-alpha.6` and `gpt-6.1-sol`, using a four-lesson Active Record course. The generated draft was left for review; automated browser tests cover approval and opening the first published lesson.

Protocol references: [Codex App Server](https://learn.chatgpt.com/docs/app-server) and [MCP configuration](https://learn.chatgpt.com/docs/extend/mcp).
