# IRS-Ind

Downloader for an organized mirror of IRS SOI **individual income tax
statistics**, in two families:

- **data by geographic area** (state, county, ZIP):
  https://www.irs.gov/statistics/soi-tax-stats-data-by-geographic-area
- **national basic tables by size of AGI** (Complete Report / Pub 1304),
  which resolve the top of the distribution finely — the geographic files
  stop at a `$1M+` class, and downstream reweighting needs the finer
  national top as an anchor.

This repo holds the **code only** — data is downloaded on demand, either into
the repo's own (gitignored) `data/` folder or to a separate location of your
choosing. All source files are U.S. federal government works (public domain).
Geographic files are stored as gzipped CSVs exactly as published by SOI (no
transformation); R and most tools read `.csv.gz` directly
(`readr::read_csv('file.csv.gz')`). The national by-size tables are published
as `.xls` and stored **raw, un-gzipped** (`readxl::read_excel()` reads them
directly).

## Usage

```bash
Rscript download_irs_ind.R                        # -> ./data, years 2011-2023
Rscript download_irs_ind.R 2017 2023              # custom year range
Rscript download_irs_ind.R --dest /path/to/store  # separate destination
```

Budget Lab internal users: the canonical shared destination (already
populated, with a consolidated `NOTES.md` at its root) is documented
internally — pass it via `--dest`.

The script is idempotent (existing files are skipped; delete a file to
re-fetch), tolerates unpublished years (HTTP 404s skipped with a message),
and rewrites a checksummed `manifest.csv` (path, source URL, year, bytes,
md5, retrieval date) at the destination each run.

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
- [notes/national_bysize.md](notes/national_bysize.md) — national Complete-Report
  tables by size of AGI (table→filename map, the fine top brackets, $thousands
  units, multi-row headers, TCJA-2018 combined IRA/pension one-off)

The SOI documentation guides themselves are downloaded alongside the data
(`*docguide*` files in each destination folder).

## Coverage and source-naming quirks

| Family | Years available | SOI filename pattern |
|---|---|---|
| HT2 all-states CSV | 2012, 2014–2022 | `{yy}in54cmcsv.csv` (2012–17; 2013 unpublished), `18in55cmagi.csv` (2018, one-off), `{yy}in55cmcsv.csv` (2019+) |
| State percentile shares | 2013–2022 | `{yy}instateshares.csv` (+ `...docguide.pdf`) |
| County income | 2011, 2013–2022 | `{yy}incyallagi.csv` / `{yy}incyallnoagi.csv` (2012 and earlier are zip archives, not pulled) |
| ZIP code data | 2011–2022 | `{yy}zpallagi.csv` / `{yy}zpallnoagi.csv` |
| National by-size 1.1/1.2/1.4/2.1 | 2011–2023 | `{yy}in11si.xls` / `in12ms` / `in14ar` / `in21id` (`.xls`) |
| National by-size 1.4A (cap assets) | 2012–2023 | `{yy}in14acg.xls` (`.xls`; 2011 unpublished) |
| National by-size 2.5/3.1/3.2/3.3/3.5 | 2011–2023 | `{yy}in25ic` / `in31mt` / `in32tt` / `in33ar` / `in35tr` (`.xls`; published back to 1996–2003 under older suffixes, not pulled) |
| National by-size 1.6 / 1.7 / 2.7 / 3.1A | 2011/2012/2014/2011 –2023 | `{yy}in16ag` / `in17dp` / `in27aca` / `in31amt` (`.xls`; T1.7 starts 2012, T2.7 starts 2014) |

Other HT2 notes: the `N2` column is *number of exemptions* through tax year
2017 and *number of individuals* from 2018 (TCJA); state rows include the 50
states, DC, and PR/"other areas" (some vintages separate PR from OA).

When SOI publishes a new year, extend the range:
`Rscript download_irs_ind.R --dest <store> 2011 2024`. (The geographic files
currently trail the national by-size tables by a year: TY2022 vs TY2023.)

## Known consumers

- **Tax-Simulator state weights** (Budget-Lab-Yale/Tax-Simulator, `state-tax`
  branch): `state/HT2/` supplies the filer calibration targets for the split
  state weights; `county/` is the planned target source for sub-state
  (locality) weights — see `other/state_tax_research/` there.
- **Affordability-Index** (Budget-Lab-Yale/Affordability-Index): `state/HT2/`
  and `state/percentile/` are the state × AGI reweight targets; `national/
  by_size/` anchors the top of the distribution when adjusting top-coded /
  underreported ACS incomes — see its `docs/04_topcode_income_notes.md`.
