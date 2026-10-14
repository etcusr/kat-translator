# Kat translator — visual direction

**English** | [Русский](README.ru.md)

The working title was approved by the user on 7 October 2026: **Kat translator**, the same in RU and EN. Name availability and trademark checks were not part of this iteration.

## Current design

- **App icon — the neon cat** from the user-supplied `kat-icon.zip`: default, dark and tinted variants, 1024×1024, RGB without alpha. It replaced the previously chosen stamp on 7 October 2026. [Details](neon-icon.md).
- **Neon theme:** lime action color `#C9FA33`, black background `#000000`, violet cards `#1B1729`; shared `KatTheme`. [Details](neon-theme/README.md).
- **Waiting animations:** a drawn cat for downloads and 14 clips for voice/text processing. [Gallery and update rules](loading-animations/README.md).
- Store artwork (Header / Search Results) lives in `docs/publication/2026-10-14/creative-assets/`.

## The user's choice on 7 October — the stamp (replaced)

On 7 October 2026 the **first option of the ninth round — the stamp** was chosen: an elongated black `kat`, a yellow accent and the caption `translator`. The neon icon replaced it on the same day; the stamp is kept in `stamp-icon/replaced-app-icon.png`.

Stamp file: kat-primary-stamp-v1.png (`kat-primary-stamp-v1.png`). Original: round-9/stamp.png (`round-9/stamp.png`); the exact prompt is in `round-9/prompts.json` (built-in image_gen). The previously chosen pixel cat and drawn cat are kept as historical candidates.

In-app downloads gained an animated cat silhouette: sits → stands up → walks/runs → sits down. The pace follows the smoothed fill speed of the bar, taking the package size into account. [Preview and check](cat-progress/README.md).

## Search history — earlier directions

> The concept images referenced below (PNG files of the rounds) are not included in the public repository; file names are kept for reference.

The following sections describe earlier iterations; they do not replace the current design above.

## Character

A sarcastic, unflappable cat: slightly squinting eyes, an asymmetric smirk, recognizable ears and black-and-white fur. The source photo sets the mood and is a starting point, not an image to copy. The character has its own proportions, markings and pose.

The cat may be ironic about the situation but never mocks the user. Its character does not affect the translation text, the accuracy of error messages or the privacy description. No model-added jokes in translations.

## Three candidates

1. **Flat / minimal:** a high-contrast light silhouette, dark background, mint details. Main candidate for the small icon.
2. **Ink / sticker:** a lively hand-drawn line, an elongated neck and a sideways look. Closer to the humor of the source image; suits first-launch illustrations.
3. **Clay / 3D:** a matte figurine with the same unflappable character. A softer, more textured look.

The candidates were generated separately with the built-in image_gen. Prompts are kept in `prompts.json`. At that point the final app icon had not been chosen or installed.

## Usage

Keep the dark background and the mint accent of the interface at that time. Use the cat sparingly: icon, first launch, the About section, empty history. Translation fields and main buttons stay easy to read. A screen redesign would be a separate iteration after choosing the character.

Do not put small text into the icon. The name sits separately from the emblem; keep sufficient contrast and free space around the head.

## Second round

- Retro comic (`round-2/kat-retro.png`)
- Geometric mark (`round-2/kat-geometric.png`)
- Pixel cat — main (`round-2/kat-pixel.png`)
- Logo with name (`round-2/kat-wordmark.png`)

## Third round — mixing new references

The first chosen pixel cat remained the main one. New options for comparison:

1. Sly-naive, with the tongue out (`round-3/kat-pixel-blep.png`).
2. Snide laugh (`round-3/kat-pixel-laugh.png`).
3. Black schemer cat (`round-3/kat-pixel-schemer.png`).
4. Pixel logo with name (`round-3/kat-pixel-wordmark.png`).

All options were created with the built-in image_gen. Full prompts: `round-3/prompts.json`. These are raster concepts, not finished vector graphics.

## Fourth round — a change of approach

The user did not like the new third-round options and asked for a different approach and style. These three images were created from scratch, without reference images, to avoid repeating the same face. The pixel candidate was kept; no new final choice.

1. Unflappable doodle cat (`round-4/kat-doodle.png`): character through pose and a messy line.
2. Black-and-white mark (`round-4/kat-deadpan-mark.png`): a silhouette and two squinting eyes.
3. Bright odd character (`round-4/kat-acid-character.png`): unusual proportions, eye-rolling, orange/violet/yellow.

Generator: built-in image_gen. Full prompts: `round-4/prompts.json`.

## Fifth round — concise logos without a character

The user rejected the fourth round and asked for simple graphic logos, possibly without a cat at all. The earlier pixel option was kept as a historical candidate; the direction became simple marks and typography.

1. kt monogram (`round-5/kt-monogram.png`).
2. Abstract exchange / two languages (`round-5/exchange-mark.png`).
3. Kat translator wordmark (`round-5/kat-wordmark.png`).

Raster concepts were created with the built-in image_gen without references. Prompts: `round-5/prompts.json`. No final option was chosen.

## Sixth and seventh rounds

Monogram variations are kept in `round-6/` together with prompts. The user rejected the direction and asked to research other styles online.

[Seventh round — six concepts](round-7/README.md): poster graphics, modular typography and retro-futurism; a mark and a wordmark for each direction. Sources and prompts in `round-7/prompts.json`. No new icon was chosen or installed at that point.

## Eighth round — with the logo-design and brand-identity skills

[Four concepts and icon examples](round-8/README.md). The skills were installed in ~/.codex/skills. Prompts are saved in round-8/prompts.json. The concepts were not approved or installed in the app.

## Ninth round — free exploration

The user preferred random, diverse directions instead of collecting new references. [Six options](round-9/README.md): stamp, pixels, calligraphy, colorful abstraction, optics, glass. The stamp from this round was chosen on 7 October and replaced by the neon icon the same day.
