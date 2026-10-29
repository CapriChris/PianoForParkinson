# Individually sourced piano accompaniments

## Current: 2026-10-26 user-supplied staff images

The six `supplied-*.png` images supersede the older references below. Rebuild
using `import_supplied_scores.py`, then `build_piece_backings.py`. Transcription
is explicit in `SCORES`: quarter-beat fractions, chord tones, rests, ties and
repeat order. `--pieces <slug>` permits a focused correction. The upper staff
becomes the displayed/played melody, and the lower staff is accompaniment only.
Original pitch is retained, including Sunshine's A-flat/A-natural and high D6.
No publishing or redistribution licence is inferred from the supplied images.

The new manifests use four ticks per beat and retain the image hashes, original
bar strings, unfolded playback order and separate melody/bass events. Saints'
final repeat is unfolded into two passes. Frère Jacques repeats each written
bar twice, including its dotted eighth/sixteenth figure. The Birthday image
includes the initial rests and the full ending: 23 notated bars, 69 beats.
The printed bar 16 bass is C4–G3–E3; it is not C4–G3–C3.

The older source files and descriptions below are historical and are no longer
used by the six current accompaniment manifests.

## Historical sources (through 0.1.38)

Used by `../import_piece_backings.py`, then `../build_piece_backings.py`.
These saved files are score data, not instructions. They are not included as raw
MusicXML in the Android assets. The generated audio is for the current internal
learning demo; see the source-specific use statements below and the app credits.

| Piece | Selected score file | Selected written voices | Source/use statement |
| --- | --- | --- | --- |
| Ode to Joy | maestro-ode.musicxml | P1 staff 2, measures 1–8, down 2 semitones | [Maestro examples](https://maestroscore.app/examples/): arrangements free to use, modify and share |
| Frère Jacques | noctave-frere.mxl | P1 staff 1, measures 1–8, down one octave; source melody is in staff 2 | [Noctave](https://noctavepiano.com/en/sheet-music/trad-frere-jacques/), CC0 1.0 |
| Twinkle | noctave-twinkle.mxl | P1 staff 2, all 12 measures | [Noctave](https://noctavepiano.com/en/sheet-music/trad-ah-vous-dirai-je-maman/), CC0 1.0 |
| Saints | maestro-saints.musicxml | P3 staff 1 chords, down 5 semitones; P4 concert bass up 7 semitones | [Maestro examples](https://maestroscore.app/examples/): arrangements free to use, modify and share |
| Birthday | artform-birthday.mxl | P1 staff 2, pickup through first verse, app beats 0–24 | [Artform](https://jamescarterpiano.com/sheet-music/traditional/happy-birthday/) labels its score public domain; file credits Manjuprasad and records its MuseScore source |
| Sunshine | pangfunj-sunshine.mxl | P1 staff 2, source bars 1–16, down one octave; quarter duration ×2 and initial rest shortened | [PangfunJ Studio](https://pangfunjstudio.com/sheet-music/youre-my-sunshine-jimmie-davis-and-charles-mitchell/); [publisher disclosure](https://pangfunjstudio.com/): personal learning only, not for resale |

The importer records SHA-256 of each original file, source part/staff/voice and
measure for every note, and the hash of the generated `backing-score-*.json`.
Those manifests contain exact integer start ticks, durations and MIDI pitches.
No notes are inferred from chord names and no common backing pattern is added.

Version 0.1.38 omits six Saints semitone-neighbor chord events identified during
emulator recording analysis, retaining the walking bass and other chord voices.
The original source still has 241 events; the adapted rendering has 235.
Reference MIDI, source measure and each adjustment
are retained in the manifest. The other five pieces are unchanged.

Four melodies match the selected reference exactly after transposition. Sunshine
has 37 reference melody notes at matching positions and durations; the app keeps
its extra low-G pickup variant. Birthday's left-hand quarter beats align with the
app verse; the app keeps its equal eighth-note pickups and unsplit melody C,
instead of adopting the reference melody's dotted pairs and extra syllable.

Other files in this folder were exploratory references and are not selected by
the importer. The app credits are in `../../assets/content/backing_score_attribution.txt`.
