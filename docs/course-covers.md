# Course covers

Courses may have one decorative cover stored through Active Storage. The original bytes stay on the local disk service; PostgreSQL stores attachment metadata. Neither uploads nor generated previews are committed. A fresh seed works without a cover and shows the bookshelf fallback. Reseeding does not remove an existing cover.

## Import

Use the same command for a first import or a replacement:

```sh
COURSE=statystyka-na-co-dzien FILE=/absolute/path/cover.png ruby bin/rails courses:attach_cover
```

In PowerShell:

```powershell
$env:COURSE = "statystyka-na-co-dzien"
$env:FILE = "C:/images/cover.png"
ruby bin/rails courses:attach_cover
```

The importer accepts decoded PNG, JPEG, and WebP files up to 5 MB and 20 million pixels. It detects content from the bytes, not the extension, and validates the input before changing the course. Repeating the same import reuses the blob; reimporting can restore a missing stored file. Changing the cover leaves lessons and learning progress intact.

The task prepares a 960 × 540 WebP card variant at quality 82. A fixed 16:9 frame prevents layout shifts. Cover images use empty alternative text because the adjacent course title supplies the link's accessible name. A missing or failed image falls back to a decorative bookshelf without blocking navigation.

## Automatic generation

New courses created through the local form get a cover after their lessons finish. A separate job uses the authenticated Codex App Server and GPT-6.1 Sol to invoke native image generation. It needs a runtime/account reporting `imageGeneration` support; version `0.166.0-alpha.6` was verified locally. No separate Image API key is used. This consumes the Codex account's image allowance. There are no model calls during setup, tests, seeding or ordinary navigation.

`CourseCoverGeneration` persists the course, status (`queued`, `running`, `completed`, `failed`), attempt, expiry and error code. Its unique course index and locked claim prevent duplicate delivery from creating more images. Completion creates this record in the same transaction as the finished lessons and enqueues it after commit. Images have a five-minute runtime deadline and a seven-minute persisted expiry. The local Async queue is not durable across restarts; the progress page expires stale work and offers an explicit retry.

The progress screen distinguishes lesson completion from image creation. **Retry cover** increments only the image attempt, leaving lesson IDs, text and approval unchanged. Late results from an earlier attempt cannot attach an image. A manually imported cover is preserved even when the image job finishes afterwards. Quota, unsupported runtime, invalid image and other failures have localized explanations. Course review and approval remain available without a cover, using the normal bookshelf fallback.

The image session receives only the course title, description and category plus a fixed Reading Room visual brief. It disables MCP, web search, shell, apps, plugins and project instructions. The adapter accepts only a matching `imageGeneration` completion item's inline base64 result, within the existing decoded byte/pixel limits. It never follows file paths or URLs from model prose, `savedPath` or `fileId`. A runtime that supplies only a file reference produces a retryable error rather than reading an arbitrary file. No raw image response is stored in PostgreSQL or application logs.

Automatic covers currently belong to the form workflow. Manually authored MCP drafts and older completed generations retain their existing covers or fallback; import an image for those with the task above.

## Codex verification

On 2026-11-06, a local App Server 0.166.0-alpha.6 session using GPT-6.1 Sol successfully called built-in image generation. The `imageGeneration` completion item provided a local `savedPath`. Its PNG was inspected, imported into the statistics course, downloaded from Active Storage, and compared by SHA-256. A repeated import preserved the blob ID. The original was 2,569,649 bytes and the WebP card variant was 54,900 bytes.

The trial used the native Codex image tool, not the separately billed Image API. [OpenAI's image-generation documentation](https://learn.chatgpt.com/docs/image-generation) describes this capability and its usage limits. The automatic adapter now uses the same tool's inline result, validating the bytes before attachment.

The complete form workflow was also verified on 2026-11-06: a three-lesson English course about commute-time variability reused the existing Polish statistics category and automatically saved a 1,518,184-byte PNG on its first image attempt. Its WebP card is 17,198 bytes. The draft and image remained available after reload, in both interface languages, at 320 px and 200% zoom. The draft was left for human review.

## Trial prompt

```text
Use case: stylized-concept.
Asset type: a landscape 16:9 cover illustration for an educational course card.
Create one original editorial illustration for a beginner course about everyday statistics:
comparing five morning commute times, understanding averages and medians, and noticing outliers.
A quiet tabletop still life combines a small clock and a simple row of five rounded vertical
wooden bars of different heights, with one noticeably taller bar. An open notebook has a few
subtle abstract dots and lines, without numbers, equations or writing. Keep the scene simple
and immediately recognizable at thumbnail size. Use tactile paper-cut shapes, restrained
painterly texture, soft natural side lighting and gentle shadows. Warm ivory paper background
(#FBF8EF), sage green (#435F48), pale sage (#E5EBDD), with a restrained terracotta accent.
Compose the main objects near the center with generous breathing room and crop-safe edges.
No people, lettering, typography, logos, borders, watermarks or UI elements. Opaque background.
Generate the actual image with your built-in image generation tool. Do not just describe it.
```

## Verification

Run `ruby bin/rails test:all`. Tests cover import round trips, idempotency, file recovery, invalid replacement, WebP output, filtering, draft exclusion, language-switch continuity, keyboard navigation, and image failure fallback. Generation tests use a fake adapter and exercise duplicate jobs, failure and independent retry, stale results, manual replacement, polling and local HTTP boundaries. Protocol tests reject wrong-turn events, invalid/oversized results and quota failures. The existing lesson-image tests exercise the shared decoder's format, byte, and pixel limits.
