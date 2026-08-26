# AskEva Design System

AskEva (styled **ÄSK EVA** in the logo, "Askeva Communication Pvt. Ltd.") is a WhatsApp business-messaging platform: AI chatbots, broadcasts, CRM/ERP integrations, and automation for sales, support, and marketing. Meta technology partner on the official WhatsApp Business API. 5,000+ business clients across e-commerce, education, healthcare, BFSI. Mascot: "Eva", a friendly white robot with glowing lime eyes.

## Sources
Local folder `Design System/` (brand PDFs + PNGs), copied into `sources/` and `assets/`:
- `Logo.pdf` — logo usage (color / on-dark / mono ink)
- `Gradient.pdf` — signature gradient spec: 135°, #3DC838 → #7FD63B → #C8FF4A
- `Chat bubbles.pdf` — WhatsApp conversation styling
- `Marketing block.pdf` — hero/marketing typography pattern
- `Seminar deck review for AskEva.pdf` — 55-page seminar deck (primary layout source)
- `PPT.pdf` was over the 30 MiB upload limit and could not be copied; ask the user for a smaller export if needed.

No product-app UI (dashboard, website) was provided, so there is **no UI kit** beyond deck slides — only brand, tokens, components, and slide layouts.

## Content fundamentals
- Voice: confident, punchy, benefit-led sales copy. Short declarative lines: "Transform conversations into customers." "WHATSAPP wins."
- Headlines mix SHOUTING CAPS with one lowercase italic accent word: "ATTENTION HAS *shifted*." "ABOUT *askeva*." Headlines often end with a period (sometimes green).
- Labels are tracked uppercase with middot separators: "MODULE 01 · BROADCASTS", "01 · CLIENTS", "ASKEVA · 2026". Slide footers: brand-year left, "07 / 42 · MODULE 01" right.
- Comparisons use ✕ / ✓ lists ("Customers don't want to… They want…").
- Emoji: yes, but only inside product/chat content (👋 🎯 📅 🎫) — never in headings or labels.
- Chat copy is warm and human: "Hi Eshan 👋 This is a friendly reminder…", first-person bot, exclamation-friendly.
- Numbers are dramatized: "5,000+", "MILLIONS", "95%+".

## Visual foundations
- **Colors**: warm cream paper `#EFECE3` page background; near-black green ink `#10180C`/`#1A2314`; brand green `#3DC838`; gradient greens `#7FD63B`, lime `#C8FF4A`. Max two background colors per composition (paper + one of ink/green/gradient).
- **Signature gradient**: 135°, #3DC838 → #7FD63B → #C8FF4A. Used on ticker strips, section-divider slides, thin bottom bands.
- **Type**: ultra-bold condensed uppercase display (Anton substitute) + lowercase serif italic accent word (Playfair Display Italic substitute) + Archivo body + Space Mono for token/code values. Display leading 0.95; label tracking 0.18em.
- **Cards**: white, ink, or green fills; 16px radius; 1px ink border; **hard offset shadow 4px 4px 0 ink** (no blur). Rows alternate tones.
- **Buttons/pills**: fully rounded; hard 3px offset shadow; press = translate into shadow. Numbered index pills "01 · EMAIL" (outline on light, lime fill on ink).
- **Motifs**: scrolling gradient ticker of "SELL · SUPPORT · BROADCAST — ON WHATSAPP"; ghost oversized numerals on dividers; green solid highlight blocks behind headline words; hand-drawn ellipse circling an accent word; green square bullet before eyebrows; thin gradient/ink band at slide bottom.
- **Chat surfaces**: WhatsApp-authentic — beige canvas `#E7DFD4`, white incoming, pale-green `#D9FDD3` outgoing, green sender name, blue ✓✓ ticks, soft 1px shadows (the one place hard shadows are NOT used).
- **Backgrounds**: flat fills or the signature gradient; subtle contour-line texture appears on gradient/dark slides in the source deck (not reproduced — flag if needed).
- **Animation**: ticker marquee (linear, infinite); button press translate; otherwise static. No bounces or fades observed.
- **Hover**: darker green (`--green-600`) for links; buttons rely on press state.
- **Imagery**: 3D rendered mascot, product UI mockups in offset-shadow cards. No photography observed.

## Iconography
- No icon font or SVG icon set in sources. The deck uses: ✕ / ✓ unicode marks, middots, arrows (→), and emoji within product content. WhatsApp glyph appears on the title slide (not shipped — trademark; use text or ask user for the asset).
- Copied assets: `assets/logo-01.png` (color — use ONLY on green or ink backgrounds, never on white/light), `assets/logo.png` (mono black — for white/light backgrounds and print), `assets/bot.png` (Eva mascot).
- If icons are needed, use Lucide from CDN (rounded, 2px stroke) and flag the substitution.

## Fonts — SUBSTITUTED, ask user for originals
No font binaries were provided. Google Fonts nearest matches, loaded in `tokens/fonts.css`:
- Display: **Anton** (deck uses a very similar heavy condensed grotesque)
- Accent italic: **Playfair Display Italic**
- Body: **Archivo**
- Mono: **Space Mono**

## Components
- `Button` — pill CTA; green/ink/lime/outline tones
- `Pill` — numbered index label "01 · EMAIL"
- `SectionLabel` — green-square eyebrow
- `Ticker` — gradient marquee strip
- `StatCard` — pill + big figure + caption; white/ink/green
- `TemplateCard` — WhatsApp broadcast template mock
- `ChatBubble` — WhatsApp conversation bubble

### Intentional additions
None — all components come from patterns in the seminar deck, marketing block, or chat-bubbles PDF.

## Index
- `styles.css` → `tokens/` (fonts, colors, typography, spacing)
- `components/` — actions (Button, Pill), brand (SectionLabel, Ticker), cards (StatCard, TemplateCard), chat (ChatBubble); each with `.d.ts`, `.prompt.md`, specimen card
- `guidelines/` — color, type, spacing, brand specimen cards
- `ui_kits/slides/` — TitleSlide, StatsSlide, SectionSlide, ComparisonSlide (1280×720 deck layouts)
- `assets/` — logo-01.png (color, green/ink bg only), logo.png (mono, white bg), bot.png (mascot)
- `sources/` — original PDFs
- `SKILL.md` — agent skill entry point
