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
[soleprop]: https://www.irs.gov/statistics/soi-tax-stats-nonfarm-sole-proprietorship-statistics

## Where things stand

The store mirrors five families — four geographic (CSV, already tidy:
consumers read them directly, no alignment layer needed beyond the
documented variable chronology in the notes) and **14 national by-size
Pub 1304 tables** (TY2011–2023, raw `.xls`). Unlike IRS-Corp, there are
**no aligned panels yet** — the by-size tables are the alignment target.

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
then the aliases/stub mapping extend naturally. Table 2.3 (exemptions,
1996–2017) could be mirrored as a closed series — discontinued by TCJA.

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
- TY2023 geographic files were not yet published as of 2026-08 — rerun the
  downloader when they land (the by-size tables already carry TY2023).

## Proposed extension: nonfarm sole proprietorships (Schedule C)

Schedule C filers are individual income tax — this belongs in IRS-Ind
(suggested layout: `national/sole_prop/`), from the [nonfarm sole
proprietorship page][soleprop] (surveyed 2026-08):

| Table | Files | Coverage | Alignment prospect |
|---|---|---|---|
| Table 1: receipts, deductions, payroll, net income by NAICS sector | `{yy}sp01br.xls` | 1999–2023 (n=21; naming variants `sp01is`/`sp01ic`/`sp01cs` in 2000–03 to reconcile) | sector-level: ~21 stable NAICS sectors — same treatment as the corporate Tier 1 easy variant |
| Table 2: full income statements by sector | `{yy}sp02is.xls` | 1999–2023 (n=23) | same; item stubs are an income-statement set (alias table needed) |
| SIC-era Tables 1–2 | `{yy}sp01ig` / `sp02ig` etc. | 1996–1998 | SIC → cut at 1999 or division-level bridge only |
| Table 3: by industry × size of business receipts | `{yy}sp03szbr.xls` (+ `16sp03br.xls`) | 2016–2020 | short-lived; mirror, align only if continued |
| Table 4: Schedule C returns by AGI × marital status × age × industry | `{yy}sp04ra.xls` | 2017–2020 | short-lived; mirror as-is |

Notes: Tables 1–2 are the durable series and publish through **TY2023**
(fresher than the geographic files). A 2015 one-off "expanded" income
statement (`15sp03isexpanded.xls`) exists. Whether Tables 3/4 are
discontinued or just slow needs a check against newer SOI Bulletin
releases before promising a panel.

## Recommended order

1. **Port the IRS-Corp engine and align Table 1.1** (2011–2023 first) —
   settles the Number/Amount pair handling and panel splitting that
   everything else reuses.
2. **Align 3.3 and 3.5**, then the rest of the 14 as demand dictates.
3. **Extend the by-size downloader pre-2011** (filename maps + BIFF
   format check) and stretch the aligned panels back to 1996/1993.
4. **Sole proprietorship family**: downloader + store for Tables 1–4,
   then sector-level panels for Tables 1–2 (1999–2023).
5. **Geographic backfill** (county, then ZIP) when a consumer needs
   pre-2011 geography; HT2 per-state fan-out only on demonstrated need.
