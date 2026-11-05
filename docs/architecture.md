# Architecture

## Application

Course Workshop is a server-rendered Rails application. ERB produces HTML; Turbo handles navigation and partial updates; Stimulus provides focused browser behavior. esbuild bundles JavaScript, and the standalone Tailwind executable builds CSS.

PostgreSQL is the application database. Active Storage stores file metadata in PostgreSQL and file contents on disk. Production uses the standard Solid adapters, with separate cache, queue, and cable databases.

## Localization

The UI supports `pl` and `en`. URLs contain the selected locale, and an `around_action` applies it only for the current request. Locale dictionaries contain interface strings; development and tests raise on missing translations.

Course language will be a separate domain attribute. Changing the interface locale will not silently translate course content.

## Planned course features

The planned domain includes categories, ordered lessons, exercises, learning progress, and lesson conversations. Markdown source will be stored in PostgreSQL. Math, diagrams, and supported interactive elements will be rendered through dedicated components.

Generated content will be treated as input: HTML output must be sanitized, and interactive blocks must use validated data rather than arbitrary generated JavaScript.

## Planned agent boundary

The embedded chat will use an adapter to a local Codex runtime, initially evaluated through Codex App Server. A separate MCP interface will expose focused course operations to the agent.

This integration is not implemented in the foundation. It must keep application access rules in the application, pass explicit lesson context, and handle cancellation and failures. Public demonstration deployments will need an explicit policy for disabling live AI operations.

## Development and production

Development runs Ruby on the host and PostgreSQL in Docker. The production image runs Rails on Linux and includes compiled assets. Dependency lockfiles cover Windows and Linux.

Development credentials and uploaded content are local runtime data. The public repository contains configuration examples, not credentials.
