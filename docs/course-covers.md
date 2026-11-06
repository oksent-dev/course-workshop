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

## Codex verification

On 2026-11-06, a local App Server 0.166.0-alpha.6 session using GPT-6.1 Sol successfully called built-in image generation. The `imageGeneration` completion item provided a local `savedPath`. Its PNG was inspected, imported into the statistics course, downloaded from Active Storage, and compared by SHA-256. A repeated import preserved the blob ID. The original was 2,569,649 bytes and the WebP card variant was 54,900 bytes.

The trial used the native Codex image tool, not the separately billed Image API. [OpenAI's image-generation documentation](https://learn.chatgpt.com/docs/image-generation) describes this capability and its usage limits. Generation is not yet part of the course-generation form; this change provides cover storage, import, and display. No model request runs during setup, tests, or ordinary library navigation.

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

Run `ruby bin/rails test:all`. Tests cover import round trips, idempotency, file recovery, invalid replacement, WebP output, filtering, draft exclusion, language-switch continuity, keyboard navigation, and image failure fallback. The existing lesson-image tests exercise the shared decoder's format, byte, and pixel limits.
