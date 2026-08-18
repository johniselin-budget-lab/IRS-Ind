# Expansion plan: five more SOI individual families

Standing plan for adding five SOI programs to this repo. Companion to
[alignment_plan.md](alignment_plan.md) (which covers panel-building for the
tables already mirrored) — this document covers **what to mirror next and
how**, plus the PDF-scraping and cross-validation machinery the line-item
publications need.

Source pages surveyed and every filename below **probed with HTTP HEAD on
2026-08-17**; 404s noted where the page's own links are wrong or a year is
genuinely absent. Re-verify before implementing — SOI renames files.

Sources: [line-item estimates (Pub 4801/5385)][li] · [sales of capital
assets][soca] · [nonfarm sole proprietorships][sp] · [IRA accumulation and
distribution][ira] · [Form W-2 statistics][w2].

[li]: https://www.irs.gov/statistics/soi-tax-stats-individual-income-tax-returns-line-item-estimates-publications-4801-and-5385
[soca]: https://www.irs.gov/statistics/soi-tax-stats-sales-of-capital-assets-reported-on-individual-tax-returns
[sp]: https://www.irs.gov/statistics/soi-tax-stats-nonfarm-sole-proprietorship-statistics
[ira]: https://www.irs.gov/statistics/soi-tax-stats-accumulation-and-distribution-of-individual-retirement-arrangements
[w2]: https://www.irs.gov/statistics/soi-tax-stats-individual-information-return-form-w2-statistics
[p1304]: https://www.irs.gov/statistics/soi-tax-stats-individual-statistical-tables-by-size-of-adjusted-gross-income

## Summary

| Family | Coverage | Live? | Format | Files | Effort |
|---|---|---|---|---|---|
| Line items, Pub 4801 (individual) | TY2003–2023 | yes | PDF (form facsimiles) | 21 | high — scraper |
| Line items, Pub 5385 (info returns) | TY2017–2023 | yes | PDF (one is a portfolio) | 6 URLs / 7 years | high — scraper |
| Sales of capital assets | 1985, 1997–1999, 2007–2015 (+ panels) | **no, ends TY2015** | xls/xlsx | ~70 | low |
| Nonfarm sole proprietorship | T1/T2 1996–2023; T3/T4 2017–2020 | yes (T1/T2) | xls | ~70 | low |
| IRA accumulation/distribution | T1–T4 2000–2023 (no 2003); T5–T10 shorter | yes | xls → xlsx 2017+ | 213 | **done** |
| Form W-2 statistics | TY2019–2020 only | stalled | xlsx | 8 | trivial |

Three of the five are pure download-and-document work. The line-item
publications are the substantial build, and they are also the piece that pays
for itself: **Pub 4801 shares the weighted SOI sample with Pub 1304**, so it
validates everything else in the store.

## Why the line-item estimates come first

Pub 4801 prints, on a facsimile of each 1040 form and schedule, the estimated
**number of returns** and **amount** for every line — far more line detail than
Pub 1304, but with no AGI dimension. Confirmed against the local store
(TY2023, `national/by_size/income_tax_items_2023.xls`, Table 1.1 "All returns"):

| Item | Pub 4801 (TY2023) | Pub 1304 T1.1 | Match |
|---|---|---|---|
| Total returns filed | 160,602,107 | 160,602,107 | exact |
| AGI (1040 line 11, $000) | 15,286,017,359 | 15,286,017,359 | exact |

That is the same weighted estimate, not two independent ones. So the harness
below should assert **equality, not tolerance** — any difference is a parse bug
or an SOI revision, and either is worth knowing. That makes Pub 4801 a
regression test for every parser this repo grows, including the by-size
aligners in [alignment_plan.md](alignment_plan.md).

## 1. Line item estimates (Pub 4801 and 5385)

### Source map — Pub 4801 (individual income tax returns)

Three filename eras plus a moving current-revision URL:

| Tax years | Pattern | Directory |
|---|---|---|
| 2003 | `03linecnt.pdf` | `/pub/irs-soi` |
| 2004–2007 | `{YYYY}linecnt.pdf` | `/pub/irs-soi` |
| 2008–2016 | `{yy}inlinecount.pdf` | `/pub/irs-soi` |
| 2017–2022 | `p4801--{rev}.pdf` | `/pub/irs-prior` |
| 2023 (current) | `p4801.pdf` | `/pub/irs-pdf` |

The `{rev}` token is a publication date, not a tax year, and cannot be derived:
2017→`2019`, 2018→`2020`, 2019→`2021`, 2020→`2022`, 2021→`2024`,
2022→`122024`. Hardcode the map; the source page is the only authority.

### Source map — Pub 5385 (individual information returns)

2017→`p5385--2019`, 2018 **and** 2019→`p5385--2021`, 2020→`p5385--2023`,
2021→`p5385--2024`, 2022→`p5385--042025` (all `/pub/irs-prior`), 2023→
`/pub/irs-pdf/p5385.pdf`. Also linked but unused on the page: `p5385--2019`.

### Gotchas verified 2026-08-17

- **`p5385--2021.pdf` is a PDF Portfolio, not a document.** One page of "open
  this in Acrobat" boilerplate wrapping three embedded files:
  `p5385--2021-10-00.pdf` (cover year **2018**, 94 pp),
  `p5385--2021-11-00.pdf` (cover year **2019**, 94 pp), and a portfolio
  chrome file. That is why the page links two tax years to one URL. The
  reader must unwrap embedded files (`fitz.Document.embfile_get`) and route
  each by its cover year. Check every vintage for this, not just 2021.
- **`/pub/irs-pdf/p4801.pdf` is a moving target.** It always holds the newest
  tax year; when TY2024 publishes, the same URL changes content and the TY2023
  revision migrates to `/pub/irs-prior/`. Store it under the tax year read
  from its own cover page, and let `manifest.csv`'s md5 catch a silent swap.
- **Text layer present in every vintage back to TY2003** (spot-checked 2003,
  2008, 2016, 2017, 2023: ~67k characters in the first 20 pages each). No OCR
  needed. Cover-page year is machine-readable from TY2016 on; 2003 and 2008
  covers carry no year text, so fall back to the table of contents.

### Page structure and extraction design

Each data page is a vector facsimile of the real form with the estimate
printed in the line's entry box (TY2023 p4801: 236 pages, 0 raster images,
~376 vector drawings/page). Even pages carry **number of returns**, odd pages
the corresponding **amount in $ thousands** — stated in the publication's own
preamble and confirmed by the values.

**Anchor on the form's drawn entry boxes, not on an "entry column".** A spike
on the TY2023 Form 1040 pages (2026-08-17) settled this; three things kill the
column approach:

- the 1040 has **two** entry columns — a mid-page box for lines 2a–6a
  (x 257.4–328.1) and the right-margin box (x 504.8–575.5) — and other forms
  have more;
- estimates are **not** reliably right-aligned inside their box (right edges
  wander 554–576 pt with digit count), so clustering right edges silently
  drops short values — line 1f = 516 was lost this way;
- column x-positions shift ~2.5 pt between facing pages, so nothing can be
  hardcoded.

The drawn boxes, by contrast, are exactly regular: one 11.1 pt-tall rectangle
per line, read straight from `page.get_drawings()`. Anchoring on them also
discards body-text numerals ("Form 8995", "Schedule 1, line 26", "January 2,
1959") for free, with no filtering rules.

Proposed helper: **`parse_line_items.py`**, Python + PyMuPDF (`import fitz` —
already installed on this cluster; R's `pdftools` needs the `poppler` module
and gives poorer word-position access). This follows the existing precedent of
Python helpers beside R aligners in IRS-Corp (`read_biff4.py`,
`read_xls_merges.py`), called from an R driver `align_line_items.R`.

Algorithm:

1. Open the PDF; if `embfile_count() > 0`, unwrap and process each embedded
   document separately, keyed by its cover-page year.
2. Read the TOC pages (3–6 in the TY2023 vintage) to map *section* → *printed
   page*, then resolve printed page → PDF page index by offset. Cross-check
   against each page's own running header rather than trusting either alone.
3. Per page: read the entry boxes from `get_drawings()` (rects ~25–130 pt
   wide, 7–16 pt tall). A **value** is a numeric token whose centre falls
   inside a box; its **line label** is the nearest `^\d{1,2}[a-z]?$` token to
   the left of that box on the same rows. Skip a token that is itself a label
   — line 7's "check here" checkbox is a drawn box containing its own label.
   Keep the row's left-hand text as `line_text` (best effort — useful for
   matching across years when lines renumber).
4. Emit values whose box has **no** label to the left as a separate stream,
   don't drop them: on the 1040 page these are the filing-status counts
   (Single 80,288,820 · MFJ 54,491,797 · MFS 4,139,858 · HOH 21,604,490 ·
   QSS 77,143 — summing to the published total return count) and the
   dependants grid. They cross-check Table 1.2 and are worth having.
5. Assert against Pub 1304 before emitting anything (see the harness below).

Output: one long CSV, `aligned/line_items.csv` —

```
tax_year, publication, universe, form, line, line_text, measure, value, pdf_page, source_file
```

`publication` ∈ {4801, 5385}; `universe` ∈ {all returns, electronically filed}
(Pub 4801 prints both for the 1040 itself); `measure` ∈ {returns, amount};
amounts in $ thousands, matching Pub 1304.

### Year tiers (layout stability is the risk, not the PDF)

- **Tier A — TY2018–2023.** Post-TCJA redesigned 1040 plus Schedules 1–3;
  most stable geometry. Build and validate here first.
- **Tier B — TY2008–2017.** Old 1040 layout, no Schedules 1–3; line numbering
  differs throughout. Same parser, different column thresholds — derive
  thresholds per year from the data rather than hardcoding.
- **Tier C — TY2003–2007.** Different publication series (`linecnt`), layout
  unverified beyond the text layer. Attempt only after A and B pay off.

## 2. Cross-check harness (the reason to do this at all)

`checks/crosswalk_line_items.csv` — a hand-curated, version-controlled map from
(publication, form, line, measure) to a target elsewhere in the store. Starter
set, all against Pub 1304 "All returns" totals:

| 4801 form/line | Target | Table |
|---|---|---|
| 1040 1a — wages | Salaries and wages | T1.4 |
| 1040 2b — taxable interest | Taxable interest | T1.4 |
| 1040 3b — ordinary dividends | Ordinary dividends | T1.4 |
| 1040 7 — capital gain/loss | Net capital gain (less loss) | T1.4, T1.4A |
| 1040 11 — AGI | AGI less deficit | T1.1 |
| 1040 12 — deduction | Standard / total itemized | T1.1, T2.1 |
| 1040 13 — QBI deduction | Qualified business income deduction | T1.4 (2018+) |
| 1040 15 — taxable income | Taxable income | T1.1, T3.1 |
| 1040 24 — total tax | Total tax liability | T3.3 |
| Sch 1 3 — business income | Business net income less loss | T1.4; sole prop T2 |
| Sch C totals | Receipts, deductions, net income | sole prop T1/T2 |
| Sch D totals | Short/long-term gain and loss | T1.4A; SOCA T1 (≤2015) |
| 1040 4a/4b, 5a/5b — IRA/pension | IRA and pension distributions | T1.4; IRA T1/T2 |
| 1040 27 — EITC | Earned income credit | T2.5 |
| 5385 W-2 boxes | Wage and deferral totals | W-2 T1/T2; T1.4 wages |

Driver `run_checks.R` writes `checks/_report.csv` (tax_year, item, source
value, target value, difference, pct, status). Rules:

- Same-universe items: **exact equality required**; a nonzero difference is a
  finding, not a tolerance to widen.
- Known-different-universe items get an explicit `expected_relation` column
  (e.g. `<=`) with the reason recorded — never a silent fudge factor.
- TY2018 IRA/pension is combined in Pub 1304 (see
  [national_bysize.md](national_bysize.md)); the crosswalk needs a year-scoped
  row for it.

This harness is worth building even before the scraper is complete: the
2-row TY2023 check above already runs.

### Spike result (2026-08-17)

Both TY2023 Form 1040 pages parsed in full — 28 lines (1a–1h, 1z, 2a/2b
through 6a/6b, 7–15) on each of the returns and amounts pages — and checked
against Tables 1.1 and 1.4: **27 of 27 crosswalk items matched exactly**,
including every individual wage component. Table 1.4 turns out to carry
lines 1a, 1b, 1c, 1e, 1g and 1h as separate column pairs, so the crosswalk
for the wages block is nearly 1:1 rather than aggregate-only.

Two traps the spike exposed, both on the Pub 1304 side:

- **Merged-cell headers.** The item name spans the Number-of-returns / Amount
  pair, so `readxl` gives it to the first column only and every Amount column
  flattens to an indistinguishable `Amount | n`. Forward-fill the item name
  across the pair and keep the published column number as a stable anchor.
- **Panel-scoped columns.** Table 1.1's taxable-income columns sit inside its
  *Taxable returns* panel, so they exclude returns with positive taxable
  income but no tax after credits — an 18.4 million-return, $319 billion gap
  against the 1040's line 15. The all-returns equivalent is Table 1.4
  col 141/142. **Every crosswalk row must name the panel, not just the item.**
  The harness caught this as a MISMATCH, which is the point.

## 3. Sales of capital assets — closed at TY2015

**Answer to "is there more up-to-date data": no, not in this program.** Probed
`16in01soca.{xls,xlsx}`, `1601insoca.xls`, `17in01soca.{xls,xlsx}`,
`18in01soca.xlsx` — all 404. The dedicated SOI study stops at **TY2015**, and
the last SOI Bulletin article (covering 2013–2015) is inside
`/pub/irs-prior/p1136--2022.pdf`.

Fresher capital-gains detail already in or near this repo:

- **Pub 1304 Table 1.4A** — `national/by_size/capital_assets_{year}.xls`,
  **TY2012–2023** (`23in14acg.xls` verified live). Short/long-term gains and
  losses by AGI class. This is the live successor; what it does *not* carry is
  SOCA's asset type, month of sale, and holding-period detail.
- Pub 1304 Table 1.4's capital-gain line, and the geographic `A01000` series.
- The SOI Sales of Capital Assets **panel** (1999–2003, 2004–2007) and the
  Individual PUF — the latter restricted; a sibling store already exists at
  `raw_data/IRS-PUF`.

Recommendation: **mirror SOCA as a closed historical series** and document 1.4A
as the live successor in both notes files, so a future reader does not go
looking for TY2016+.

Coverage: cross-section Tables 1–4 for 1985, 1997 (+ a revised 1997 set),
1998, 1999, and 2007–2015 — **no 2000–2006**. Tables 5–9 (stratum definitions
and coefficients of variation) exist for TY2012 only. Panel tables cover
1999–2003 and 2004–2007.

Filename eras, per table `{n}`: `{yy}in0{n}soca.xlsx` (2013–2015),
`{yy}0{n}insoca.xls` (2010–2012 — note the transposed year/table), 
`{yy}in0{n}soca.xls` (2008–2009), `{yy}in0{n}ab.xls` (2007),
`{yy}in0{n}ab.xlsx` (1999), `98in{n}ab.xlsx` (1998), `97soca{n}a.xlsx` (1997),
`85in0{n}cg.xlsx` (1985). **The revised 1997 files live under `/pub/irs-tai/`,
not `/pub/irs-soi`** (e.g. `/pub/irs-tai/98in5ab.xlsx`) — see the downloader
change below.

## 4. Nonfarm sole proprietorships (Schedule C)

Supersedes the proposal sketched in [alignment_plan.md](alignment_plan.md);
the year→filename lineage below is now verified.

- **Table 1** (business receipts, selected deductions, payroll, net income by
  NAICS sector): `{yy}sp01br.xls` for 1999–2023, then per-year one-offs —
  2003 `03sp01cs`, 2002 `02sp01is`, 2001 `01sp01ic`, 2000 `00sp01is`. SIC era:
  1998 `98sp01ic` (and `98sp03ic`), 1997 `97sp01ig`, 1996 **`96spo1ig.xls`** —
  a published typo (letter `o`, not zero); `96sp01ig.xls` 404s.
- **Table 2** (full income statements by sector): `{yy}sp02is.xls` 1999–2023,
  with 2003 `03sp02cs`, 2001 `01sp02ic`; SIC era 1998 `98sp02ic`/`98sp04ic`,
  1997 `97sp02ig`, 1996 `96sp02ig`. Plus a one-off
  `15sp03isexpanded.xls` (TY2015 expanded income statement).
- **Table 3** (by industry × size of business receipts): `{yy}sp03szbr.xls`
  2017–2020, plus `16sp03br.xls` for 2016. `21sp03szbr.xls` 404s — the series
  stops at TY2020.
- **Table 4** (Schedule C returns by AGI × marital status × age × industry):
  `{yy}sp04ra.xls` 2017–2020 only; `21sp04ra.xls` 404s.
- Bulletin articles 1996–2022 (mixed `soi-a-insp-id{nnnn}.pdf`,
  `soi-a-inpr-id{nnnn}.pdf`, and two years inside `p1136--{yyyy}.pdf`).

Tables 1–2 are the durable series and publish through **TY2023** — fresher
than the geographic files. Align at NAICS sector level, exactly as IRS-Corp
does its industry tables; cut the SIC era (1996–1998) out of the panel or
bridge only at division level.

## 5. IRA accumulation and distribution

Ten tables, live through **TY2023**, `.xls` through 2016 and `.xlsx` from 2017:
`{yy}in{nn}ira.{xls,xlsx}`.

| Table | Contents | Years |
|---|---|---|
| 1 | IRA plans by type | 2000–2002, 2004–2023 |
| 2 | by size of AGI | same |
| 3 | by type × size of AGI | same |
| 4 | by taxpayer age | same |
| 5 | traditional IRA contributions by size and age | 2004–2023 |
| 6 | Roth IRA contributions by size and age | 2004–2016 linked, plus 2017–2023 |
| 7 | by filing status and gender | 2000–2002, 2004, 2014–2023 |
| 8 | by type and age | 2017–2021, 2023 |
| 9 | by AGI percentile | 2018–2023 |
| 10 | by type and AGI percentile | 2018–2023 |

Companion precision files: **confidence intervals** `{yy}in{nn}iraci.xlsx` for
TY2022–2023 (all ten tables), **coefficients of variation**
`{yy}in{nn}ira-cv.xlsx` for TY2018, 2020, 2021 (Tables 1–7).

Gotchas verified 2026-08-17:

- **TY2003 is absent entirely** (`03in01ira.xls` 404s) — a real hole, not a
  naming variant.
- **TY2002 renumbers**: Table 1 is `02in06ira.xls`, T2 `02in07ira`,
  T3 `02in08ira`, T7 `02in09ira`, T4 `02in10ira`. TY2001 and TY2004 shift too
  (T5 is `04in06ira`, T6 is `04in07ira`). TY2000 drops the final `a`:
  `00in01ir.xls`.
- **The page's TY2019 CV links point at the data files themselves**
  (`19in01ira.xlsx`, not `-cv`); `19in01ira-cv.xlsx` 404s. TY2019 has no CV
  file — do not mirror one.
- **Table 8 TY2022 is missing** (`22in08ira.xlsx` 404s) even though its
  confidence-interval companion `22in08iraci.xlsx` exists (200).
- **The page under-links what exists**: `14in06ira.xls` returns 200 but appears
  nowhere on the page. Probe the filename pattern for every year rather than
  scraping the link list, and let 404s fall through as the downloader already
  does.

Tables 2, 3, 9, and 10 are by size or percentile of AGI, so they slot straight
into the same distributional use as `national/by_size/`, and Tables 5/6 give
contribution behavior the Pub 1304 tables do not carry.

## 6. Form W-2 statistics — stalled at TY2020

Four tables, TY2019 and TY2020 only: `{yy}in0{n}w2all.xlsx`. Probed
`21in01w2all.{xlsx,xls}`, `22in01w2all.xlsx`, `21in02w2all.xlsx` — all 404.

Table 1 (wage income by age, sex, size of wages, size of AGI, return/earner
type, multiple of the OASDI limit), Table 2 (elective retirement
contributions, incl. taxpayers at the maximum), Table 3 (retirement-plan
indicator), Table 4 (items by spousal presence of contributions, percentiles,
plan type). Eight files total — mirror them now, note the series as stalled,
and re-probe when TY2021 appears. The overlap with Pub 5385's W-2 boxes makes
these a second validation target rather than a standalone build.

## 7. Changes the downloader needs

`download_irs_ind.R` currently hardcodes one base URL and builds every target
from `sprintf` patterns over a year loop. Four changes, in order:

1. **Per-target base URL.** Add an optional `base` field to each target,
   defaulting to `https://www.irs.gov/pub/irs-soi`. Needed for `/pub/irs-pdf`
   (current Pub 4801/5385), `/pub/irs-prior` (prior revisions, bulletin
   articles) and `/pub/irs-tai` (revised 1997 SOCA files).
2. **Explicit year→filename maps** where `sprintf` cannot express the lineage —
   Pub 4801/5385 revisions, IRA's renumbered early years, sole prop's
   1996–2003 variants, SOCA's five eras. Follow the IRS-Corp `old_file()`
   pattern: a named vector per table, `sprintf` fallback for the modern era.
3. **Non-year-keyed targets.** SOCA panel files (`99-03in01st.xls`,
   `04-07in01st.xls`), the TY2012-only CV tables, and the 1985 one-offs are
   not year-loop members. Add a small `static_targets()` list fetched once per
   run, outside the year loop.
4. **`--only <family>[,<family>]`.** With five more families the full run gets
   long and mostly re-checks files that never change. Families:
   `geo`, `by_size`, `line_items`, `capital_assets`, `sole_prop`, `ira`, `w2`.

Keep it one script and base-R only — that constraint is what makes this repo
easy to run anywhere, and none of the above breaks it.

## 8. Proposed layout under the destination

```
national/line_items/     p4801_{year}.pdf          Individual line-item estimates, TY2003-2023
                         p5385_{year}.pdf          Information-return line items, TY2017-2023
                                                   (2018/2019 unwrapped from one portfolio)
national/capital_assets/ soca_t{n}_{year}.xls[x]   Tables 1-4, 1985/1997-1999/2007-2015
                         soca_cv_t{n}_2012.xls     Tables 5-9, TY2012 only
                         soca_panel_{range}_t{n}.xls  1999-2003 and 2004-2007 panels
national/sole_prop/      sp_t{n}_{year}.xls        Tables 1-2 (1996-2023), 3-4 (2017-2020)
national/ira/            ira_t{nn}_{year}.xls[x]   Tables 1-10
                         ira_t{nn}_ci_{year}.xlsx  confidence intervals, 2022-2023
                         ira_t{nn}_cv_{year}.xlsx  coefficients of variation, 2018/2020/2021
national/w2/             w2_t{n}_{year}.xlsx       Tables 1-4, TY2019-2020
aligned/line_items.csv                             parsed Pub 4801/5385 (long)
checks/crosswalk_line_items.csv                    curated validation map
checks/_report.csv                                 check results
```

Table-numbered filenames (zero-padded for IRA so listings sort) rather than the
descriptive names used in `national/by_size/`: these are numbered series of up
to ten tables whose descriptive titles run to a full sentence. The table→title
map belongs in the per-family notes, as IRS-Corp does it. Store files **as
published** (no gzip, original extension) — consistent with `by_size/`.

Rough footprint: line items ~28 PDFs × ~4 MB ≈ 120 MB; the four spreadsheet
families ≈ 400 files, well under 200 MB.

## 9. Sequencing

1. **Downloader refactor** (§7) — prerequisite for everything, half a day.
2. **Mirror the three easy families**: IRA (**done** 2026-08-17 — 213 files,
   `notes/ira.md`), then sole proprietorship and W-2. Pure download plus one
   notes file each in the style of `notes/ht2.md`.
3. **Mirror capital assets** as a closed series; add the TY2016+ successor
   note to `notes/national_bysize.md` so 1.4A is findable from both directions.
4. **Mirror Pub 4801/5385 PDFs** and stand up the check harness on the two
   items that already validate (total returns, AGI) — proves the plumbing
   before the parser exists.
5. **Build `parse_line_items.py` + `align_line_items.R` for Tier A**
   (TY2018–2023), gated on the crosswalk passing exactly. This is the bulk of
   the work.
6. **Extend the crosswalk** to Schedule C ↔ sole prop, Schedule D ↔ 1.4A/SOCA,
   IRA lines ↔ IRA tables, Pub 5385 ↔ W-2 tables. Each new family then arrives
   with a validation story rather than on trust.
7. **Tier B then Tier C** line-item years; sole prop and IRA sector/AGI panels
   using the IRS-Corp engine, interleaved with the by-size work in
   [alignment_plan.md](alignment_plan.md).

## 10. Open questions

- Does Pub 4801's "returns filed" universe match Pub 1304's exactly in every
  year, or only in TY2023 where it was checked? Run the two-item check across
  all overlapping years before trusting equality as the harness rule.
- Are Pub 4801's electronically-filed panels worth carrying, or is the
  all-returns universe sufficient for the intended consumers?
- Sole prop Tables 3/4 and the W-2 tables: discontinued or merely slow? Check
  the SOI Bulletin release schedule before promising anyone a panel.
- Which consumer needs these first? `by_size/` was pulled for
  Affordability-Index and Tax-Simulator; naming the consumer for the IRA and
  sole prop tables would settle whether alignment (§9.7) is worth doing now.
