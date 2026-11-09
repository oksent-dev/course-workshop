# Development setup

## Requirements

- Ruby **4.0.9** and Bundler **4.0.20**; see `.ruby-version` and `Gemfile.lock`.
- Node.js **24** and npm **11**; see `.node-version` and `package.json`.
- Docker with Compose for PostgreSQL **18**.
- libvips for image validation and variants.
- Chrome or Chromium for browser tests.

On Windows, use RubyInstaller with MSYS2/Devkit. Native gems may install build dependencies during `bundle install`. Make `ruby`, `bundle`, `node`, `npm` and `docker` available on `PATH`. Reopen the terminal after installing them. Install libvips through the RubyInstaller toolchain or provide a compatible libvips library; the production Dockerfile and Linux CI install it explicitly.

For a read-only preview with fewer host dependencies, use [the isolated Docker demo](demo.md) instead.

## First start

From a checkout:

```sh
ruby bin/setup
ruby bin/dev
```

`bin/setup` preserves an existing `.env`. Otherwise it copies `.env.example` and generates a random local database password. It installs Ruby/JavaScript dependencies, starts PostgreSQL, prepares the primary/queue databases, imports the development example course, and builds browser assets. AI is disabled by default; setup makes no model requests.

Open [http://localhost:3000/pl](http://localhost:3000/pl) or [http://localhost:3000/en](http://localhost:3000/en). The development seed is the three-lesson Polish course **Statystyka na co dzień**. To add the two complete demo courses without disabling local features:

```sh
ruby bin/rails demo:prepare
```

`bin/dev` runs Rails, a Solid Queue worker, and the JavaScript/CSS watchers. Stop the group with Ctrl+C. Keep the worker and database running while local AI is working; closing the browser does not cancel an accepted request.

## Configuration

| Variable | Purpose |
| --- | --- |
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD` | Local database connection; defaults and placeholders are in `.env.example` |
| `LOCAL_AI_ENABLED` | Enables local assistant/settings access when exactly `true` |
| `COURSE_AUTHORING_ENABLED` | Enables local drafts/MCP; both AI flags are required for form generation |
| `CODEX_EXECUTABLE` | Codex executable or `codex-desktop` for Windows desktop runtime discovery |
| `LOCAL_PROGRESS_ENABLED` | Shared local progress by default in development; set `false` for per-browser profiles |
| `DEMO_MODE` | Enables the guarded catalog and disabled previews; overrides local AI/authoring and shared-progress flags |

Restart Rails and its worker after environment changes. Settings changed through the application apply to new requests without a restart. Start with [local AI setup](local-ai.md) before enabling generation. [AI settings](ai-settings.md) describe model, effort and style selection; [course generation](course-generation.md) covers the approval workflow.

For a hosted demo, use the separate production variables and release steps in [demo.md](demo.md#vercel-deployment-preparation). Do not reuse local authoring credentials or a development database.

## Update an existing checkout

```sh
bundle install
npm ci
ruby bin/rails db:prepare db:seed
ruby bin/dev
```

`db:seed` refreshes the development example in place. Under `DEMO_MODE=true`, it imports the packaged bilingual catalog instead. Both retain seeded lesson IDs. See [demo.md](demo.md) for the reserved slugs and overwrite boundary.

## Checks

```sh
ruby bin/rails test
ruby bin/rails test:system
ruby bin/rails zeitwerk:check
ruby bin/rubocop
ruby bin/brakeman --no-pager
ruby bin/bundler-audit
npm audit
```

Tests use `course_workshop_test`, fake AI/image adapters and headless Chrome. They require no Codex account or model allowance. Run test processes sequentially against this database; concurrent suites can interfere through fixtures. To select one browser test file, use `ruby bin/rails test test/system/demo_test.rb`; `test:system` runs the full browser suite.

The [CI workflow](../.github/workflows/ci.yml) runs these checks on Linux. A separate job builds the production demo against a fresh PostgreSQL volume and runs HTTP smoke checks. The real-runtime checks described in the AI guides are historical manual verification, not part of CI.

## Common problems

| Symptom | Check |
| --- | --- |
| Port 5432 is occupied | Change `POSTGRES_PORT` in `.env` before starting the database |
| PostgreSQL rejects the password after editing `.env` | The existing Docker volume retains its original database password; editing the file does not rotate it |
| Images fail to import | Check libvips availability, supported formats, the 5 MB limit and the 20-million-pixel limit |
| Styles or learning blocks do not load | Run `ruby bin/rails javascript:build tailwindcss:build`; inspect the browser network requests |
| A model request stays queued | Keep `bin/dev` running, inspect the worker output and follow [recovery commands](local-ai.md#durable-jobs-and-recovery) |
| Codex disappears after a Windows update | Use `CODEX_EXECUTABLE=codex-desktop` rather than a version-specific desktop path |
| Demo forms stay disabled locally | Check `DEMO_MODE` and restart the app after changing it |

## Data and backups

Development stores application and queue data in PostgreSQL, with a named Docker volume, and uploaded image bytes in `storage/`. Preserve the primary database, queue database, storage directory and encryption secrets together when backing up a local installation. Demo media is bundled with the image; demo progress still requires its PostgreSQL volume and stable `SECRET_KEY_BASE`.

`.env*`, credentials keys, logs, temporary files, runtime uploads and dependencies are ignored by Git and excluded from the production image where applicable. Do not attach them to public issues. Removing a database volume destroys its contents; ordinary `docker compose stop` preserves it.
