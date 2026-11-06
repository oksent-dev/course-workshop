# Local course authoring through MCP

Course Workshop exposes nine MCP tools over stdio. A local client can read categories and courses, create a draft, replace its metadata, append or revise lessons, and reorder them. A draft stays outside the library until a person reviews and approves it in the application. The lesson tutor remains separate and cannot call these tools.

## Start and connect

Prepare the database, then start the server with explicit authoring enablement:

```sh
ruby bin/rails db:prepare
COURSE_AUTHORING_ENABLED=true ruby bin/mcp
```

In PowerShell, set `$env:COURSE_AUTHORING_ENABLED = "true"` before running `ruby bin/mcp`. A client normally launches this process automatically. No Rails HTTP server is needed for MCP; PostgreSQL must be running. The launcher loads configuration from the app's checkout, so it can be invoked with an absolute path from another workspace.

Example Codex configuration (replace the installation paths):

```toml
[mcp_servers.course_workshop]
command = "C:/Ruby40-x64/bin/ruby.exe"
args = ["C:/path/to/course-workshop/bin/mcp"]
cwd = "C:/path/to/course-workshop"
startup_timeout_sec = 30
tool_timeout_sec = 30

[mcp_servers.course_workshop.env]
RAILS_ENV = "development"
COURSE_AUTHORING_ENABLED = "true"
```

Alternatively, register the launcher using the CLI:

```sh
codex mcp add course_workshop --env COURSE_AUTHORING_ENABLED=true --env RAILS_ENV=development -- ruby /absolute/path/to/course-workshop/bin/mcp
```

Use an absolute Ruby executable path if the client does not inherit your shell's PATH. Keep machine-specific configuration and database credentials outside this repository. Tool approval remains a client policy: write tools are declared as mutations. A Codex session using approval policy `never` cannot run a tool that its MCP policy requires approval for. Use the client's normal approval flow; registering a server alone does not approve writes.

To use the local preview, add `COURSE_AUTHORING_ENABLED=true` to the private `.env`, restart `ruby bin/dev`, and open **Course drafts** from the library. This UI shows the 50 most recently updated drafts. Review every lesson, then select **Approve and add to library**. Approval applies only to the revision shown by the form. Concurrent edits require another review. Approval is a database state change, not a deployment or internet publication.

## Tools and result contract

All input schemas reject unknown properties. Success responses contain both JSON text and the same object in `structuredContent`; the server validates output schemas. IDs are positive database integers, stable across title changes and reordering. Slugs are set at creation and remain the reader URL after approval.

| Tool | Required input | Result |
| --- | --- | --- |
| `get_authoring_guide` | None | Supported Markdown, block formats, limits, and retry rules |
| `list_categories` | None | Existing category IDs and names, excluding the reserved `Drafts` placeholder |
| `list_courses` | None; optional `status`, `after_id`, `limit` | Course summaries and `next_after_id`; default 20, maximum 50 |
| `read_course` | `course_id` | Course metadata, revision, and ordered lesson summaries |
| `read_lesson` | `course_id`, `lesson_id` | Course metadata, lesson body, and attachment keys/descriptions |
| `create_course_draft` | `request_key`, `slug`, `title`, `description`, `language`, and exactly one of `category_id` or `category` | Newly created draft at revision 0 |
| `update_course_draft` | `request_key`, `course_id`, `expected_revision`, `title`, `description`, `language`, and exactly one of `category_id` or `category` | Updated metadata and revision |
| `save_draft_lesson` | `request_key`, `course_id`, `expected_revision`, `title`, `body`; optional `lesson_id` | Appended or updated lesson and new course revision |
| `reorder_draft_lessons` | `request_key`, `course_id`, `expected_revision`, `lesson_ids` | New order and course revision |

`status` accepts `all`, `draft`, or `published`. Metadata updates replace the supplied fields; lesson updates replace the entire title and body. Omit `lesson_id` only when appending. Reordering requires every existing lesson ID exactly once. It preserves IDs, temporarily moves positions out of the target range, and applies the new contiguous order in one transaction.

Read `list_categories` before selecting a subject. Reuse a suitable `category_id`, even when its label is in another language or describes a broader subject. Supply `category` as a new broad name only when none fits. Whitespace and case variants reuse the existing category; a database index protects concurrent creation. Course responses include both `category_id` and the unchanged display name. Semantic synonym matching remains the author's/model's responsibility. MCP authoring does not automatically generate images; automatic covers belong to the [form workflow](course-generation.md).

## Example calls

Invoke these names through your client's `tools/call` support. Generate a new UUID for each distinct write and use the IDs and revisions returned by the server.

```json
{"name":"create_course_draft","arguments":{"request_key":"56c1d7ca-feba-4c44-9338-017919d08026","slug":"probability-basics","title":"Probability basics","description":"Reason about simple events.","language":"en","category":"Mathematics"}}
```

After reading the returned `course.id` and `course.revision`, append a lesson (the values below are illustrative):

```json
{"name":"save_draft_lesson","arguments":{"request_key":"441b48dc-6614-405d-a920-b6a421053dda","course_id":42,"expected_revision":0,"title":"Events and outcomes","body":"## A fair coin\n\nThe probability of heads is one half."}}
```

To revise that lesson, include its returned `lesson.id` and the latest course revision. Then use `read_course` and `read_lesson` to verify the result. A suitable client prompt is:

> Read the authoring guide and category catalog. Reuse a suitable category, creating a new one only if none fits. Create a draft with two short lessons about probability, then revise the first lesson with a fair-coin example. Keep the lesson IDs stable, verify the result, and leave the course as a draft.

## Retries and concurrent edits

Every write uses a UUID `request_key`. `DraftOperation` stores a canonical argument fingerprint and the result in the same PostgreSQL transaction as the mutation. An identical retry, including one from another process, returns the original result without another write. JSON object ordering is not significant. Reusing a key for different input returns `request_conflict`.

Failed mutations roll back their receipt and all record changes, including newly created categories. A corrected request can be submitted after a validation failure. After an uncertain network failure, first repeat the exact original request and key; do not guess whether it committed.

Edits lock the course row and compare `expected_revision`. Every successful edit or approval increments the course revision once. A stale revision returns `revision_conflict`; read current content, reconcile the intended edit, and use a new key. Replayed responses are historical receipts, so call `read_course` for current state. Receipts remain in the database without automatic expiry.

Tool-level domain errors set `isError: true` and return `code` and `message`: `disabled`, `not_found`, `not_draft`, `generation_incomplete`, `invalid_content`, `invalid_category`, `invalid_order`, `revision_conflict`, `request_conflict`, or `conflict`. SDK schema-validation errors also use `isError: true` with a text explanation. Unexpected internal errors do not include raw application exceptions in tool responses.

Drafts owned by an unfinished [course generation](course-generation.md) reject ordinary edits and approval with `generation_incomplete`. Resume them from the generation screen. The generator has its own narrower server, bound to one draft and one attempt; its process configuration is not a replacement for the general-purpose launcher above.

## Content and access boundaries

Titles allow 160 characters, descriptions 2,000, categories 80, and lesson bodies 40,000. A draft supports at most 60 lessons. Languages use two- or three-letter lowercase codes. The existing [Markdown and image](lesson-content.md) and [learning-block](learning-blocks.md) rules apply to previews and approved courses. Server validation checks block formats and limits; full KaTeX rendering and educational correctness still require review in the preview. Raw HTML is escaped. Exercise text follows the same image validation as the surrounding lesson.

Image references must resolve to attachments on that lesson. MCP does not read local paths, import files, download images, run code, access conversations or learner progress, delete content, or publish courses. A local operator can attach an image with the existing Rails import task before adding its reference to the draft.

The server is opt-in, runs only in development/test, and exposes no HTTP MCP endpoint. Production refuses to start it even when enabled. The preview and approval routes additionally require loopback client and host addresses; ordinary course, lesson, conversation, and completion routes only resolve published courses.

Stdio grants access through the local process launch, not an API token or an account system. All enabled local clients share the same draft workspace and can read course content. Launch only trusted clients. The process has the checkout's database access; application checks constrain its tools, not the OS account. Logs go to stderr and stdout is reserved for MCP JSON lines. Requests are capped at 512 KiB. Database data, receipts, local configuration and Codex history remain outside Git. A model client can send returned course content to its inference provider.

## Verification

Run `ruby bin/rails test:all`. Tests cover the real stdio handshake and launcher refusal, tool schemas, two-lesson drafting, correction and reordering, repeated and concurrent requests, stale revisions, rollback, content validation, published/foreign record rejection, hidden drafts, local/production boundaries, human approval, and PL/EN browser navigation.

For an end-to-end check, connect a local Codex session, use the example prompt, inspect the resulting draft in the app, and verify that it remains absent from the normal library. This requires a configured Codex account and approval for the write tools. Automated tests do not call a model.

The workflow was verified on Windows with Codex App Server `0.166.0-alpha.6` and `gpt-6.1-sol`. The model created two lessons and revised the first without changing its ID, leaving a draft at revision 3. Browser verification covered the rendered formula, revised example, exercise disclosure, and absence from the library. The smoke session received explicit authorization for its limited tool allow list; no global approval settings were changed.

References: [MCP Ruby SDK tools](https://ruby.sdk.modelcontextprotocol.io/server/tools/), [stdio transport](https://ruby.sdk.modelcontextprotocol.io/server/transports/), and [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp).
