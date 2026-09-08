# Notes: County income data (`county/`)

Documentation of the data and its changes over time, compiled 2026-07 from
the SOI documentation guides and verified directly against the local files
(TY2023 added 2026-09). Money amounts are **$ thousands**; return counts
rounded to the nearest 10 **from 2013** (unrounded in 2011).

**Documentation caveat**: the `{yy}incmdocguide.doc` files SOI links from the
county pages are titled "**State Data** Documentation Guide" — they document
the state (HT2-companion) tabulations and the variable set shared with the
county files, but contain no county-specific suppression thresholds. Any
county-cell disclosure rule beyond what is quoted below is undocumented in
this mirror. (The same guides are saved under `state/HT2/` as well.)

## What the files are

- **`county_{year}_agi.csv.gz`**: one row per **county × AGI stub** (2022
  and 2023: 25,552 rows = 3,194 geographies × 8 stubs).
- **`county_{year}_noagi.csv.gz`**: one row per county (`AGI_STUB` = 0),
  same column set as the agi file.
- Geography: `STATEFIPS`, `STATE`, `COUNTYFIPS` (3-digit), `COUNTYNAME`.
- **State-total rows exist** (`COUNTYFIPS == "000"`, all years, 51 incl. DC).
- **No US row** and no PR/OA rows — national totals must come from HT2.

## AGI stub schemes (a break at 2013)

- **2011 (7 stubs)**: 1 = Under $1 (negative AGI included as its own stub),
  2 = $1–<$25k, 3–7 = $25k/$50k/$75k/$100k/$200k+ (verified from per-stub
  mean AGI).
- **2013–2023 (8 stubs, unchanged)**: 1 = Under $1, 2 = $1–<$10k,
  3 = $10k–<$25k, 4–8 = $25k/$50k/$75k/$100k/$200k+. The county CSVs
  **collapse the state guide's three top classes ($200k–500k, $500k–1M,
  $1M+) into a single $200k+ stub** (verified: max stub = 8, stub-8 mean AGI
  ≈ $440–480k).

## Variable chronology

(Header diffs verified against the files; each `A#####` has a matching
`N#####` count.)

- **2011 → 2013** (74→115 cols): + `MARS1`/`MARS4` (2011 had only `MARS2`),
  `A00101` AGI of itemizers, `A00700` state refunds, `A02650` total income,
  `A02900` adjustments, `A03150`–`A03270` above-the-line detail (IRA,
  student loan, educator, tuition & fees, DPAD, SE health), `A05800` tax
  before credits, `A07230`/`A07240`/`A07300` education/saver's/foreign
  credits, `A09400` SE tax, `A10600` total payments, `A10960` refundable
  education credit, `A26270` partnership/S-corp, `A85300` NIIT, `A85330`
  additional Medicare tax.
- **2014:** + ACA items (`A85770`/`A85775` PTC/APTC, `A05780`, `A09750`
  mandate, `A11560` net PTC), `TOTAL_VITA`/`VITA`/`TCE`; `A85330` recoded
  `A85530` (same concept).
- **2015:** + `RAL`, `RAC`, `ELDERLY`, `VITA_EIC`.
- **2016:** + 8 Schedule A detail pairs (medical, personal property tax,
  mortgage detail, points, mortgage insurance, investment interest, misc).
- **2017:** + `ELF`, `CPREP`, `DIR_DEP`, `A11900`, `A12000`, `A20950`
  (absorbs `A21020`); − `RAL`.
- **2018 (TCJA):** + `A01750` combined IRA+pension (2018 only), standard
  deduction detail, **`A04475` QBI**, `A07225` child & other dependent
  credit (replaces `A07220`), `A18460` capped SALT; − tuition & fees, DPAD,
  mortgage insurance, net limited misc.
- **2019:** `A01400`/`A01700` separated back; − `A01750`, `A09750`,
  **`NUMDEP`**.
- **2020 (COVID):** + `VRTCRIND`, `A02910` charitable-if-standard,
  **`A10970` recovery rebate, `A10971` EIP1, `A10973` EIP2**, `A11450`
  leave credit, `A19550` back.
- **2021:** + `A11520` refundable CDCTC, `A11530` post-3/31 leave credit;
  − `A10973`; **`A10971` re-purposed to EIP3**.
- **2022:** + `A00400` tax-exempt interest, `A25870` rent/royalty,
  **`A59661–64` EITC by qualifying-child count**; − all COVID fields.
- **2023 (Inflation Reduction Act splits Form 5695):** − `A07260`
  residential energy tax credit; + **`A07262` residential clean energy
  credit** (Sch. 3:5a) and **`A07265` energy efficient home improvement
  credit** (Sch. 3:5b). 166 → 168 columns. `A11070` is relabelled
  "additional child tax credit" (was "refundable child tax credit or
  additional child tax credit") — same code, same content. The 2023 docguide
  states all three changes in its "Nature of Changes" section. Identical to
  the HT2 change the same year (see [ht2.md](ht2.md)).

## Disclosure / suppression / rounding

From the state-data guides (see caveat above):

- **AGI-class collapsing**: items with fewer than a threshold of returns in
  an AGI class are combined with a neighboring class within the same state.
  Threshold **<3 returns (TY2013)**, raised to **<10 (TY2014+)** — the only
  threshold change in the series. Collapsed classes carry `**` flags in the
  Excel products only; **the CSVs have no flags**.
- **Counts rounded to the nearest 10 from TY2013** (2011 counts unrounded —
  verified).
- **2011 rules are undocumented locally** (no guide before 2013; the ZIP
  2011 rules demonstrably differ — county 2011 includes a negative-AGI stub
  that ZIP excludes).

## Relationship to HT2

Every guide, verbatim: HT2 "reflect[s] the most complete and accurate totals
by State. Due to various disclosure protection procedures, State totals
included in SOI's ZIP Code and county data may not be comparable to those
from Table 2." Verified in-mirror: AL 2022 county `N1` sum = 2,149,580 vs
the state row's 2,149,320.

## The N2 relabel

`N2` = number of exemptions through TY2017; "number of individuals" from
TY2018 (same column name, rebuilt from filing status + dependents; series
break). `NUMDEP` survives through 2018, dropped 2019.

## Population / coverage

Returns filed/processed in the calendar year following the tax year, plus
limited prior-year returns (described as a late-filer proxy from 2017 on).
Filing-address based, filers only. **COVID exceptions**: TY2019 paper
returns included through mid-July 2021, TY2020 through early June 2022;
EIP-only returns excluded both years — extended, nonstandard windows.

## Gotchas for analysis

1. Use the `COUNTYFIPS == 000` rows for state totals (or better, HT2) — 
   county sums differ by rounding/disclosure.
2. No US row; no PR/OA.
3. **2011 is a different animal**: 74 columns, 7 stubs with different
   boundaries, unrounded counts, no MARS1/MARS4, no documentation.
4. Column presence churns yearly — intersect columns before panel work;
   watch the silent recodes (`A85330`→`A85530`, `A10971` EIP1→EIP3, `N2`
   2018 break, `A07220`→`A07225`, the 2018-only `A01750`).
5. Per-stub county cells for rare items are unreliable (silent collapsing +
   rounding); the noagi file is safer for small counties.
6. TY2019/2020 filing windows are extended — level breaks vs adjacent years.
