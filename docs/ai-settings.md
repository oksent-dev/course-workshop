# Local AI settings

Open the gear to the right of the language selector. Settings are shared by the local application and stored in PostgreSQL. They require local AI to be enabled and the same development/test and loopback checks as the assistant. Production does not expose this page or its update endpoint.

Codex is the fixed provider. **GPT-6.1 Sol** (`gpt-6.1-sol`) remains the application default. The model picker reads the authenticated runtime's paginated `model/list`, using its IDs and display names instead of a hard-coded catalog. It includes visible text-capable models and the application default when advertised. Availability, image support and account limits can differ between models. See the official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server).

Loading the catalog does not start inference. If Codex is unavailable, the form retains the saved selection and permits a style-only update. A changed model must appear in the current catalog. Each execution verifies availability again and fails explicitly if the selected model is missing; it never silently substitutes the default. Reasoning effort uses `low` when supported, otherwise the model's advertised default or first supported effort.

## When changes apply

| Accepted work | Settings used |
| --- | --- |
| New course request | Current settings, captured once at submission |
| Plan, lessons, illustrations, initial cover, resume and retries | The original course request's settings |
| New tutor or draft-editor message | Current settings captured with that message |
| Retry or recovery of that message | The original message's settings |
| Replacement cover and its retries | The requesting editor message's settings |

`AiConfigured` captures an immutable `ai_configuration` JSON snapshot. `CourseGeneration`, `Exchange`, `CourseCoverGeneration` and `DraftCoverRequest` retain it; each `AiRun` also records the execution configuration. Duplicate submission keys keep the original request and snapshot. Saving settings does not cancel or rewrite accepted work. Optimistic locking prevents an older settings tab from silently overwriting a newer save.

## Tone and style

The optional instruction accepts up to 1,000 characters, trims surrounding whitespace and rejects null bytes. An empty value clears the preference. Use it for explanation style, tone and examples. Course language, required visuals, validation, tool permissions and approval rules remain controlled by the application.

A stable developer instruction defines this scope. Every turn supplies the accepted request's `response_style`, including an explicit empty string for reset. The current value replaces earlier preferences. This avoids relying on `thread/resume` to rewrite thread-creation instructions: a native runtime check retained the initial style when only the resume parameter changed. Tutor and editor follow-ups retain their runtime thread and history while carrying the new request's model and style.

The instruction is sent to Codex with the task and can remain in local database snapshots and Codex history. Clearing the current preference does not erase historical requests. HTTP parameter logging filters this field; development SQL logs can still contain it. Do not enter credentials or secrets. The bounded text is escaped in forms and never rendered as HTML.

## Course provenance

The course stores its original generation provider, model ID and display name. The outline, draft preview and generation overview display this information. Later editing with another model does not rewrite the original generation credit; execution snapshots record those later choices. The model is the Codex orchestrator, not a claim about the underlying image-generation model version.

The migration backfills known form-generated courses and existing AI requests with the previously fixed Sol configuration. Seeded or externally authored courses without known generation provenance remain unlabelled. The style instruction is not exposed in course metadata.

After updating, run `ruby bin/rails db:prepare` and restart `ruby bin/dev` so the queue worker loads the new code. Subsequent preference changes take effect without restarting the worker.

## Verification

Automated checks cover access restrictions, catalog failure and recovery, stale forms, invalid selections, style limits/reset, immutable task snapshots, retries, model availability, generation provenance, and Polish/English navigation at narrow widths. Protocol checks exercise model and style propagation through tutor, editor inheritance, course and image execution.

A bounded native check on 2026-11-07 changed from Sol to another advertised model in the same tutor thread, changed its response style, then cleared the preference. Each answer reflected the accepted request. The temporary course was isolated from existing learning material. Desktop, 320 px and 200% browser zoom were also checked.
