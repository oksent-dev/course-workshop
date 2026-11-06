# Local lesson conversations

A lesson can send its current text and a question to a local Codex App Server. The tutor uses **GPT-6.1 Sol** (`gpt-6.1-sol`) with low reasoning effort. A follow-up resumes the stored Codex thread. Each lesson and browser session has a separate conversation.

## Enable the tutor

Install Codex CLI and sign in using `codex login`. The account must list `gpt-6.1-sol` in App Server's `model/list` response. The adapter checks this before starting a turn and does not substitute another model.

Add these settings to the private `.env`:

```dotenv
LOCAL_AI_ENABLED=true
CODEX_EXECUTABLE=codex
```

`CODEX_EXECUTABLE` is one executable path, not a shell command or a list of arguments. On Windows, an absolute path to `codex.exe` is recommended, especially if a package-manager shim points to an older CLI. Use the executable available on your machine; do not commit a personal installation path.

Then run:

```sh
ruby bin/rails db:prepare
ruby bin/dev
```

Open the application through `http://localhost:3000` or `http://127.0.0.1:3000`. In a lesson, expand **Ask about this lesson**, enter a question, and send it. The app shows a queued or running state, then the answer. **Cancel reply** requests interruption. Closing the panel or navigating to another lesson does not cancel a reply; reopen the original lesson to see its result.

The development process uses a two-thread Active Job async executor. It does not require a separate worker. Jobs are not durable across a Rails restart: an unfinished exchange becomes retryable after five minutes when its conversation is loaded again. Each Codex connection has a three-minute deadline. Failed questions are not automatically retried.

Set `LOCAL_AI_ENABLED=false` and restart Rails to disable the integration.

## Access and data boundary

The server requires all of the following for every conversation endpoint: development (or test) environment, explicit enablement, a loopback client IP, and a localhost/loopback host. The background job checks enablement again. Production rejects these routes even if the flag is accidentally enabled. This local boundary is not a user authentication system: do not expose the development server through a tunnel or reverse proxy.

Rails owns the conversation and exchange records in PostgreSQL. An encrypted session cookie holds a random browser key; lookups always include that key and the current lesson. Clearing the cookie starts a new browser identity. Existing records remain in the local database. There is no account synchronization or conversation-management UI yet.

Each exchange stores the submitted question, a snapshot of the lesson and its course title, the response language, the final answer, and its outcome. A unique partial index permits only one queued or running exchange per conversation. A per-submission UUID makes repeated HTTP delivery idempotent. Cancellation and completion are serialized with row locks, so a late answer cannot replace a cancelled exchange.

The model receives this explicit lesson snapshot and question. Codex stores its own thread history using the existing local Codex account. The application does not copy login credentials or expose Codex thread identifiers to the browser. Questions and lesson content leave the machine for model inference; “local” refers to the runtime and application, not the model.

The adapter overrides project instructions, disables shell execution, image viewing, search, memories, hooks, multi-agent work, apps, plugins, and configured MCP servers, and requests a read-only sandbox. Unexpected interactive tool requests fail the exchange. This tutor currently explains supplied material; research and course-writing tools require separate integration work. Codex configuration and protocol are evolving, so re-run the smoke check after upgrading the CLI.

Question parameters are filtered from request logs. Development SQL logs and Codex session storage can still contain conversation content; these are local runtime data and must remain outside Git. Runtime exception details are not shown in the UI. Questions and answers are escaped plain text; Markdown rendering is a separate reader feature.

## Verification

Automated tests use a fake tutor and a small local JSON-lines process. They cover lesson context, follow-up threads, browser and lesson isolation, blocked HTTP calls, idempotency, concurrency constraints, cancellation, stale work, runtime failure, escaping, and the browser interaction. They do not require a Codex login or make model requests.

```sh
ruby bin/rails test:all
```

For a manual check with the seeded course:

1. Open **Średnia i mediana**.
2. Ask why changing 12 to 32 leaves the median unchanged.
3. Ask what the mean was before that change.
4. Reload the lesson and confirm both answers remain.
5. Open another lesson and confirm it has a separate conversation.
6. Disable local AI, restart Rails, and confirm the chat is hidden and direct requests return 404.

The integration was checked on Windows with Codex App Server `0.166.0-alpha.6` and the requested `gpt-6.1-sol` model. Protocol references: [App Server](https://learn.chatgpt.com/docs/app-server) and [Codex configuration](https://developers.openai.com/codex/config-reference). The client uses stdio JSON lines and the initialize → thread/start or thread/resume → turn/start lifecycle. It renders final agent messages after turn completion and polls Rails for the saved outcome.
