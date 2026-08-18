# Notes: Nonfarm sole proprietorships (`national/sole_prop/`)

Documentation compiled 2026-08-17, verified against the local files and a
full HTTP probe of the filename grid (1,346 candidate URLs). Source:
[SOI Tax Stats — Nonfarm sole proprietorship statistics][sp].

[sp]: https://www.irs.gov/statistics/soi-tax-stats-nonfarm-sole-proprietorship-statistics

## What they are

Schedule C business activity — receipts, deductions, payroll and net income —
tabulated by **industry**, from the same individual return sample as the rest
of this repo. Tables 1–2 are the durable series and publish through **TY2023**,
a year ahead of the geographic files. Money amounts are **thousands of
dollars**. One worksheet per file (`TAB1`, `TAB2`, …).

## Table map and coverage

| Repo file | Table | Contents | Tax years (n) |
|---|---|---|---|
| `sp_t01_{year}.xls` | 1 | Business receipts, selected deductions, payroll, net income, by industrial sector | 1998–2023 (26) |
| `sp_t02_{year}.xls` | 2 | Full income statements, by industrial sector | 1998–2023 (26) |
| `sp_t03_{year}.xls` | 3 | Returns, receipts, deductions, net income by industry × **size of business receipts** | 2016–2020 (5) |
| `sp_t04_{year}.xls` | 4 | Schedule C returns: income items, credits and taxes by AGI × marital status × age × industry | 2017–2020 (4) |
| `sp_t{nn}_sic_{year}.xls` | 1–2 | The **SIC-classified** companions | 1996–1998 (3 each) |
| `sp_t02_expanded_2015.xls` | — | TY2015 one-off expanded income statement | 2015 |

68 files. Tables 3 and 4 stop at TY2020 — `21sp03szbr.xls` and `21sp04ra.xls`
were probed and are absent, so treat both as discontinued until SOI says
otherwise.

## SIC → NAICS: TY1998 published both, and the numbering hides it

**The single most important thing here.** TY1998 is the transition year and
SOI published *four* tables that year:

| File | Caption | Classification | Stored as |
|---|---|---|---|
| `98sp01ic.xls` | Table 1 | **SIC** | `sp_t01_sic_1998.xls` |
| `98sp02ic.xls` | Table 2 | **SIC** | `sp_t02_sic_1998.xls` |
| `98sp03ic.xls` | Table 3 | **NAICS** | `sp_t01_1998.xls` |
| `98sp04ic.xls` | Table 4 | **NAICS** | `sp_t02_1998.xls` |

Taking TY1998's "Table 1" at face value puts a **SIC** table into an otherwise
NAICS series and breaks a 1998–2023 panel exactly at its seam. The canonical
`sp_t{nn}_{year}` series here is therefore NAICS throughout, built from
`sp03ic`/`sp04ic` for 1998; the SIC pair is kept alongside under `_sic_`.
Verified by reading the subtitles ("Classified with the Standard Industrial
Codes" vs "… with the North American Industry Classification System"): of the
52 canonical Table 1/2 files, **none** mention SIC.

TY1996–1997 are SIC only, so they have `_sic_` files and no canonical entry.
Because TY1998 exists on both bases, it is a genuine **bridge year** — a
SIC↔NAICS crosswalk can be estimated from the overlap rather than cutting the
panel at 1999, as `alignment_plan.md` originally assumed.

From TY2005 the headers stop naming NAICS and just say "by Industrial
Sectors"; 1998–2004 spell it out. Same basis either way.

## Filename lineage

Table 1 is `{yy}sp01br.xls` and Table 2 `{yy}sp02is.xls` for TY2004–2023 (and
1999), but the intervening years each differ:

| Tax year | Table 1 | Table 2 |
|---|---|---|
| 1996 | `96spo1ig.xls` | `96sp02ig.xls` |
| 1997 | `97sp01ig.xls` | `97sp02ig.xls` |
| 1998 | `98sp03ic` (NAICS) / `98sp01ic` (SIC) | `98sp04ic` / `98sp02ic` |
| 1999 | `99sp01br.xls` | `99sp02is.xls` |
| 2000 | `00sp01is.xls` | `00sp02is.xls` |
| 2001 | `01sp01ic.xls` | `01sp02ic.xls` |
| 2002 | `02sp01is.xls` | `02sp02is.xls` |
| 2003 | `03sp01cs.xls` | `03sp02cs.xls` |
| 2004+ | `{yy}sp01br.xls` | `{yy}sp02is.xls` |

**TY1996 Table 1 is `96spo1ig.xls`** — a published typo carrying the letter
`o` where every other file has a zero, *and* a single digit where every other
file zero-pads. `96sp01ig.xls`, `96sp1ig.xls` and `96spo01ig.xls` all 404. A
zero-padded probe sweep misses this file entirely; it was found by hand.

Table 3 is `16sp03br.xls` in TY2016 but `{yy}sp03szbr.xls` from TY2017.

## The TY2015 "Table 3" is not Table 3

`15sp03isexpanded.xls` is captioned "Table 3 … **Income Statements**, by
Industrial Sectors" — that is Table **2**'s content in expanded form, not the
size-of-receipts Table 3 that begins in TY2016. It is stored as
`sp_t02_expanded_2015.xls`, named for its content rather than its caption.

## Format gotchas

- **TY1996–2003 are legacy BIFF4** (`09 04` BOF magic) and `readxl`/libxls
  cannot open them; `xlrd` reads them fine, via the `read_biff4.py` bridge
  already written for IRS-Corp. TY2004+ are ordinary OLE2 `.xls`.
- One exception: `96spo1ig.xls` (SIC Table 1, TY1996) *is* OLE2 and opens in
  `readxl`, while its TY1996 Table 2 sibling is BIFF4. Do not assume the
  format from the year alone — check the magic bytes.
- Every file is `.xls`; no `.xlsx` variant exists through TY2023.

## Known consumers

None yet. The natural join is Schedule C in the Pub 4801 line-item estimates
(see [expansion_plan.md](expansion_plan.md)) and business net income in Pub
1304 Table 1.4 — both cross-checks rather than independent series.
