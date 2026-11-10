# Public demo

Hosted demo: [Polish](https://course-workshop-solvepatch.vercel.app/pl) · [English](https://course-workshop-solvepatch.vercel.app/en).

The demo includes **Statystyka przy kawie** (Polish) and **Statistics over coffee** (English), each with four complete lessons. Both use an explicitly invented dataset of five coffee waiting times: 4, 6, 8, 10 and 32 minutes. Interface language and course language remain independent.

| Lesson | Material to explore |
| --- | --- |
| A measurement rule | Local photograph, caption, source attribution, table, quotation, exercise |
| Mean and median | KaTeX formula, comparison table, highlighted Ruby, exercise |
| Spread and interpretation | Local chart with descriptive alternative text and equivalent data table, formula, exercise |
| Communicating a result | Accessible Mermaid flowchart, general Ruby median function, final exercise and a small independent project |

Answers expand without a model call. Lesson completion, undo, resume, category filters, and language switching work normally. The charts are static illustrations; interactive Chart.js lessons are not implemented.

## Run an isolated production demo

With Docker running, execute from the repository root:

```sh
ruby bin/demo
```

Open [http://localhost:3001/pl](http://localhost:3001/pl) or [http://localhost:3001/en](http://localhost:3001/en). The command creates a private, ignored `.env.demo` with random database and cookie-signing secrets if it does not exist, then builds and starts the production image and a separate PostgreSQL service. It preserves an existing configuration. Set `DEMO_PORT` in `.env.demo` to change the default port.

The database is not exposed on a host port. Its named volume belongs to the `course-workshop-demo` Compose project. This stack does not use the development database, storage directory, Codex session, or model settings. The first start prepares the schema and imports the two courses. Keep `.env.demo` stable to preserve database access and browser identities between restarts.

Compose also sets `DEMO_LOCAL_HTTP=true` for this localhost preview. This disables the TLS-proxy assumption and HTTPS redirect only in demo mode, while restricting accepted hosts to localhost and loopback addresses. It keeps browser form origins and CSRF checks consistent over local HTTP. Do not enable this setting on Vercel or another public host; hosted deployments keep HTTPS and secure cookies.

```sh
docker compose --env-file .env.demo -f compose.demo.yml stop
docker compose --env-file .env.demo -f compose.demo.yml up -d --wait
docker compose --env-file .env.demo -f compose.demo.yml exec web ruby bin/rails demo:prepare
docker compose --env-file .env.demo -f compose.demo.yml exec web ruby bin/check-demo
```

The prepare command refreshes owned course content in place. It does not delete unrelated courses, lesson progress, or existing lesson IDs. The two `demo-*` slugs are reserved for this catalog: edit their Markdown sources rather than authoring unrelated courses under those slugs. Re-importing intentionally replaces edits to these eight lessons. Removing the database volume destroys demo progress; stopping the stack does not.

`bin/check-demo` verifies the running application over HTTP, including CSRF-protected requests to disabled endpoints and separate progress cookies. It creates isolated anonymous test profiles and reverses its completion change. CI runs it against a freshly built production container. Browser tests additionally verify client-side math, diagram and image rendering.

## Feature gate

Set **`DEMO_MODE=true`** in the server environment and restart the application. Only the exact value `true` enables it. This is a server configuration flag, not a request parameter or browser preference.

| Surface | Demo behavior |
| --- | --- |
| Library, outline, lessons | Only the two reserved published courses are accessible, including direct URLs |
| `/pl/generations/new`, `/en/generations/new` | Visible form inside a disabled fieldset; no recent private generations |
| `/pl/settings`, `/en/settings` | Disabled preview using default values; no saved private preferences or model discovery |
| Assistant | Openable preview with a disabled composer and an explanation; no conversation fetches or polling |
| Generation, settings updates, drafts, conversations, MCP | Server-side access guards reject requests even if local AI and authoring flags are enabled |
| Active Storage endpoints | Framework upload, download and transformation routes are not mounted at demo boot |
| Progress | Separate encrypted browser identity, including on localhost; private, non-cacheable HTML and progress responses |

Clearing the learner cookie or using another browser starts a separate profile. There is no login or cross-device synchronization. Progress is stored in PostgreSQL, with the browser holding only its identity cookie.

Production demo mode uses one primary PostgreSQL database, an in-process cache and inline jobs. It needs no queue worker, Solid Cache/Cable databases, Codex executable, or AI credentials. Uploaded local authoring assets are not used by the demo.

For development-only content review, `ruby bin/rails demo:prepare` adds the courses to the ordinary library without activating demo mode. The existing development seed remains available. When `DEMO_MODE=true`, `db:seed` instead loads only the packaged catalog.

## Bundled media

Original course text lives in `db/demo/{pl,en}/`. YAML manifests supply titles, descriptions and image references. PNGs and the licensed photograph are versioned in `public/demo-media/` and included in the container image. See [asset sources and licensing](demo-assets.md).

The read-only `bundled` Active Storage service stores database references to those files and returns same-origin static URLs. It validates keys, rejects writes and direct uploads, and preserves source files when a database attachment is purged. Covers use a prepared 960 × 540 image, so requests need no writable image-variant cache. Standard local course attachments retain their existing disk service outside demo mode.

Run `ruby bin/rails demo:illustrations` to regenerate the original cover and chart PNGs with libvips. The source SVG and chart drawing code are in the repository. Assets are immutable once seeded: use a new versioned filename and update the manifest when their bytes change. The importer checks image contents, size, dimensions and checksums. Do not copy private `storage/` or a development database into a demo deployment.

## Vercel deployment preparation

The local Docker commands above do not create external resources. Hosted deployments use Vercel's [Container Runtime](https://vercel.com/docs/functions/runtimes/container), currently documented as beta, and Neon PostgreSQL through the Vercel Marketplace. The container preserves the project's Ruby version and native dependencies. Confirm the target project and current platform limits before publishing.

`vercel.json` selects the Container preset and the Frankfurt (`fra1`) function region. Provision Neon in the same region, with Auth and Realtime disabled. The demo uses ordinary Active Record and the `pg` gem; no provider SDK is required. Connect the database to Production only unless a separate preview database has been deliberately prepared.

The container runs as the unprivileged `rails` user with `HOME=/home/rails`. Puma drains requests and exits normally on `SIGTERM`, which container platforms use during scale-in and deployment replacement. This avoids reporting routine shutdown as an application crash. Both the application and the free database may idle between visits; allow for a cold start.

Configure `DEMO_MODE=true`, `RAILS_ENV=production`, `PORT=3000`, a stable random `SECRET_KEY_BASE`, and the provider's `DATABASE_URL` (including its required TLS options). Keep `LOCAL_AI_ENABLED=false` and `COURSE_AUTHORING_ENABLED=false`. The two bundled courses need no writable media volume or cloud bucket; PostgreSQL must remain persistent.

Run `ruby bin/rails db:prepare demo:prepare` as a controlled release step against the target database, then set `PREPARE_DATABASE_ON_BOOT=false` for the web service. This avoids simultaneous migrations on auto-scaled instance startup. The local Compose preview intentionally retains automatic preparation for an easy fresh start. Run a hosted deployment behind HTTPS; the production configuration assumes a TLS-terminating proxy.

For the release command, use Neon's `DATABASE_URL_UNPOOLED` as the process's `DATABASE_URL`. Normal web requests use the pooled `DATABASE_URL` supplied by the integration. Preserve the database name and TLS parameters in both connection strings. Verify the target Neon project before running migrations. Import the packaged catalog rather than copying a development database.

Store `SECRET_KEY_BASE` as a Vercel Secret and retain it across deployments. Keep non-sensitive flags as Config variables. `.vercel/` and environment files are excluded from Git, Docker and Vercel source uploads. If credentials are needed locally for a release, pull them to an explicitly ignored production filename; never overwrite the development `.env` or `.env.local`. Remove temporary credential files after the release.

Stage a production build, check its protected URL with the authenticated CLI, and promote that exact build:

```sh
vercel project inspect --non-interactive
vercel deploy --dry --json
vercel deploy --prod --skip-domain
vercel curl https://<deployment-host>/up
vercel curl https://<deployment-host>/en
vercel promote https://<deployment-host>
```

The production alias must be accessible to visitors without a Vercel login. Keep preview and individual deployment URLs protected. After promotion, run `DEMO_URL=https://<public-host> ruby bin/check-demo` from a shell with the project dependencies installed, then verify the browser behavior below. The smoke check creates fresh anonymous profiles and reverses its lesson completion.

Before publication, verify both language versions, all eight lessons, media loading, equations, the diagram, exercise disclosure, progress persistence after restart, isolation in a second browser, disabled forms, and rejection of direct POST/PATCH requests. Test the actual preview deployment before assigning a public domain.

## Automated checks

```sh
ruby bin/rails test test/integration/demo_mode_test.rb test/services/demo_catalog_test.rb
ruby bin/rails test test/system/demo_test.rb
```

The integration checks exercise the guards with both local AI flags enabled. Catalog checks cover repeatability, preserved progress, read-only media, and the executable Ruby examples in both courses. Browser checks render each format, exercise completion and the assistant preview, and inspect disabled forms at 320 px with enlarged text.
