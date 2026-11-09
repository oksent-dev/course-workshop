# Learning progress

The library and course outline show a completed-lesson count and a progress bar. The reader distinguishes the current lesson from completed lessons. Use **Mark complete** after studying a lesson; **Mark as incomplete** reverses that choice.

## Ownership

Development uses one shared local learner profile by default. Requests must come from a loopback address and use a localhost or loopback host name to access it. Its progress is shared across local browsers and survives browser changes, application restarts, and cookie removal because it belongs to a stable database record.

Set `LOCAL_PROGRESS_ENABLED=false` and restart Rails to try browser-specific progress locally. Test and production environments default to browser profiles. Production and demo mode always use browser profiles, even if this setting is explicitly enabled. Nonlocal requests also use browser profiles.

A browser profile is identified by a random 256-bit key in an encrypted cookie. The cookie expires one year after creation, is HTTP-only, uses `SameSite=Lax`, and is marked secure on HTTPS. Only the server chooses the profile; request parameters cannot select another learner. Profile IDs and completion data are not stored in the cookie.

This is anonymous browser continuity, not an account or sign-in system. A separate browser, private window, cleared cookie, expired cookie, or changed encryption key starts a separate profile. Existing database records remain, but there is no recovery or cross-device synchronization. Switching between local and browser modes does not merge their progress. Accepted conversations use the same learner identity and remain in PostgreSQL, scoped additionally to course and tutor/editor mode; only unsent composers and panel state live in per-tab session storage. Demo mode does not expose conversation history.

## Completion and resume rules

- Opening a lesson records its most recent visit. It never completes the lesson.
- Revealing an exercise answer or asking the tutor a question does not complete the lesson.
- Completing a lesson sets its completion time once. Repeated submissions keep the same row and timestamp.
- Undo clears completion while preserving visit history. Repeating undo has no further effect.
- Counts use the course's current lessons. An empty course has no progress bar or start action and is not considered complete.
- An untouched course starts at its first lesson.
- **Resume course** opens the last visited lesson if it is unfinished. If it is complete, resume selects the next unfinished lesson in course order, wrapping to the first unfinished lesson when necessary.
- Once every lesson is complete, **Review course** opens the first lesson. Review does not reset completion.

Changing the interface language preserves the same profile and progress. Updating seeded material in place preserves progress because the lesson IDs remain stable. Deleting a lesson removes its associated progress; adding a lesson changes the total and makes it available to resume.

## Storage and requests

`LearnerProfile` owns `LessonProgress` records. Each progress row belongs to one lesson and stores `last_opened_at` and optional `completed_at`. PostgreSQL enforces foreign keys and a unique profile/lesson pair. Completion updates lock the row so concurrent repeated submissions cannot change an existing completion time.

`CourseProgress` calculates counts and resume targets from the ordered outline. Library queries load outlines and progress in batches rather than issuing queries for every card; lesson bodies are not loaded for this purpose.

The completion resource is nested under its course and lesson:

```text
POST   /:locale/courses/:course_slug/lessons/:lesson_id/completion
DELETE /:locale/courses/:course_slug/lessons/:lesson_id/completion
```

Both actions use Rails forms with CSRF protection. Turbo Stream responses morph only the desktop/mobile progress and outline, completion controls, and previous/next navigation. The lesson body, open exercise, assistant, keyboard focus and reading position remain in place. Completion does not add a history entry or replay entrance animations. Without JavaScript, HTML submissions redirect with HTTP 303 to the lesson's progress panel. The lesson is resolved through its course and the progress through the current profile.

Reader GET requests record visits. HEAD and prefetch requests do not move the resume location. Turbo prefetching and page snapshots are disabled so background requests do not count as reading and browser back navigation refreshes progress. Personalized pages use `Cache-Control: private, no-store`.

Progress lives in PostgreSQL, not browser storage. Preserve the database volume to preserve records. Browser continuity additionally requires the cookie and a stable application encryption key. Course backup and restore should retain lesson IDs and associated progress rows.

## Verification

After updating an existing checkout:

```sh
ruby bin/rails db:prepare
ruby bin/dev
```

Run the complete suite with `ruby bin/rails test:all`. Progress coverage includes a two-of-five course after reopening with the same browser cookie, repeat submissions, undo, resume ordering, deletion, empty courses, local sharing, browser isolation, tampered cookies, production isolation, prefetch requests, keyboard controls, PL/EN, narrow screens, and Turbo back navigation.

For a manual check, complete two lessons, return to the library, and select **Resume course**. Reopen the application to check that the count remains. In browser mode, use another browser or private window to check that its count starts at zero. After completing the course, select **Review course**, undo one lesson, and check that **Resume course** returns to it.

Implementation references: [Rails cookies](https://guides.rubyonrails.org/action_controller_overview.html#cookies), [Turbo prefetching](https://turbo.hotwired.dev/handbook/drive#prefetching-links-on-hover), and [Turbo cache control](https://turbo.hotwired.dev/handbook/building#opting-out-of-caching).
