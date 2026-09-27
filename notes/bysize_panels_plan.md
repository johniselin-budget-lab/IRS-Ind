# Plan: table-specific harmonized panels for the Pub 1304 by-size tables

Status 2026-09-26: **plan, not built.** Companion to
[national_bysize.md](national_bysize.md) ("Aligned panels": the layer this
builds on) and [alignment_plan.md](alignment_plan.md) (Tier 1, now done).

## Layers

1. **Aligned** (`aligned/bysize_{family}.csv`, built): one row per published
   cell, labels as published, plus `item` — the column key with differences
   of *form* cleaned away automatically (case, hyphens, year stamps, and the
   justified rewrites in `checks/bysize_label_synonyms.csv`). After cleanup,
   258 items (counting a Number/Amount pair once) are not published in every
   year of their table. Those are the concept changes this plan resolves.
2. **Harmonized** (`aligned/panel_{family}.csv`, this plan): one panel per
   table, keyed on that table's own dimensions, with every concept change
   resolved by the three rules below. Built by a new `harmonize_bysize.R`
   from layer 1 and a committed concept map, `checks/bysize_concepts.csv`.

## The three kinds of concept change

| Kind | Meaning | Treatment |
|---|---|---|
| **condense** | 2+ published categories collapse into one in some years | The one category becomes a **consistent total** in every year (published where published; the sum of the components where not). The components are kept, with an explicit note, and are **NA in the years of the collapse**. |
| **expand** | 1 published category splits into 2+ in some years | Same treatment, mirrored: the one category is the consistent total (published where published; the sum of the new components where not); the components are kept, noted, and NA in the years before the split. |
| **other** | Anything else: a law change that redefines an item, an item entering or leaving, a restructure that is neither a clean split nor a merge | Value kept as published and **flagged** (`change = 'other'`, with a note). No total is built. |

**Summing rules for a consistent total.** Amounts ($ thousands) sum. A
**number of returns** sums only when the components are mutually exclusive
(filing statuses, AGI classes). When one return can sit in two components
(IRA and pension distributions, partnership and S corporation income, two
energy credits), the total's return count is **NA with a note** in the
derived years, never an overcount. Averages and percents are not summed:
NA in derived years. A component that is combined (`**`) or suppressed
(`d`) makes the derived total NA with the component's flag.

**Other-flag default.** Every item published in only some years of its
table, and not claimed by a condense/expand entry in the concept map, is
flagged `other` automatically, with the note "published TY…"; the map adds a
reason where one is known. So nothing drifts unflagged.

**AGI size classes are resolved automatically** as `expand`: the classes
whose bounds appear in every year of a table (and panel) are its consistent
classes; a finer split published in some years (TY2011–2012's $250k break)
is kept as components, NA in the other years, and the consistent class is
derived by summing in the split years. Class counts are exclusive, so
returns sum.

## Output schema (all tables)

`tax_year, table, family, panel, <table's row dimension>, row_agi_lo,
row_agi_hi, series, measure, value, flag, derived, change, change_note`

- `series`: the harmonized item (layer 1's `item`, or the concept map's
  total name); `measure`: `returns`, `amount`, or the published measure for
  single-measure columns (exemptions, averages, percents).
- `derived`: TRUE where the value is a sum built here, not a published cell.
- `change`: NA, `condense_total`, `condense_component`, `expand_total`,
  `expand_component`, `other`; `change_note` says what and why.
- Panel, section and row labels get the same form cleanup as columns (case,
  ", total" suffix: TY2011's "Size of Adjusted Gross Income", 2.7/1.7's
  "All returns, total" vs "All returns").

Checks carried into the new layer: every published cell appears exactly once;
a derived total's published years match the published total; additivity of
the consistent classes to the panel total; and a seam report per
condense/expand entry (last year before vs first year after, total and
components) so a bad mapping shows as a jump.

## Decisions

1. **Partnership + S corporation in Table 1.4 (split TY2021) — decided
   2026-09-26: net.** The published columns are *net income* and *net loss*,
   netted per return across partnership and S corporation income together,
   so the separately netted components cannot recover them. The consistent
   total is **net income less net loss**, which is additive and exact
   (TY2020 combined 707.4B; TY2021 components 975.7B). Confirmed
   independently: Pub 4801 Schedule E line 32, "total partnership and S
   corporation income or (loss)", prints 975,656,400 for TY2021 (and
   707,431,778 for TY2020). The combined gain and loss columns are NA from
   TY2021 with a note.
2. **IRA + pensions (combined in TY2018 only; 1.4, 2.1) — decided
   2026-09-26: flag as other.** No consistent total is built; the TY2018
   combined items and the separate IRA and pension items are all flagged
   `other`, with a note naming the other side of the seam.
3. **Return counts in totals whose components overlap — open.** A sum of
   component counts overcounts returns that sit in both. What an estimate
   could rest on differs by case:
   - *National anchor exists* (partnership + S corporation): Schedule E
     line 32's return count is exactly Table 1.4's combined count in
     TY2019–2020 (8,939,959; 9,001,513) and continues after the split
     (9,331,698 in TY2021, against 10,524,718 for the summed components:
     a 12.8% overcount). By AGI class there is no anchor, so class values
     would be an allocation of that national figure.
   - *Overlap observable in one year* (IRA + pensions): TY2018 publishes the
     combined count by AGI class; the ratio to the mean of TY2017 and
     TY2019 component sums runs 0.76–0.90 by class (0.795 overall).
   - *Nothing to anchor on* (energy credits, sick leave windows, 1.4A basis
     categories): bounds only, [largest component, sum of components].

## Per table

AGI classes are "consistent" (in every year) plus, in brackets, finer splits
published in some years only. "Returns" in a total means number of returns.

### 1.1 Selected income and tax items — `income_tax_items`, TY2011–2023
- **Panel**: year × section (size / accumulated from smallest / accumulated
  from largest) × AGI class × column. 20 columns, 9 additive; Taxable returns
  is a column group, not a panel.
- **Classes**: 19, to $10M+. Nothing partial.
- **Condense / expand**: none. **Other**: none. Only label cleanup (TY2011
  section case).

### 1.2 Filing status — `marital_status`, TY2011–2023
- **Panel**: year × panel (all / taxable / nontaxable) × AGI class × filing
  status × item × measure. 19 classes (15 in the sub-panels, top $1M+).
- **Condense**: married filing jointly + surviving spouses → one group from
  TY2015. Total "joint and surviving spouse" in every year (TY2011–2014 as
  the sum; statuses are exclusive, so returns sum); the two components are
  NA from TY2015. Applies to all 8 items of the group.
- **Other**: exemption amount, every status, TY2011–2017 (exemptions
  suspended from TY2018).

### 1.4 Sources of income — `income_sources`, TY2011–2023
- **Panel**: year × panel × AGI class × item × measure. 19 classes (15 in
  sub-panels) [$250k split TY2011–2012].
- **Other** (decision 2): IRA distributions + pensions and annuities
  combined in TY2018 only.
- **Expand**:
  - Wages, TY2022: "Salaries and wages" (≤2021) is the total, continued by
    "Total wages > Total" ($9.02T 2021 → $9.74T 2022, +7.9% against +7.2%
    the year before). Components from TY2022: Form W-2 wages, household
    employee wages not on a W-2, tips not on a W-2, taxable dependent care
    benefits, Form 8919 wages, other earned income — NA before. Returns in
    the total are published every year.
  - Partnership and S corporation, TY2021 (decision 1).
- **Other**: TY2011 Schedule D detail (19 items; moved to Table 1.4A from
  TY2012); exemptions (≤2017); QBI deduction and "standard or itemized plus
  QBI" (2018+/2019+); section 965, GILTI, limitation on business losses
  (2017–2019); disaster loss (2017+); domestic production activities
  (≤2019, and a 2018 co-op pass-through); Archer MSA, foreign housing,
  capital construction fund (≤2019); tuition and fees (≤2020); unemployment
  exclusion (2020); charitable deduction for non-itemizers (2020–2021);
  excess advance premium tax credit repayment (2014+).

### 1.4A Capital assets — `capital_assets`, TY2012–2023
- **Panel**: year × panel × AGI class × holding period × basis category ×
  item × measure. 19 classes [$250k split TY2012].
- **Expand**: "With basis reported" (TY2012) splits from TY2013 into "…and
  no Form 8949" and "…on Form 8949", for each of short and long term ×
  sales price, cost or basis, adjustment, gain, loss (10 items). Total =
  TY2012 published, sum from TY2013; returns NA in TY2013+ (a return can
  report both ways); components NA in TY2012.
- **Other**: none further.

### 1.6 Age × filing status — `returns_marital_age`, TY2011–2023
- **Panel**: year × filing status (panel) × age band (row) × AGI class
  (column). The only table with classes across the columns; 19 classes.
- **Condense**: married filing jointly + surviving spouses blocks → one
  block from TY2015 (as 1.2; statuses exclusive, returns sum). Age bands
  match: both TY2011–2014 blocks open "Under 26".
- **Other**: none. Combined cells move counts between age rows (worst
  TY2018); Tax-Data's merged target view is a separate deliverable
  ([alignment_plan.md](alignment_plan.md), step 1).

### 1.7 Dependent returns — `dependent_returns`, TY2012–2023
- **Panel**: year × AGI class × item × measure; one panel, 12 classes (top
  $200k+).
- **Condense / expand**: none (TY2022's "Total wages" is a relabel, cleaned).
- **Other**: charitable deduction for non-itemizers (2020–2021).

### 2.1 Itemized deductions — `itemized_deductions`, TY2011–2023
- **Panel**: year × panel × AGI class × item × measure. 22 classes, $5k
  steps to $60k [$250k split TY2011–2012]. Universe: returns with itemized
  deductions.
- **Other** (decision 2): taxable IRA + taxable pensions combined in TY2018
  only.
- **Expand**: wages TY2022 (as 1.4).
- **Other**:
  - TCJA suspensions: limited miscellaneous deductions (5 items), the
    overall limitation ("in excess of limitation"), exemptions — TY2011–2017.
  - Casualty or theft loss (≤2019).
  - The state and local tax (SALT) cap: "limited state and local taxes"
    (2018+) and a pre-cap "total state and local taxes" (2018+) that has no
    published counterpart before (the pre-2018 components carry through).
  - "Total mortgage interest and points" (2018+), a new subtotal.
  - Mortgage insurance premiums, published TY2011–2017 and 2019–2021 (not
    2018, not after the deduction expired).
  - TY2018–2019 business items (section 965, GILTI, loss limitation),
    unemployment exclusion (2020), excess premium credit repayment (2014+).

### 2.3 Exemptions — `exemptions`, TY1996–2017 (closed)
- **Panel**: year × panel × AGI class × exemption type × measure. 18
  consistent classes, bottom "Under $5,000" [$1.5M/$2M/$5M/$10M splits
  TY2000–2017; TY1996–1999 stop at $1M+].
- **Condense / expand**: the top classes (automatic).
- **Other**: Hurricane Katrina displaced-person exemptions (2005–2006),
  Midwestern disasters (2008), returns filed by dependents (2009+).

### 2.5 Earned income credit — `eitc`, TY2011–2023
- **Panel**: year × qualifying-children group × AGI class × item × measure;
  no stacked panels. 27 classes, $1k steps to $20k [$50k split TY2012+:
  TY2011 stops at $45k+].
- **Other**: nontaxable combat pay (≤2014), total income tax (≤2018), for
  every children group.

### 2.7 Affordable Care Act items — `aca_items`, TY2014–2023
- **Panel**: year × AGI class × item × measure; 12 classes to $50k+.
- **Other**: individual responsibility payment (2014–2018; penalty zeroed
  from 2019).

### 3.1 Modified taxable income — `modified_taxable_income`, TY2011–2023
- **Panel**: year × computation type (published as *sections*: regular only
  / Form 8615 / Schedule D; promote to the panel dimension) × AGI class ×
  item. 18 classes.
- **Other**: excess advance premium tax credit repayment (2014+).

### 3.1A Form 8615 — `form8615`, TY2011–2023
- **Panel**: year × AGI class × column (6); 18 classes. Nothing left after
  cleanup.

### 3.2 Tax as a percent of AGI — `tax_pct_of_agi`, TY2011–2023
- **Panel**: year × status block × AGI class × ratio band × measure; 12
  classes (top $200k+).
- **Other**: the joint and single status blocks, TY2011–2014 only. To
  verify at build: "All returns" (TY2011–2015) and "All returns with total
  income tax" (2016+) are the same universe (the table's title says so) —
  if the totals line up with 3.3's returns with total income tax, it is a
  label and gets cleaned.

### 3.3 Tax liability, credits, payments — `tax_liability`, TY2011–2023
- **Panel**: year × panel × AGI class × item × measure. 19 classes [$250k
  split TY2011–2012].
- **Expand**:
  - Income tax withheld: total published every year; components (Form W-2,
    Form 1099, other forms) from TY2020, NA before.
  - Residential energy credits: split TY2023 into residential clean energy
    and energy efficient home improvement (8.24B in 2022; 8.23B + 2.33B in
    2023). Returns NA in TY2023.
  - Qualified sick and family leave credit: one item TY2020, two leave
    windows from TY2021. Returns NA from TY2021.
- **Other**:
  - Child credits: child tax credit (≤2017) → child and other dependent
    credit (2018+, TCJA adds the $500 credit and doubles the CTC: 26.9B →
    81.5B); additional child tax credit (≤2020) → refundable CTC or ACTC
    (2021+, the American Rescue Plan's fully refundable year); refundable
    child and dependent care credit (2021 only).
  - Vehicle credits: qualified electric vehicle (≤2014), qualified plug-in
    electric vehicle (≤2022) → clean vehicle credit (2023, new rules);
    alternative motor vehicle (≤2022).
  - "Other tax credits" (≤2020) vs "other nonrefundable credits > total"
    (2021+): different residuals, not a relabel.
  - The refundable credit breakout "total refundable credits > …" begins
    TY2014; recovery rebate credit (2020–2021); 2011–2013 one-offs
    (first-time homebuyer, refundable adoption, refundable prior-year
    minimum tax, health insurance tax credit, regulated investment company
    credit), with their "used to offset" and "refundable portion" columns.
  - Other taxes: additional Medicare tax and net investment income tax
    (2013+), individual responsibility payment (2014–2018), the TY2021
    restructure of other taxes (additional Social Security and Medicare,
    uncollected taxes on tips, installment-sale interest), section 965
    installments (2017–2018).
  - Payments: Schedule H / SE deferral (2020–2021); total income tax minus
    refundable credits (2018+).

### 3.5 Tax by rate — `tax_generated_byrate`, TY2011–2023
- **Panel**: year × AGI class × rate × measure; 24 classes, $2k steps to
  $20k; no panels.
- **Other**: the bracket schedule. 15/25/28/33% (≤2017) and 39.6% (2013–2017)
  give way to 12/22/24/32/37% (2018+); 10% and 35% run throughout (same
  label, but the brackets' income ranges change in 2018 — flagged, not
  merged); the 20% capital gains rate enters 2013. No total is built across
  rates: the brackets are not a split or merge of one another.

## Build order

1. `harmonize_bysize.R` with the rules above and a concept map holding the
   condense/expand entries listed here (about 15 entries; everything else
   defaults to `other`).
2. Tables in the order a consumer needs them: **1.6, 1.4, 1.7** (Tax-Data's
   TY2018–2023 filer refit), then 1.2, 2.1, 3.3, then the rest.
3. The seam report per condense/expand entry, reviewed before any panel is
   called done.
