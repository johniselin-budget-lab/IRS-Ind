# Notes: National tables by size of AGI (`national/by_size/`)

Documentation compiled 2026-07, verified against the local files. These are
**national** SOI tables (no geography), unlike the rest of this repo's
by-geographic-area files. They are carried because they are the
**distributional backbone the geographic files lack**: HT2 stops at a single
`$1,000,000+` state class, but these resolve AGI up to `$10,000,000+` with full
sources of income, so they anchor the top of the distribution when the
state × AGI files are reweighted onto survey microdata (see "Known consumers").

## What they are

SOI **Complete Report (Publication 1304) basic tables**, "Returns filed and
sources of income … by size of adjusted gross income," published each fall for
the prior tax year. Downloaded **as published (`.xls`, not CSV)** and stored
**raw, un-gzipped** — `readxl::read_excel()` reads `.xls` directly, and gzip
would break that. Money amounts are **$ thousands**; return counts are numbers
of returns (SOI sample estimates, not a full count).

## Table → filename map

| Repo file | SOI table | SOI source stub | Contents |
|---|---|---|---|
| `income_sources_{year}.xls`     | **1.4**  | `{yy}in14ar.xls`  | Sources of income, adjustments, deductions, exemptions, tax — every income line by AGI class |
| `capital_assets_{year}.xls`     | **1.4A** | `{yy}in14acg.xls` | Sales of capital assets (Sch. D) detail: short/long-term gain & loss by AGI class |
| `income_tax_items_{year}.xls`   | **1.1**  | `{yy}in11si.xls`  | Selected income & tax items; AGI, taxable income, tax after credits — with **cumulative** ("accumulated size") rows |
| `marital_status_{year}.xls`     | **1.2**  | `{yy}in12ms.xls`  | Sources of income cross-tabulated by **marital/filing status** × AGI class |
| `itemized_deductions_{year}.xls`| **2.1**  | `{yy}in21id.xls`  | Itemized deductions in detail by AGI class |

## AGI size classes (Table 1.4, TY2022 — the fine top end is the point)

Left stub, "All returns" panel (rows ~9–28): `No AGI` · `$1–5k` · `5–10` ·
`10–15` · `15–20` · `20–25` · `25–30` · `30–40` · `40–50` · `50–75` · `75–100` ·
`100–200` · `200–500` · `500–1,000` · **`1,000–1,500`** · **`1,500–2,000`** ·
**`2,000–5,000`** · **`5,000–10,000`** · **`10,000+`** (all $thousands). Six
classes above $500k, versus HT2's single `$1M+`. The `Taxable returns` and
`Nontaxable returns` sub-panels that follow collapse the top back to `$1M+`.

## Structure / parsing

- **Multi-row header band** (rows ~3–8): a group label row, sub-labels, then a
  repeating **`Number of returns` / `Amount`** pair per income item. Column
  count is large (1.4 ≈ 153, 1.4A ≈ 120, 1.1 ≈ 21). Flatten the header
  yourself; there is no tidy machine header row.
- **Three panels** in 1.4/1.2 (All / Taxable / Nontaxable returns) stacked
  vertically — filter to the panel you want by the stub label.
- AGI is "less deficit" (negative-AGI returns sit in `No AGI` / stub 1).

## Coverage & year gotchas

- **1.1, 1.2, 1.4, 2.1: TY2011–2022. 1.4A: TY2012–2022** (2011 not published;
  the downloader 404-skips it).
- **TCJA (TY2018):** IRA and pension distributions appear **combined** in 2018
  (mirrors the HT2 `A01750` and state-percentile one-offs); separate lines
  return in 2019. QBI deduction and the capped SALT enter 2018; personal
  exemptions disappear.
- Disclosure: small cells flagged `*`/`**` and sometimes combined; footnotes
  live in the bottom rows of each sheet.
- File format has stayed `.xls` (not `.xlsx`) through 2022 — the `.xlsx` URL
  404s. Re-verify the naming when extending to newer years.

## Known consumers

- **Affordability-Index** (Budget-Lab-Yale/Affordability-Index): the national
  top-of-distribution anchor for adjusting top-coded/underreported ACS incomes
  before state × AGI reweighting — see its `docs/04_topcode_income_notes.md`.
