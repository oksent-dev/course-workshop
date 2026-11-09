# Documentation

[Project overview and screenshots](../README.md) · [Design system](../DESIGN.md) · [License](../LICENSE) · [Notices](../NOTICE)

## Run and understand the application

| Guide | Covers |
| --- | --- |
| [Development setup](development.md) | Dependencies, first start, Windows notes, configuration, checks, troubleshooting and backups |
| [Demo and deployment preparation](demo.md) | Two bilingual courses, isolated Docker setup, disabled AI, bundled media, Vercel prerequisites and smoke checks |
| [Architecture](architecture.md) | Rails request flow, records, component boundaries, localization, storage and agent execution |
| [Reading Room design system](../DESIGN.md) | Logo, palette, typography, layout, controls, motion and accessibility review |

## Create and study courses

| Guide | Covers |
| --- | --- |
| [Course generation](course-generation.md) | Topic submission, plan approval, lessons, categories, visuals, status and recovery |
| [Course assistant](course-assistant.md) | Shared panel, context, durable history, pagination, activity and continuity |
| [Draft editing](draft-editing.md) | Scoped editing tools, lesson changes, revisions, cover replacement and undo |
| [Learning progress](learning-progress.md) | Local/browser ownership, completion, resume and persistence |
| [AI settings](ai-settings.md) | Models, reasoning effort, response style, immutable settings snapshots and course provenance |

## Content and integrations

| Guide | Covers |
| --- | --- |
| [Lesson Markdown and images](lesson-content.md) | Formatting, highlighted code, image imports, captions, limits and sanitization |
| [Math, diagrams and exercises](learning-blocks.md) | Accepted fence formats, accessible fallbacks and renderer behavior |
| [Course covers](course-covers.md) | Local import, generated covers, image validation and retries |
| [Local AI](local-ai.md) | Codex setup, executable discovery, runtime restrictions, workers and recovery |
| [Course-authoring MCP](course-authoring.md) | External local clients, tool schemas, access boundaries, revisions and idempotency |
| [Demo asset sources](demo-assets.md) | Photograph attribution, original illustrations and teaching data |
| [Screenshot capture](screenshots/README.md) | Reproducing the README images from the isolated demo |

## Maintenance and licensing

- [Contribution policy](../CONTRIBUTING.md): external contributions are not accepted.
- [PolyForm Noncommercial License 1.0.0](../LICENSE) and [project notices](../NOTICE).
- Bundled font licenses: [DM Sans](licenses/dm-sans.txt), [Spectral](licenses/spectral.txt).
- [Continuous integration](../.github/workflows/ci.yml): style, security, dependency audits, application and browser tests, and the production demo build.

All application documentation is written in English. Course material and interface strings may use either supported content language. When changing behavior, update the guide that owns it and keep this index current.
