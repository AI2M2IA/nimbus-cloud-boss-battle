# Fallback fonts

The Web (HTML5) export bundles the engine's compiled-in default font, which
only covers Latin/Cyrillic/Greek glyphs. Players using a non-Latin
`data/i18n/<code>.json` locale (zh, ja, ko, hi, bn, ar, ur, he, th) saw tofu
boxes instead of text, and the "more choices below" overflow hint (`▼`,
U+25BC) was missing in every locale because the base font has no geometric
shapes at all.

The files here are subsets of Google's Noto Sans family, added as fallback
fonts on top of the engine default (see `fonts/notosans_fallback.tres` and
the `gui/theme/custom_font` project setting) — the default font is still used
first for every glyph it already covers, so existing Latin-script rendering
is unchanged. Each subset only includes the glyphs the game actually uses
(the i18n JSON values, the native language names in the language picker, and
the handful of symbols used for UI chrome), to keep the size increase small
(~1.7 MB total for 9 files) instead of bundling full-coverage CJK/Arabic
fonts (tens of MB each).

| File | Script / use | Source family |
| --- | --- | --- |
| `NotoSansSC-Subset.ttf` | Simplified Chinese (`zh`) | Noto Sans SC |
| `NotoSansJP-Subset.ttf` | Japanese (`ja`) | Noto Sans JP |
| `NotoSansKR-Subset.ttf` | Korean (`ko`) | Noto Sans KR |
| `NotoSansDevanagari-Subset.ttf` | Hindi (`hi`) | Noto Sans Devanagari |
| `NotoSansBengali-Subset.ttf` | Bengali (`bn`) | Noto Sans Bengali |
| `NotoSansArabic-Subset.ttf` | Arabic + Urdu (`ar`, `ur`) | Noto Sans Arabic |
| `NotoSansHebrew-Subset.ttf` | Hebrew (`he`) | Noto Sans Hebrew |
| `NotoSansThai-Subset.ttf` | Thai (`th`) | Noto Sans Thai |
| `NotoSans-Symbols-Subset.ttf` | UI symbols (`▼▲◀▶—–…‘’“”·•✓✗×÷°`), all locales | Noto Sans Symbols 2 |

Regenerating the subsets (e.g. after adding a new i18n key or language)
requires the source variable fonts from
[google/fonts](https://github.com/google/fonts) (`ofl/notosanssc`,
`ofl/notosansjp`, etc.) and `fonttools` (`pip install fonttools`):

```sh
python3 -m fontTools.subset <source.ttf> \
  --text="<exact characters used>" \
  --output-file=<out.ttf> \
  --layout-features=* \
  --name-IDs=*
```

`--layout-features=*` keeps the GSUB/GPOS tables complex scripts (Devanagari
conjuncts, Arabic joining forms) need for correct shaping — dropping it
produces a font that *has* the right glyphs but renders them unjoined/out of
order.

## License

All source families are Google Noto fonts under the SIL Open Font License
1.1. The unmodified license text for each family (subsetting is an
explicitly permitted modification under the OFL) is in `licenses/`,
alongside its original copyright notice.
