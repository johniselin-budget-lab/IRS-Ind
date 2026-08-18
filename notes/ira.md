# Notes: IRA accumulation and distribution (`national/ira/`)

Documentation compiled 2026-08-17, verified against the local files and a
full HTTP probe of the filename grid (430 candidate URLs, 213 live). Source:
[SOI Tax Stats — Accumulation and distribution of individual retirement
arrangements][ira].

[ira]: https://www.irs.gov/statistics/soi-tax-stats-accumulation-and-distribution-of-individual-retirement-arrangements

## What they are

Ten national tables built from Form 5498 (contributions, fair market value)
matched to Form 1040 data — the only SOI series that carries **IRA balances**
rather than just the deduction and distribution lines the Pub 1304 tables
show. Tables 2, 3, 9 and 10 are cut by size or percentile of AGI, so they
join the same distributional use as `national/by_size/`. Money amounts are
**thousands of dollars**; counts are taxpayers (SOI sample estimates).

Published as `.xls` through TY2016 and `.xlsx` from TY2017. Stored **as
published**, un-gzipped.

## Table map and coverage

| Repo file | Table | Contents | Tax years (n) |
|---|---|---|---|
| `ira_t01_{year}` | 1 | IRA plans by **type of plan** | 2000–2023 (23) |
| `ira_t02_{year}` | 2 | by **size of AGI** | 2000–2023 (23) |
| `ira_t03_{year}` | 3 | by type of plan × size of AGI | 2000–2023 (23) |
| `ira_t04_{year}` | 4 | by **age of taxpayer** | 2000–2023 (23) |
| `ira_t05_{year}` | 5 | **traditional** IRA contributions by size of contribution × age | 2004–2023 (20) |
| `ira_t06_{year}` | 6 | **Roth** IRA contributions by size of contribution × age | 2004–2023 (20) |
| `ira_t07_{year}` | 7 | by **filing status and gender** | 2000–2002, 2004, 2013–2023 (15) |
| `ira_t08_{year}` | 8 | by type of plan × age | 2017–2021, 2023 (6) |
| `ira_t09_{year}` | 9 | by **increasing AGI percentile** | 2018–2023 (6) |
| `ira_t10_{year}` | 10 | by type of plan × increasing AGI percentile | 2018–2023 (6) |
| `ira_t{nn}_ci_{year}` | 1–10 | confidence intervals | 2022–2023 (2 each) |
| `ira_t{nn}_cv_{year}` | 1–7 | coefficients of variation | 2018, 2020, 2021, 2022 (4 each) |

**All year counts exclude TY2003, which SOI never published for any table** —
a real hole in the series, not a naming variant (`03in01ira.xls` 404s).

## The TY2000–2004 numbering break (read this first)

The repo filename `ira_t{nn}` is the **modern table number**, i.e. the
*content*. Through TY2004 SOI numbered its files — and the table captions
*inside* them — differently, so in those years **the number printed in the
file does not match the number in its filename**:

| Tax year | Modern table → published file slot |
|---|---|
| 2000 | 1→01, 2→02, 3→03, **4→05**, **7→04** (and the stem is `ir`, not `ira`) |
| 2001 | 1→01, 2→02, 3→03, **4→05**, **7→04** |
| 2002 | **1→06, 2→07, 3→08, 4→10, 7→09** |
| 2004 | 1→01, 2→02, 3→03, 4→04, **5→06, 6→07, 7→05** |
| 2005+ | slot = table number |

Verified by opening the files: `ira_t01_2002.xls` is captioned "Table 6 …
by Type", `ira_t07_2002.xls` is "Table 9 … by Filing Status and Gender",
`ira_t05_2004.xls` is "Table 6 … Traditional … by Size of Contribution", and
`ira_t06_2004.xls` is "Table 7 … Roth …". The grouping in the downloader
(`IRA_SLOTS`) follows content, which is what a cross-year panel needs — but
anyone quoting a table number from a pre-2005 file should quote the modern
one, and expect the caption to disagree.

TY2000 additionally drops the final `a` from the stub (`00in01ir.xls`).

## Format and parsing gotchas

- **The five TY2000 files are legacy BIFF4** (`09 04` BOF magic) and
  `readxl`/libxls cannot open them — `read_excel()` fails with "Unable to
  open file". They mirror fine and are stored as published; reading them
  needs the BIFF4 bridge already written for IRS-Corp (`read_biff4.py`).
  Every other file (208 of 213) opens with `readxl`.
- `.xls` → `.xlsx` at TY2017, with no other change to the stub.
- Table 8 is **missing for TY2022** (`22in08ira.xlsx` 404s) even though its
  confidence-interval companion `22in08iraci.xlsx` exists. Tables 9 and 10
  are present that year, so this looks like an SOI omission rather than a
  suspended table — re-probe when TY2024 lands.

## The source page under-reports what exists

Do not build the file list by scraping the page's links; probe the filename
pattern and let 404s fall through (which is what the downloader does):

- **`13in07ira.xls` is live but unlinked.** The page's Table 7 block starts at
  2014, so the series actually begins **TY2013**, not 2014.
- **TY2022 coefficient-of-variation files are live but unlinked** (all seven
  of `22in{01..07}ira-cv.xlsx`). The page lists CV files only for 2018–2021.
- **The page's TY2019 "CV" links point at the data files themselves**
  (`19in01ira.xlsx`, not `-cv`). `19in01ira-cv.xlsx` 404s: TY2019 genuinely
  has no CV files, so there is nothing to mirror there.

## Known consumers

None yet. Tables 2/3/9/10 (by AGI size and percentile) are the natural join
to the `national/by_size/` distributional work; Tables 5/6 carry contribution
behaviour that Pub 1304 does not.
