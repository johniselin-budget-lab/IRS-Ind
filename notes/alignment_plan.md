# Alignment plan: cross-year panels for the individual tables

Status as of 2026-08. Companion to [national_bysize.md](national_bysize.md)
(file structure, table→filename map, TCJA gotchas) and the per-family
geographic notes ([ht2.md](ht2.md), [percentile.md](percentile.md),
[county.md](county.md), [zip.md](zip.md)). Modeled on the IRS-Corp repo's
`notes/alignment_plan.md`, whose parsing engine (`alignment_helpers.R`:
sheet-to-matrix reading with a BIFF4 fallback, number-row detection, value
cleaning/flags, size-class header parsing, label aliasing verified by
seam continuity) is the intended base for all alignment work here.

Sources: [Pub 1304 by-size-of-AGI page][p1304] · geographic pages:
[HT2][ht2] · [county][county] · [ZIP][zipcode] · [state percentiles][pctl].

[p1304]: https://www.irs.gov/statistics/soi-tax-stats-individual-statistical-tables-by-size-of-adjusted-gross-income
[ht2]: https://www.irs.gov/statistics/soi-tax-stats-historic-table-2
[county]: https://www.irs.gov/statistics/soi-tax-stats-county-data
[zipcode]: https://www.irs.gov/statistics/soi-tax-stats-individual-income-tax-statistics-zip-code-data-soi
[pctl]: https://www.irs.gov/statistics/soi-tax-stats-adjusted-gross-income-agi-percentile-data-by-state

## Where things stand

The store mirrors four geographic families (CSV, already tidy: consumers
read them directly, no alignment layer needed beyond the documented variable
chronology in the notes), **14 national by-size Pub 1304 tables** (TY2011–2023,
raw `.xls`, plus Table 2.3 complete for 1996–2017), and three national
families added 2026-08-17 — IRA (213 files), sole proprietorship (68) and
Form W-2 (12) — the Pub 4801 line item estimates (27 PDFs), and the closed
sales-of-capital-assets study (73). 708 files in all. The only aligned output
so far is the line-item panel ([line_items.md](line_items.md)); the by-size
tables remain the alignment target.

## Tier 1 — align the 14 mirrored by-size tables (2011–2023)

Long panels per table, `aligned/{table}.csv` at the store, following the
IRS-Corp recipe. What the engine port has to handle (see
[national_bysize.md](national_bysize.md) "Structure / parsing"):

- **AGI-class rows × item columns** with repeating **Number of returns /
  Amount column pairs** per item — the column key is (item, measure), so
  header flattening must carry the pair structure.
- **Stacked panels**: 1.1/1.2/1.4 repeat the stub vertically for All /
  Taxable / Nontaxable returns — same shape as the corporate old Table 5
  sector blocks (truncate/section logic exists in the IRS-Corp engine).
- Fine AGI stubs (19 classes to `$10M+` in the "All returns" panel;
  sub-panels collapse the top to `$1M+`) — bounds parseable like the
  corporate asset classes.
- TCJA-2018 item drift (combined IRA+pension in 2018 only; QBI and capped
  SALT enter 2018; exemptions leave) → alias table + coverage report,
  merges adopted only after seam continuity checks.

Suggested first target: **Table 1.1** (headline income/tax items, includes
cumulative "accumulated size" rows — the Table-4-style test case), then
**3.3** (liability/credits/payments) and **3.5** (tax by rate bracket).

## Tier 2 — push the by-size tables back in time (to 1996, some 1993)

The [Pub 1304 page][p1304] carries most tables decades before our 2011
floor, under older filename suffixes (surveyed 2026-08):

| Table | Modern stub | Earlier lineage |
|---|---|---|
| 1.1 | `{yy}in11si.xls` 1996+ | 1997 published as bare `97in11.xls` |
| 1.2 | `{yy}in12ms.xls` 2001+ | `{yy}in12ar.xls` 1996–2000 (sparse); bare 1997 |
| 1.4 | `{yy}in14ar.xls` 1995+ | `{yy}in14si.xls` 1993–1996 (overlap to verify); bare 1997 |
| 2.1 | `{yy}in21id.xls` 1993+ | bare 1997 |
| 2.5 | `{yy}in25ic.xls` 1996+ | bare 1997 |
| 3.1 | `{yy}in31mt.xls` 1998+ | `{yy}in31tc.xls` 1996; bare 1997 |
| 3.2 | `{yy}in32tt.xls` 1998+ | `{yy}in32ti.xls` 1996–2002 (sparse, overlap to verify) |
| 3.3 | `{yy}in33ar.xls` 1996+ | bare 1997 |
| 3.5 | `{yy}in35tr.xls` 2003+ | `{yy}in35mt.xls` 1996–2002 |
| 1.4A / 1.6 / 1.7 / 2.7 / 3.1A | — | start 2012 / 2008 / 2012 / 2014 / 2008; no earlier history |

Work items: per-table filename maps in the downloader (the IRS-Corp
`old_file()` pattern); **format-check the 1990s vintages** (the corporate
1994–2002 files were BIFF4 — `read_biff4.py` is ready if these are too);
then the aliases/stub mapping extend naturally.

Table 2.3 (exemptions, 1996–2017) is **done** — mirrored complete as a closed
series 2026-09-09, 22 files. It is a useful dry run for the rest of this tier,
and it confirmed both expectations above: TY1997 does drop its suffix (bare
`97in23.xls`), and the 1990s vintages are BIFF4 — though **TY1997 itself is
not**, so format has to be checked per file rather than assumed from a
cut-off year. See [national_bysize.md](national_bysize.md).

## Tier 3 — geographic families back in time (a mirroring decision)

Pre-2011 geographic data exists but in bulkier shapes; each is a
download-and-store decision first, alignment second:

- **[County][county]**: 1989–2010 published as one zip archive per year
  (per-county workbooks in the oldest years, CSVs later) — extend the
  downloader with the IRS-Corp zip-extract pattern. Variable sets shrink
  going back; the county notes' chronology would need extension.
- **[ZIP code][zipcode]**: pre-2011 zips for 1998, 2001–02, 2004–2010.
  Same treatment.
- **[HT2][ht2]**: before TY2012 there is **no all-states CSV**, only
  per-state Excel workbooks (~54 files/year) — a large fan-out for modest
  gain; recommend deferring unless a consumer needs pre-2012 state × AGI.
- **[State percentiles][pctl]**: begin TY2013; nothing to push back.
- TY2023 geographic files have since landed for HT2, county and the state
  percentile shares. **ZIP code data still trails at TY2022** (re-probed
  2026-09-09); rerun the downloader when it appears.

## Proposed extension: five more SOI individual families

Sole proprietorships (Schedule C) plus the line-item estimates
(Pub 4801/5385), sales of capital assets, IRA, and Form W-2 statistics —
what to mirror, the verified filename lineages, the PDF-scraping design, and
a cross-validation harness that checks parsed line items against the Pub 1304
tables already in the store. See **[expansion_plan.md](expansion_plan.md)**.

Alignment-relevant summary: sole prop Tables 1–2 are the durable series
(NAICS 1998–2023, fresher than the geographic files) and align at sector
level like the corporate industry tables; IRA Tables 2/3/9/10 are by size or
percentile of AGI and slot into the same distributional use as the by-size
panels below.

**Update (2026-08-17):** IRA, sole proprietorship and W-2 are now mirrored
(`notes/ira.md`, `notes/sole_prop.md`, `notes/w2.md`). One correction to
Tier 2 above: the sole prop SIC era need not be cut at 1999, because TY1998
was published on **both** SIC and NAICS bases, giving a genuine bridge year
for a crosswalk.

## Recommended order

1. **Port the IRS-Corp engine and align Table 1.1** (2011–2023 first) —
   settles the Number/Amount pair handling and panel splitting that
   everything else reuses.
2. **Align 3.3 and 3.5**, then the rest of the 14 as demand dictates.
3. **Extend the by-size downloader pre-2011** (filename maps + BIFF
   format check) and stretch the aligned panels back to 1996/1993.
4. **The new families** ([expansion_plan.md](expansion_plan.md)): all five
   are mirrored, and the line-item scraper with its two check harnesses is
   built for TY2018–2023. What remains there is extraction coverage (matrix-
   layout pages, pre-2018 vintages) and Pub 5385. Sole prop sector panels
   (Tables 1–2, 1998–2023) and IRA by-AGI panels follow, reusing the same
   engine.
5. **Geographic backfill** (county, then ZIP) when a consumer needs
   pre-2011 geography; HT2 per-state fan-out only on demonstrated need.
