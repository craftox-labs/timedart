# README media — shot list

Drop the PNGs named below into this folder; the README `<img>` slots pick them
up automatically. Capture on the **dark theme**, hide personal/client data
(use the seeded demo data or dummy names), and keep widths consistent.

| File | What to capture | Target width |
| --- | --- | --- |
| `hero.png` | Main tracker: side panel (clients → projects → tasks) + a **running** timer + the task list. The signature view. | ~1600px |
| `invoice.png` | A branded invoice **preview** (the A4 preview or an exported PDF page), ideally with a logo + a few line items. | ~800px |
| `onboarding.png` | The "How timedart works" onboarding step (the cycling panel + flow cards). | ~800px |
| `branding.png` | The invoice branding editor — a template or profile form, or the read-only preview. | ~800px |
| `keyboard.png` | The shortcut overlay (press `?`). | ~800px |

Notes
- PNG, 2× / retina if easy (GitHub scales down cleanly). Trim window chrome unless it adds context.
- Optional later: a short screen capture (GIF/MP4, timer → invoice) for the hero instead of a still.
- Logo hero is a theme-aware `<picture>`: `timedart_logo_stacked_dark.png` (dark viewers) /
  `timedart_logo_stacked_light.png` (light viewers), so the wordmark stays readable on both.
