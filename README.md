# IRS-Ind

Downloader for an organized mirror of IRS SOI **individual income tax
statistics**:

- **data by geographic area** (state, county, ZIP):
  https://www.irs.gov/statistics/soi-tax-stats-data-by-geographic-area
- **national basic tables by size of AGI** (Complete Report / Pub 1304),
  which resolve the top of the distribution finely — the geographic files
  stop at a `$1M+` class, and downstream reweighting needs the finer
  national top as an anchor.
- **IRA accumulation and distribution** (Form 5498 matched to Form 1040):
  the only SOI series carrying IRA *balances*, TY2000–2023.
- **nonfarm sole proprietorships** (Schedule C by industry, TY1996–2023) and
  **Form W-2 statistics** (wages at the earner level, TY2014–2020).
- **line item estimates** (Pub 4801/5385, TY2003–2023): every line of every
  form and schedule, with no AGI cut. Because these share Pub 1304's weighted
  sample, they double as a cross-check on the rest of the store.
- **sales of capital assets** (the Schedule D study: gains and losses by asset
  type, month of sale and holding period, TY1985–2015, plus a 1999–2007
  panel). A closed series; Pub 1304 Table 1.4A is its live successor.

This repo holds the **code only** — data is downloaded on demand, either into
the repo's own (gitignored) `data/` folder or to a separate location of your
choosing. All source files are U.S. federal government works (public domain).
Geographic files are stored as gzipped CSVs exactly as published by SOI (no
transformation); R and most tools read `.csv.gz` directly
(`readr::read_csv('file.csv.gz')`). The national by-size tables are published
as `.xls` and stored **raw, un-gzipped** (`readxl::read_excel()` reads them
directly); the IRA tables likewise, `.xls` through TY2016 and `.xlsx` after.

## Usage

```bash
Rscript download_irs_ind.R                        # -> ./data, years 1985-2023
Rscript download_irs_ind.R 2017 2023              # custom year range
Rscript download_irs_ind.R --dest /path/to/store  # separate destination
Rscript download_irs_ind.R --only by_size         # one family only
```

Cross-check the line item estimates against the Pub 1304 tables (see
[notes/line_items.md](notes/line_items.md)):

```bash
python3 parse_line_items.py /path/to/store        # needs PyMuPDF (import fitz)
Rscript run_checks.R --dest /path/to/store        # writes checks/_report.csv
```

`parse_line_items.py` writes `aligned/line_items.csv` — every extracted line
of every form, for the validated years TY2018–2023 (10,890 values, ~57 forms
a year). `run_checks.R` then compares that panel against the Pub 1304 tables
and exits non-zero on any unexplained mismatch, so it can gate a build. Note
that `module load R/...` swaps the Python environment on this cluster — run
the two steps in separate shells.

```bash
Rscript check_arithmetic.R --dest /path/to/store  # writes checks/_arithmetic.csv
```

A second, structural check: the forms state their own arithmetic ("Add lines
1z, 2b, 3b, …"), so every subtotal can be tested against its own components
rather than only the dozen lines the crosswalk names. It is a screen rather
than a gate — most stated arithmetic is conditional per return and does not
survive aggregation — and its job is to surface the cases where a sum lands on
the wrong line. See [notes/line_items.md](notes/line_items.md).

Families for `--only` (comma-separated, default all): `geo` (the four
by-geographic-area CSV sets and their documentation guides), `by_size` (the
Pub 1304 tables), `ira` (ten IRA tables plus their precision companions),
`sole_prop` (Schedule C by industry), `w2` (Form W-2), `line_items` (the Pub
4801/5385 PDFs) and `capital_assets` (the Schedule D study). Flags may be given
in any order; the two positional arguments are the year range. Each family is
clamped to the first year it publishes, so the default run spans 1985–2023
without fetching years a family lacks.

Budget Lab internal users: the canonical shared destination (already
populated, with a consolidated `NOTES.md` at its root) is documented
internally — pass it via `--dest`.

The script is idempotent (existing files are skipped; delete a file to
re-fetch), tolerates unpublished years (HTTP 404s skipped with a message),
and rewrites a checksummed `manifest.csv` (path, source URL, year, bytes,
md5, retrieval date) at the destination each run. A narrowed run (`--only`,
or a short year range) does not truncate the manifest: rows for files it
never visited are carried over as long as those files are still on disk.

## Data layout (under the destination)

```
state/HT2/          ht2_{year}.csv.gz                 Historic Table 2: returns and income
                                                      items by state x AGI class (filers only)
state/percentile/   state_shares_{year}.csv.gz        AGI percentile data by state
                    state_shares_docguide_{year}.pdf  SOI documentation guide
county/             county_{year}_agi.csv.gz          County income data, by AGI class
                    county_{year}_noagi.csv.gz        County income data, county totals
zip/                zip_{year}_agi.csv.gz             ZIP code data, by AGI class
                    zip_{year}_noagi.csv.gz           ZIP code data, ZIP totals
national/capital_assets/ soca_t{n}_{year}.xls[x]     Sales of capital assets study:
                    soca_t{n}_1997rev.xlsx            Tables 1-4 (asset type / AGI /
                    soca_panel_{range}_t{n}.xls       month / holding period) for 1985,
                                                      1997-99, 2007-15; the revised
                                                      1997 set; two panel waves
national/line_items/ p4801_{year}.pdf                 Line item estimates: every line
                    p5385_{year}.pdf                  of every form/schedule, no AGI
                                                      cut. p5385_2018-2019.pdf is one
                                                      PDF Portfolio holding both years
aligned/            line_items.csv                    every extracted form line,
                                                      TY2018-2023 (see notes)
                    line_relations.csv                the arithmetic each form
                                                      states about itself
checks/             line_item_values.csv              cover-page totals, all vintages
                    _report.csv                       the run_checks.R report
                    _arithmetic.csv                   the check_arithmetic.R report
national/sole_prop/ sp_t{nn}_{year}.xls               Nonfarm sole proprietorships
                    sp_t{nn}_sic_{year}.xls           (Schedule C) by industry; the
                    sp_t02_expanded_2015.xls          canonical series is NAICS, _sic_
                                                      are the 1996-98 SIC companions
national/w2/        w2_all_{year}.xls                 Form W-2 statistics: wages and
                    w2_t{n}_{year}.xlsx               deferrals at the earner level.
                                                      One 51-sheet workbook to TY2018,
                                                      four slimmer ones after
national/ira/       ira_t{nn}_{year}.xls[x]           IRA accumulation and distribution:
                    ira_t{nn}_ci_{year}.xlsx          ten tables (nn = modern table
                    ira_t{nn}_cv_{year}.xlsx          number), ci = confidence intervals,
                                                      cv = coefficients of variation
national/by_size/   income_sources_{year}.xls         SOI Complete-Report (Pub 1304) basic
                    capital_assets_{year}.xls         tables by size of AGI, NATIONAL (no
                    income_tax_items_{year}.xls       geo): the fine top-of-distribution
                    marital_status_{year}.xls         anchor (AGI classes up to $10M+).
                    itemized_deductions_{year}.xls    Raw .xls.
                    returns_marital_age_{year}.xls    T1.6: counts by marital status x age
                    dependent_returns_{year}.xls      T1.7: dependent filers
                    eitc_{year}.xls                   T2.5: returns with EITC
                    aca_items_{year}.xls              T2.7: ACA items
                    modified_taxable_income_{year}.xls T3.1: by tax-computation type
                    form8615_{year}.xls               T3.1A: "kiddie tax" computations
                    tax_pct_of_agi_{year}.xls         T3.2: tax as % of AGI
                    tax_liability_{year}.xls          T3.3: liability, credits, payments
                    tax_generated_byrate_{year}.xls   T3.5: tax by marginal rate bracket
                    exemptions_{year}.xls             T2.3: exemptions by type; closed
                                                      series TY1996-2017, mirrored whole
manifest.csv        path, source url, year, bytes, md5, retrieval date
```

## Notes on the data

Per-family documentation of what each file is and how it changed over time —
variable additions/removals by year, disclosure-rule changes, unit anomalies,
and analysis gotchas — compiled from the SOI docguides and verified against
the files:

- [notes/ht2.md](notes/ht2.md) — Historic Table 2 (incl. the silent
  suppression-cell collapsing, the N2 exemptions→individuals relabel, PR
  joining in 2018)
- [notes/percentile.md](notes/percentile.md) — state AGI percentile shares
  (incl. the 2014/2016/2017 unit + scientific-notation anomaly and the 2018
  combined-IRA/pension one-off)
- [notes/county.md](notes/county.md) — county income data
- [notes/zip.md](notes/zip.md) — ZIP code data
- [notes/ira.md](notes/ira.md) — IRA accumulation and distribution (incl. the
  TY2000–2004 file-vs-table numbering break, the missing TY2003, the BIFF4
  TY2000 files `readxl` cannot open, and three files the source page fails to
  link)
- [notes/capital_assets.md](notes/capital_assets.md) — the Schedule D study
  (incl. the eight filename eras, the transposed 2010–12 stub, the "1997
  Revised" set that is really the 1998 publication's Tables 5–8, three dead
  page links, and a neighbouring file that is not capital assets at all)
- [notes/line_items.md](notes/line_items.md) — Pub 4801/5385 line item
  estimates (incl. the exact-agreement cross-check against Pub 1304 and its
  three ±1 rounding differences, the portfolio that holds two tax years, the
  attachment that only looks like one, and the per-year AGI line number)
- [notes/sole_prop.md](notes/sole_prop.md) — nonfarm sole proprietorships
  (incl. the TY1998 SIC/NAICS double publication that would otherwise break a
  panel at its seam, the `96spo1ig.xls` typo, and the TY2015 "Table 3" that is
  really Table 2)
- [notes/w2.md](notes/w2.md) — Form W-2 statistics (TY2019–2020 only;
  multi-sheet workbooks with a different sheet count per table)
- [notes/national_bysize.md](notes/national_bysize.md) — national Complete-Report
  tables by size of AGI (table→filename map, the fine top brackets, $thousands
  units, multi-row headers, TCJA-2018 combined IRA/pension one-off)
- [notes/alignment_plan.md](notes/alignment_plan.md) — the standing plan:
  aligned cross-year panels for the by-size tables, pushing them back to
  1996/1993, and geographic backfill options
- [notes/expansion_plan.md](notes/expansion_plan.md) — the standing plan for
  the families still to come: line-item estimates (Pub 4801/5385, with a
  PDF-scraping design and a harness that cross-checks them against the Pub
  1304 tables), sales of capital assets, nonfarm sole proprietorships, and
  Form W-2 statistics (IRA, its first family, is now mirrored)

The SOI documentation guides themselves are downloaded alongside the data
(`*docguide*` files in each destination folder).

## Freshness

**Last checked against irs.gov: 2026-09-09.** Nothing new had published.

- **No TY2024 files exist yet** for any family — probed the by-size, IRA, sole
  proprietorship, W-2 and geographic stubs directly. SOI typically posts the
  autumn vintages from late September, so this is the window to re-check.
- **Geographic files still trail**: HT2, county and state percentile shares
  reach TY2023; **ZIP code data still stops at TY2022** (`23zpallagi.csv`
  404s).
- **The two moving-target PDFs are unchanged.** `/pub/irs-pdf/p4801.pdf` and
  `p5385.pdf` always hold the newest tax year, so they can change content
  without changing URL; both still md5-match the TY2023 revisions recorded in
  `manifest.csv`, and no newer revision has appeared under `/pub/irs-prior/`.
- A full sweep (`--dest <store> 1985 2024`) finds nothing new. The store holds
  **708 files**; both harnesses pass at 78 exact / 1 known difference / 0
  unexplained.

To refresh: re-run that sweep, then re-verify the md5 of the two current
PDFs — those are the only files that can change underneath a stable URL.

## Coverage and source-naming quirks

| Family | Years available | SOI filename pattern |
|---|---|---|
| HT2 all-states CSV | 2012, 2014–2023 | `{yy}in54cmcsv.csv` (2012–17; 2013 unpublished), `18in55cmagi.csv` (2018, one-off), `{yy}in55cmcsv.csv` (2019+) |
| State percentile shares | 2013–2023 | `{yy}instateshares.csv` (+ `...docguide.pdf`) |
| County income | 2011, 2013–2023 | `{yy}incyallagi.csv` / `{yy}incyallnoagi.csv` (2012 and earlier are zip archives, not pulled) |
| ZIP code data | 2011–2022 (trails the rest by a year) | `{yy}zpallagi.csv` / `{yy}zpallnoagi.csv` |
| National by-size 1.1/1.2/1.4/2.1 | 2011–2023 | `{yy}in11si.xls` / `in12ms` / `in14ar` / `in21id` (`.xls`) |
| National by-size 1.4A (cap assets) | 2012–2023 | `{yy}in14acg.xls` (`.xls`; 2011 unpublished) |
| National by-size 2.5/3.1/3.2/3.3/3.5 | 2011–2023 | `{yy}in25ic` / `in31mt` / `in32tt` / `in33ar` / `in35tr` (`.xls`; published back to 1996–2003 under older suffixes, not pulled) |
| National by-size 1.6 / 3.1A | 2011–2023 | `{yy}in16ag` / `in31amt` (`.xls`; published from 2008, pulled from the repo's 2011 floor) |
| National by-size 1.7 / 2.7 | 2012–2023 / 2014–2023 | `{yy}in17dp` / `{yy}in27aca` (`.xls`; first published TY2012 and TY2014) |
| National by-size 2.3 (exemptions) | 1996–2017, complete | `{yy}in23ar.xls`, but bare `97in23.xls` for TY1997. Closed series — repealed by TCJA, TY2018 probed and absent. TY1996 and 1998–2003 are BIFF4; TY1997 is not |
| IRA tables 1–4 | 2000–2023 (no 2003) | `{yy}in{nn}ira.xls` → `.xlsx` from 2017; TY2000–2004 number files differently from tables (see notes/ira.md), TY2000 stem is `ir` |
| IRA tables 5–6 / 7 / 8 / 9–10 | 2004–2023 / 2000–02, 2004, 2013–2023 / 2017–21, 2023 / 2018–2023 | same stub; Table 8 skips TY2022 |
| IRA confidence intervals / CVs | 2022–2023 / 2018, 2020–2022 | `{yy}in{nn}iraci.xlsx` / `{yy}in{nn}ira-cv.xlsx` (CVs cover tables 1–7 only; TY2019 has none) |
| Sole prop tables 1–2 | 1998–2023 (NAICS) | `{yy}sp01br` / `{yy}sp02is` from 2004 and 1999; 2000–03 each differ; TY1998 NAICS is `98sp03ic`/`98sp04ic` (see notes/sole_prop.md) |
| Sole prop tables 1–2, SIC era | 1996–1998 | `{yy}sp01ig`/`sp02ig` (1997), `98sp01ic`/`98sp02ic`; **TY1996 Table 1 is `96spo1ig.xls`** — letter `o`, unpadded |
| Sole prop tables 3 / 4 | 2016–2020 / 2017–2020 | `16sp03br` then `{yy}sp03szbr`; `{yy}sp04ra`. Both absent from TY2021 |
| Form W-2 | 2014, 2016–2020 | `{yy}inallw2.xls` (one workbook, Tables 1–7) through 2018, then `{yy}in0{n}w2all.xlsx` (four workbooks, Tables 1–4). Note the word order flips. TY2015 and TY2021+ probed and absent; the source page links only 2019–2020 |
| Pub 4801 line items | 2003–2023 | `03linecnt` / `{YYYY}linecnt` / `{yy}inlinecount` / `p4801--{rev}` / current `p4801.pdf`; the revision token is a publication date, not derivable |
| Pub 5385 line items | 2017–2023 | `p5385--{rev}` / current `p5385.pdf`; TY2018+2019 share one URL as a PDF Portfolio |
| Capital assets Tables 1–4 | 1985, 1997–99, 2007–15 (closed) | eight stubs: `85in0{n}cg`, `97soca{n}a`, `98in{n}ab`, `99in0{n}ab`, `07in0{n}ab`, `{yy}in0{n}soca` (08–09), **`{yy}0{n}insoca`** (10–12, transposed), `{yy}in0{n}soca.xlsx` (13–15). TY2016+ probed, absent |
| Capital assets extras | 1985 T5–6; 2012 T5–9; 1997 revised; panels | `85in0{5,6}cg.xls`; `120{n}insoca.xls`; `98in{5..8}ab.xlsx` (the page's `/pub/irs-tai/` links for 6–8 are dead — `/pub/irs-soi/` has them); `99-03in0{n}..` and `04-07in01st` + `07in0{n}..` |

Other HT2 notes: the `N2` column is *number of exemptions* through tax year
2017 and *number of individuals* from 2018 (TCJA); state rows include the 50
states, DC, and PR/"other areas" (some vintages separate PR from OA).

When SOI publishes a new year, extend the range:
`Rscript download_irs_ind.R --dest <store> 2011 2024`. As of 2026-09 the
mirror runs through **TY2023 everywhere except ZIP**, which SOI has not yet
published for 2023 — re-running `--only geo 2023 2023` later will pick up
just that pair. Nothing exists for TY2024 in any family yet.

TY2023 brought one schema change to HT2 and both county files, from the
Inflation Reduction Act's split of Form 5695: `N/A07260` (residential energy
tax credit) is replaced by `N/A07262` (residential clean energy credit,
Sch. 3:5a) and `N/A07265` (energy efficient home improvement credit,
Sch. 3:5b) — 163→165 columns in HT2, 166→168 in county. `N/A11070` is
relabelled "additional child tax credit" but is the same code and content.
The state percentile shares are unchanged. See
[notes/ht2.md](notes/ht2.md) and [notes/county.md](notes/county.md).

## Known consumers

- **Tax-Simulator state weights** (Budget-Lab-Yale/Tax-Simulator, `state-tax`
  branch): `state/HT2/` supplies the filer calibration targets for the split
  state weights; `county/` is the planned target source for sub-state
  (locality) weights — see `other/state_tax_research/` there.
- **Affordability-Index** (Budget-Lab-Yale/Affordability-Index): `state/HT2/`
  and `state/percentile/` are the state × AGI reweight targets; `national/
  by_size/` anchors the top of the distribution when adjusting top-coded /
  underreported ACS incomes — see its `docs/04_topcode_income_notes.md`.
