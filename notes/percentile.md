# Notes: State AGI percentile shares (`state/percentile/`)

Documentation of the data and its changes over time, compiled 2026-07 from
the SOI docguide PDFs (2013–2023) and verified directly against the local
files (TY2023 added 2026-09). **Units vary by year — see below before any
cross-year use.**

## What it is

SOI's "Adjusted Gross Income Percentiles by State" (`{yy}instateshares.csv`).
**One row per state** — `statefips` 00 (US) + 50 states + DC (52 rows; an
extra `OA` row appears only in 2014/2016/2017). Columns hold counts, AGI
entry cutoffs, and aggregate amounts for **descending cumulative percentile
groups** within each state: top 1, 5, 10, 25, 50, 75 percent
(`_01 … _75` suffixes).

**Population**: returns filed in the following calendar year, **excluding
dependents' returns and negative-AGI returns**; APO/FPO/foreign/territory
returns are counted in the US row only. Totals are therefore smaller than
HT2 `N1` (2022: 149.5M vs 159.7M; 2023: 150.1M vs 159.9M) and not
comparable to all-returns tabulations.

## Column structure (142-column standard layout)

- `total`, `top_xx`: return counts (total, and in each top-x% group).
- `agi_xx`: **AGI cutoff for entering each top group, whole dollars** (based
  on the nearest actual observation).
- `total_agi`, `sum_agi_xx`: aggregate AGI.
- Nine income-item blocks (`total_{item}_num/amt`, `num_/sum_{item}_xx`):
  `sal` wages, `int` taxable interest, `div` dividends, `businc` Sch. C,
  `cpgain` net capital gains, `iradist` taxable IRA, `pension` taxable
  pensions, `scorp` (**partnership AND S-corp**, despite the name).
- `total_tax`, `sum_tax_xx`: income tax after credits (floored at zero per
  return) **plus NIIT** — not comparable to HT2 `A10300` total liability.

## Changes by year

- **2013–2017 and 2019–2023**: layout identical (142 columns). **2023 is
  unchanged from 2022** — same 142 columns, same 52 rows (US + 50 + DC, no
  `OA`), same units. It is the only one of the four geographic sets the
  Form 5695 split does not touch (it carries no credit detail).
- **2018 one-off (128 columns)**: the separate IRA (`iradist`) and `pension`
  blocks (28 columns) are replaced by a combined `ira_pension` block (14
  columns) — mirroring HT2's 2018-only combined `A01750`. For a panel, 2018
  IRA and pension exist only combined.
- **2019**: exact reversal; separate blocks restored.

## Units — documented vs actual (important)

The docguides misstate units in several years. Verified against the files:

| Years | Aggregate amounts (`sum_*`, `total_*_amt`, `total_agi`, `total_tax`) |
|---|---|
| 2013, 2015, 2018–2023 | **$ thousands** |
| 2014, 2016, 2017 | **whole dollars**, with large cells exported in **Excel scientific notation (~6 significant digits)** (e.g. `1.11477E+13`) — a real precision loss in ~300 cells/year |

`agi_xx` percentile cutoffs are whole dollars in **all** years. Rescale
2014/2016/2017 by 1/1000 and tolerate the 6-digit precision when building
time series; check for `E+` cells when parsing.

## Other quirks

- Series starts TY2013 (no 2012 file) — complementing HT2, which has 2012
  but no 2013 CSV.
- `statefips` is zero-padded from 2018 (`00`,`01`,…) but unpadded 2013–2017
  — read as string.
- The `OA` (statefips 57) row appears only in 2014/2016/2017 — the same
  three years with the unit/notation anomaly (a different export path).
  Drop/handle it before sum-of-states operations.
- `agi_xx` cutoffs carry cents through 2022 (`675368.52`) but are whole
  integers in 2023 — cosmetic, but a strict type check across the panel
  will see the column change shape.
- No suppression thresholds documented; protection comes from the coarse
  state × percentile cells.

## Gotchas for analysis

- **Percentile groups are cumulative, not brackets**: `top_05` includes the
  top 1%; difference adjacent groups for brackets (bottom 25% = `total` −
  the `_75` group).
- US percentiles are computed on the national distribution — state top-x%
  groups do not aggregate to the US top-x% group; the US row also includes
  APO/FPO/foreign/territory returns absent from every state row.
- Population excludes dependent filers and negative AGI (and the associated
  AMT) — shares are conditional on that universe.
- `scorp` includes partnership income.
