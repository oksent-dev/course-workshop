# Course Workshop

A workspace for creating and studying structured courses, with a Polish and English interface.

## Status

The library groups courses by category. Each course has an outline and a reader with previous and next lesson links. A three-lesson Polish course on everyday statistics is included.

Lessons render Markdown with headings, lists, code, links, and tables. Local images use Active Storage, with descriptions and optional captions. The example course includes a prepared chart. See [lesson content and image import](docs/lesson-content.md) for authoring instructions.

The statistics lesson also includes a KaTeX formula, a Mermaid flow diagram, and a practice exercise with a revealable answer. See [learning blocks](docs/learning-blocks.md) for the supported formats.

An optional local tutor uses GPT-6.1 Sol through Codex App Server. Ask questions directly in a lesson and continue the conversation there. See [local AI setup and verification](docs/local-ai.md); AI is disabled by default and unavailable in production.

## Requirements

- Ruby 4.0.9 and Bundler 4.0.20
- Node.js 24 and npm 11
- Docker with the Compose plugin
- Chrome or Chromium for browser tests
- libvips for validating and importing lesson images

On Windows, use RubyInstaller with MSYS2/Devkit. Native gems may install build dependencies during the first bundle installation.

## Quick start

From the project directory:

```sh
ruby bin/setup
ruby bin/dev
```

Setup installs dependencies, creates a private `.env` with a generated database password, starts PostgreSQL, prepares the databases, loads the example course into development, and builds assets. Existing `.env` values are preserved. Review `.env.example` for available settings.

Open [http://localhost:3000](http://localhost:3000). The application redirects to `/pl`; English is available at `/en`.

Open **Statystyka na co dzień** in the library, then select the first lesson from the course outline. Follow the navigation to the final lesson or jump to a title in the outline. Switching the interface to English keeps the current lesson open and the original Polish text visible.

The development command runs Rails, the JavaScript watcher, and the Tailwind watcher. Stop them with Ctrl+C. If PowerShell does not find Ruby, reopen the terminal after installing RubyInstaller.

## Database and files

PostgreSQL runs in a dedicated Docker Compose service, bound to `127.0.0.1:5432`. Set `POSTGRES_PORT` in `.env` before setup if that port is occupied.

```sh
docker compose up -d --wait db
docker compose stop db
```

Database files live in the `postgres_data` named volume. Active Storage uses `storage/` locally. Both are private runtime data and are excluded from Git. Removing the database volume destroys its contents; changing the password in `.env` does not rotate the password in an existing PostgreSQL volume.

For an existing checkout, run `ruby bin/rails db:prepare db:seed` to migrate the databases and refresh the example in development. The [seed material](db/seeds/everyday-statistics.yml) supplies the course slug and the lessons in reading order. Re-running the seed updates those records in place and preserves their links.

Image imports use libvips to validate the file contents and dimensions. Install libvips before importing images or running the seed and tests. The production Dockerfile and CI already include it.

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

Tests use a separate `course_workshop_test` database. Browser tests run headless Chrome. GitHub Actions runs the checks against PostgreSQL.

## Stack

- Rails 8.1, PostgreSQL 18, Puma, and Propshaft
- ERB, Turbo, Stimulus, and esbuild
- Tailwind CSS through `tailwindcss-rails`, with daisyUI components in ERB views
- Rails I18n with English and Polish locale dictionaries
- Active Storage with the local disk adapter
- Solid Queue, Solid Cache, and Solid Cable for production infrastructure

Commonmarker renders lesson Markdown, KaTeX renders math, and Mermaid with DOMPurify renders restricted flow diagrams. Chart.js and the Ruby MCP SDK are installed for upcoming interactive chart and agent features.

## Configuration and deployment

Keep secrets in environment variables or encrypted Rails credentials. Never commit `.env`, credential keys, uploaded files, or logs.

The production Dockerfile builds a standalone Rails image:

```sh
docker build -t course-workshop .
```

A deployment must provide `SECRET_KEY_BASE`, PostgreSQL connection settings, and persistent storage mounted at `/rails/storage`. The entrypoint prepares the primary and Solid databases; the database role needs the corresponding privileges. Run behind a TLS-terminating reverse proxy. A live Codex runtime is not included in the image.

See [architecture](docs/architecture.md) for component boundaries and the [Reading Room design system](DESIGN.md) for interface guidelines.
