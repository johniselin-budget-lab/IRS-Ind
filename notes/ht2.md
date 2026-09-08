# Notes: Historic Table 2 (`state/HT2/`)

Documentation of the data and its changes over time, compiled 2026-07 from
the SOI docguides (2012, 2022 and 2023 vintages; county docguides for
intermediate years, which share the variable set) and verified directly
against the local files. TY2023 added 2026-09. Money amounts are
**$ thousands**; return counts are rounded to the nearest 10.

## What it is

Individual income tax returns (Forms 1040) tabulated by **state × AGI
class**. Returns are those filed and processed during the calendar year
following the tax year (TY2022 = returns processed during CY2023; prior-year
returns received in the window are included as a proxy for late filers).

- **One row per area × `AGI_STUB`**: stub 0 (area total) plus stubs 1–10.
- **Areas:** 50 states + DC + `OA` ("Other Areas": APO/FPO, foreign,
  territory addresses) + a `US` total row. **`PR` (Puerto Rico) is added in
  TY2018** (583 rows = 53 areas × 11 through 2017; 594 = 54 × 11 from 2018).
- Key identifiers: `N1` = returns; `MARS1/MARS2/MARS4` = single / joint /
  head-of-household return counts (added in TY2012).

## AGI stub scheme (unchanged 2012–2023)

| stub | AGI class |
|---|---|
| 0 | total (no stub) |
| 1 | Under $1 (negative AGI lives here) |
| 2 | $1 – <$10,000 |
| 3 | $10,000 – <$25,000 |
| 4 | $25,000 – <$50,000 |
| 5 | $50,000 – <$75,000 |
| 6 | $75,000 – <$100,000 |
| 7 | $100,000 – <$200,000 |
| 8 | $200,000 – <$500,000 |
| 9 | $500,000 – <$1,000,000 |
| 10 | $1,000,000+ |

This 10-class scheme began with TY2012 (the old "$1 under $25,000" class was
split that year, per the 2012 docguide "Nature of Changes"). Earlier
vintages have one fewer class.

## Variable changes by year

(From mechanical header diffs of the local files; translations from the
docguide variable tables.)

- **2012 → 2014** (2013 CSV unpublished; changes span both years): ACA items
  — `N/A85770` premium tax credit, `N/A85775` advance PTC, `N/A11560` net
  PTC, `N/A05780` excess APTC repayment, `N/A85300` net investment income
  tax (Form 8960), `N/A85530` additional Medicare tax (Form 8959), `N/A09750`
  individual-mandate payment; volunteer-prep counts `TOTAL_VITA`, `VITA`,
  `MVITA`, `TCE`.
- **2015:** + `ELDERLY` (primary taxpayer 60+), `RAC`/`RAL` refund products,
  `VITA_EIC`.
- **2016:** + Schedule A detail (`A17000` medical, `A18800` personal property
  taxes, `A19500`/`A19530`/`A19550`/`A19570` mortgage-interest detail,
  `A20800`/`A21020` miscellaneous deductions).
- **2017:** + `A11900` total overpayments, `A12000` credited-forward,
  `A20950` other non-limited misc (replaces `A21020`); prep indicators `ELF`
  (e-filed), `CPREP`, `DIR_DEP`. − `A21020`, `RAL`.
- **2018 (TCJA / 1040 redesign):** + `N/A01750` **combined** taxable
  IRA+pension (2018 only), standard-deduction detail (`A04450` total,
  `A04100` basic, `A04200` additional), **`N/A04475` QBI deduction**,
  `N/A07225` child & other dependent credit, `N/A18460` **capped SALT**
  (Sch. A:5e). − separate `A01400`/`A01700` IRA/pension, `A03230` tuition &
  fees, `A03240` DPAD, `A07220`, `A19550`, `A20800` (TCJA-suspended items).
- **2019:** separate `A01400`/`A01700` restored; − `A01750`, `A09750`
  (mandate zeroed), **`NUMDEP` dropped**.
- **2020 (COVID):** + `N/A02910` charitable-if-standard, **`N/A10970`
  recovery rebate credit, `N/A10971` EIP1, `N/A10973` EIP2**, `N/A11450`
  sick/family-leave credit, `A19550` re-added, `VRTCRIND` virtual-currency
  indicator.
- **2021:** + `N/A11520` refundable CDCTC, `N/A11530` post-3/31 leave
  credit; **`A10971` is redefined as EIP3**; − `A10973`.
- **2022:** + `N/A00400` tax-exempt interest, `N/A25870` rent/royalty net
  income, **`N/A59661–64` EITC by number of qualifying children (0/1/2/3)**;
  − all COVID-era fields.
- **2023 (Inflation Reduction Act splits Form 5695):** − `N/A07260`
  residential energy tax credit, the single pre-IRA Form 5695 total;
  + **`N/A07262` residential clean energy credit** (Sch. 3:5a) and
  **`N/A07265` energy efficient home improvement credit** (Sch. 3:5b).
  163 → 165 columns. No other variable added or dropped; `N/A11070` is
  relabelled "additional child tax credit" (was "refundable child tax credit
  or additional child tax credit") — **same code, same content**, a docguide
  label change only. A cross-year energy-credit series must treat 2023 as a
  break: 07262 + 07265 is the nearest analogue to the old 07260, not a
  continuation of it.

## The N2 relabel

`N2` = **number of exemptions** through TY2017; from **TY2018** it is
**"number of individuals"**, reconstructed from filing status and dependents
after TCJA suspended exemptions. Same column name, discontinuous series
(2018 county docguide states the rename explicitly). `NUMDEP` survives
through 2018 and disappears in 2019.

## Disclosure rules

- **Cell suppression by collapsing**: items with fewer than a threshold of
  returns in an AGI class are merged into a neighboring class within the
  same state. Threshold: **<3 returns (TY2012–2013), <10 (TY2014+)**.
  Collapsed cells are flagged `**` in the published Excel tables but **the
  CSVs carry no flag** — merges are silent.
- **Counts rounded to the nearest 10** (from TY2012).
- **HT2 state totals are authoritative**: per the docguides, "State totals
  included in SOI's ZIP Code and county data may not be comparable to those
  from Table 2" due to disclosure processing. Do not expect county/ZIP files
  to sum to HT2.

## Publication quirks

- No all-states CSV before TY2012; **TY2013 CSV never published** (per-state
  Excel only). Filename lineage: `{yy}in54cmcsv.csv` (2012–17),
  `18in55cmagi.csv` (2018 one-off, table renumbered 54→55 when PR was
  added), `{yy}in55cmcsv.csv` (2019+).
- 2012 header uses different case (`State,agi_stub` vs `STATE,AGI_STUB`).
- Numeric cells are quoted with embedded thousands separators
  (`"145,025,450"`) — parse as CSV and strip commas; naive `cut -d,` breaks.

## Gotchas for analysis

- Use **stub 0** for totals; summing stubs 1–10 differs by rounding. Exclude
  the `US` row (and remember `OA`, and `PR` from 2018) before summing states.
- Stub 1 amounts are negative (AGI less deficit).
- Small-state × high-stub cells may be silently collapsed — within-state
  stub distributions of rare items are approximate.
- `N2` breaks at 2018; `A01400`/`A01700` missing in 2018 only (use `A01750`);
  `A10971` = EIP1 in 2020 but EIP3 in 2021.
- Alaska Permanent Fund dividends are included in unemployment compensation
  (`A02300`) — affects AK and US totals.
