# Application screenshots

These are unedited browser captures of the isolated English demo, using the bundled **Statistics over coffee** course. They contain no local AI conversation, private settings, generated user course, or account information.

Start the demo, install development dependencies, then run:

```sh
ruby bin/demo
bundle install
ruby script/capture_screenshots.rb
```

The script requires Chrome/Chromium and the project's Selenium dependency. `DEMO_URL` optionally selects another running demo; the default is `http://localhost:3001`. It uses a fresh browser profile, waits for fonts and lesson renderers, and disables motion for stable captures. It refuses a page without the demo notice.

| File | Viewport | Content |
| --- | --- | --- |
| `library.png` | 1440 × 1100 | Course cards, language/category labels, covers and progress |
| `reader.png` | 1440 × 1400 | Outline, lesson prose and mean formula |
| `code.png` | 1440 × 1100 | Comparison table and highlighted Ruby example |
| `diagram.png` | 1440 × 1400 | Complete Mermaid flowchart in the lesson reader |

Regenerate the images after material UI changes and inspect each result before committing it. Update the root README paths if a filename changes.
