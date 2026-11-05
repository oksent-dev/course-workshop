# Course Workshop

A workspace for creating and studying structured courses, with a Polish and English interface.

## Status

The application foundation is in place: Rails, PostgreSQL, localized navigation, asset builds, local file storage, tests, and CI. Course management, lesson rendering, progress tracking, and the Codex integration are planned; they are not implemented yet.

## Requirements

- Ruby 4.0.9 and Bundler 4.0.20
- Node.js 24 and npm 11
- Docker with the Compose plugin
- Chrome or Chromium for browser tests

On Windows, use RubyInstaller with MSYS2/Devkit. Native gems may install build dependencies during the first bundle installation.

## Quick start

From the project directory:

```sh
ruby bin/setup
ruby bin/dev
```

Setup installs dependencies, creates a private `.env` with a generated database password, starts PostgreSQL, prepares the development and test databases, and builds assets. Existing `.env` values are preserved. Review `.env.example` for available settings.

Open [http://localhost:3000](http://localhost:3000). The application redirects to `/pl`; English is available at `/en`.

The development command runs Rails, the JavaScript watcher, and the Tailwind watcher. Stop them with Ctrl+C. If PowerShell does not find Ruby, reopen the terminal after installing RubyInstaller.

## Database and files

PostgreSQL runs in a dedicated Docker Compose service, bound to `127.0.0.1:5432`. Set `POSTGRES_PORT` in `.env` before setup if that port is occupied.

```sh
docker compose up -d --wait db
docker compose stop db
```

Database files live in the `postgres_data` named volume. Active Storage uses `storage/` locally. Both are private runtime data and are excluded from Git. Removing the database volume destroys its contents; changing the password in `.env` does not rotate the password in an existing PostgreSQL volume.

Image variants use libvips, which must be available if transformations are used. Uploads and local file storage do not require image transformation.

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

Commonmarker, KaTeX, Mermaid, Chart.js, and the Ruby MCP SDK are installed for the upcoming lesson and agent features. They do not expose a renderer, chart editor, or MCP endpoint yet.

## Configuration and deployment

Keep secrets in environment variables or encrypted Rails credentials. Never commit `.env`, credential keys, uploaded files, or logs.

The production Dockerfile builds a standalone Rails image:

```sh
docker build -t course-workshop .
```

A deployment must provide `SECRET_KEY_BASE`, PostgreSQL connection settings, and persistent storage mounted at `/rails/storage`. The entrypoint prepares the primary and Solid databases; the database role needs the corresponding privileges. Run behind a TLS-terminating reverse proxy. A live Codex runtime is not included in the image.

See [architecture](docs/architecture.md) for component boundaries and the [Reading Room design system](DESIGN.md) for interface guidelines.
