# Notes: ZIP code data (`zip/`)

Documentation of the data and its changes over time, compiled 2026-07 from
the SOI ZIP Code Data documentation guides (2011–2022, downloaded alongside
the data) and verified directly against the local files. Coverage note
re-checked 2026-09. Money amounts are **$ thousands**; return counts rounded
to the nearest 10 **from 2012** (unrounded in 2011).

## What the files are

**Coverage as of 2026-09: this series stops at TY2022 and now trails the
other three geographic sets by a year.** HT2, the state percentile shares
and the county files all reached TY2023 in August 2026; `23zpallagi.csv` /
`23zpallnoagi.csv` return 404 and the SOI ZIP Code Data page still lists
TY2022 as its newest year. Nothing is missing from the mirror — re-run
`--only geo 2023 2023` when SOI publishes, and it will pick up just the ZIP
pair. Expect the same Form 5695 split HT2 and county took in TY2023
(`07260` → `07262` + `07265`, see [ht2.md](ht2.md)) whenever it lands.

- **`zip_{year}_agi.csv.gz`** (`{yy}zpallagi.csv`): one row per STATE × ZIP ×
  AGI stub (stubs 1–6, all years).
- **`zip_{year}_noagi.csv.gz`** (`{yy}zpallnoagi.csv`): one row per STATE ×
  ZIP with `AGI_STUB = 0`.
- Identifiers: `STATEFIPS`, `STATE`, `ZIPCODE`. **Header case is
  inconsistent** across years and between the two files — uppercase before
  stacking.
- **State-total rows (`ZIPCODE == 00000`) exist in every year except 2016**
  (verified: zero `00000` rows in both 2016 files — sum ZIPs + `99999` for
  that year).
- **`ZIPCODE == 99999` catch-all rows** hold ZIPs with <100 returns and
  single-building/nonresidential ZIPs, per state (all years).

## AGI stub scheme (unchanged 2011–2022, the full published series)

1 = $1–<$25k; 2 = $25k–<$50k; 3 = $50k–<$75k; 4 = $75k–<$100k;
5 = $100k–<$200k; 6 = $200k+. (0 = no stub, noagi file.) Negative-AGI
returns are excluded entirely, so there is no loss stub.

## Variable chronology

(Header diffs verified against the files; annotations from the docguide
variable tables and "Nature of Changes" sections.)

- **2011 base** (73 cols): `N1`, `MARS2`, `PREP`, `N2` (exemptions),
  `NUMDEP`, AGI, major income items, Schedule A basics, CTC, EITC, AMT,
  income tax, total liability, tax due, refunds.
- **2012:** + `MARS1`, `MARS4`; `A00101` AGI-of-itemizers.
- **2013:** + ~19 item pairs: total income, state refunds, adjustments
  (IRA/student loan/educator/tuition/DPAD/SE health), tax before credits,
  education/retirement-savings/foreign tax credits, SE tax, total payments,
  refundable education credit, `26270` partnership/S-corp, `85300` NIIT,
  `85330` Additional Medicare tax.
- **2014:** + ACA items (`85770`/`85775` PTC/APTC, `11560` net PTC, `05780`
  excess APTC repayment, `09750` mandate payment); `TOTAL_VITA`/`VITA`/`TCE`;
  `85330` renumbered `85530` (same concept).
- **2015:** + `ELDERLY`, `RAC`, `RAL`, `VITA_EIC`.
- **2016:** + 8 Schedule A detail pairs (medical, personal property tax,
  mortgage detail, points, mortgage insurance, investment interest, misc
  deductions).
- **2017:** + `ELF`, `CPREP`, `DIR_DEP`, `11900` overpayments, `12000`
  credited-forward, `20950` (replaces `21020`, adds gambling losses);
  − `RAL` ("insufficient data").
- **2018 (TCJA):** + `01750` combined IRA+pension (2018 only), standard
  deduction detail (`04100`/`04200`/`04450`), **`04475` QBI**, `07225` child
  & other dependent credit (replaces `07220`), `18460` capped SALT;
  − tuition & fees, DPAD, mortgage insurance, net limited misc.
- **2019:** `01400`/`01700` restored (− `01750`); − `09750`, **`NUMDEP`**.
- **2020 (COVID):** + `VRTCRIND`, `02910` charitable-if-standard, **`10970`
  recovery rebate, `10971` EIP1, `10973` EIP2**, `11450` leave credit,
  `19550` back.
- **2021:** + `11520` refundable CDCTC, `11530` post-3/31 leave credit;
  − `10973`; **`10971` re-purposed to EIP3** (docguide 2021: "replaces the
  Tax Year 2020 field").
- **2022:** + `00400` tax-exempt interest, `25870` rent/royalty, **`59661–64`
  EITC by qualifying-child count**; − all COVID fields. (The 2022 docguide
  lists `MVITA` but the CSV lacks it — docguide error.)

## Disclosure rules and their changes

Stable throughout: ZIPs with **<100 returns** (or single-building/
nonresidential) fold into `99999`; **AGI classes with <20 returns collapse**
into a neighboring class within the ZIP; **negative-AGI returns excluded**;
a **dominance rule** suppresses cells/items dominated by one return
(threshold not released).

Changes:

- **2012** ("to enhance the disclosure protection procedures"): counts
  rounded to nearest 10; items with <20 returns within a ZIP excluded; and —
  critically — **the `0.0001` collapsed-cell sentinel was dropped from the
  CSVs**. The 2011 CSV contains ~3.5M cells equal to `0.0001` (~29% of
  cells) marking collapsed AGI classes — treat as missing, never as values.
  **From 2012, collapsed/suppressed cells are indistinguishable from true
  zeros** in the CSVs (the `**` flag exists only in the Excel releases).
- **2017**: dominance-rule language narrows from suppressing the whole
  *return* to suppressing the specific *data item* in the cell. [UNCERTAIN
  whether methodology change or clarification — the guides don't say.]

## Population / coverage

Returns filed during the calendar year following the tax year (plus limited
prior-year returns as a late-filer proxy). Exclusions in all years:
negative AGI, no-ZIP or ZIP/state-mismatch, APO/FPO/foreign/territory
addresses. State codes derive from the return's ZIP; the address need not
be the taxpayer's residence.

**COVID exceptions**: TY2019 paper returns included through mid-July 2021;
TY2020 through early June 2022; EIP-only returns excluded in both — the
2019/2020 coverage windows are longer than other years, so filer-count
movements around 2019–2021 partly reflect processing, not behavior.

## The N2 relabel

`N2` = number of exemptions through TY2017; from TY2018, "number of
individuals," reconstructed from filing status and dependent information
(docguide 2018: same variable name kept deliberately). Series break at
2017→2018. `NUMDEP` disappears in 2019.

## Gotchas for analysis

- **Suppression is invisible from 2012 on** — zeros may be suppressed cells.
  In 2011, `0.0001` = collapsed cell (must be treated as missing).
- Small ZIPs are not missing at random: they live in the state's `99999` row.
- **2016 has no state-total (`00000`) rows** in either file.
- **State sums ≠ HT2** (exclusions + dominance suppression); every docguide
  says so — use HT2 for state totals.
- Code-reuse traps: `A10971` = EIP1 (2020) but EIP3 (2021); `85330`→`85530`
  same concept; `21020`→`20950`; `01400`/`01700` absent in 2018 only;
  `07220`→`07225` at 2018.
- noagi ≠ collapse of agi: the noagi file includes returns whose AGI class
  was too small to publish, so agi-file stub sums can fall short.
- Docguide typos: 2016 guide's "processed during 2016" (should be 2017);
  2019 guide's overview says "Tax Year 2018" (copy-paste error).
