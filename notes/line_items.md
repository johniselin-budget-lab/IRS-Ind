# Notes: Line item estimates, Pub 4801 / 5385 (`national/line_items/`)

Documentation compiled 2026-08-17, verified against the mirrored files.
Source: [SOI Tax Stats — Individual income tax returns line item estimates
(Publications 4801 and 5385)][li].

[li]: https://www.irs.gov/statistics/soi-tax-stats-individual-income-tax-returns-line-item-estimates-publications-4801-and-5385

## What they are

For **every line of every form and schedule**, the estimated number of returns
carrying an entry and the amount reported. Far more line detail than Pub 1304
— but with **no AGI dimension**, so the two are complements: Pub 1304 gives
the distribution, Pub 4801 gives the line coverage.

- **Pub 4801** — individual income tax returns, TY2003–2023 (21 files).
- **Pub 5385** — individual *information* returns (W-2, 1099s, etc.),
  TY2017–2023 (7 tax years in 6 files).

Both are PDFs printed on facsimiles of the forms, with each estimate placed in
that line's entry box. Amounts are **thousands of dollars**. Within a
publication, even pages carry number of returns and odd pages the matching
amounts.

## They share Pub 1304's sample — which makes them a test

Both publications are built from the same weighted SOI sample, so matching
items agree **exactly**, not approximately. `run_checks.R` exploits this: it
compares extracted line items against the Pub 1304 tables in the store and
treats any difference as a defect to explain rather than a tolerance to widen.

Result over **156 comparisons, TY2011–2023**: **152 exact matches, 4
documented differences, 0 unexplained**. Every year is checked at 12
comparisons — AGI, taxable and tax-exempt interest, ordinary and qualified
dividends and taxable income, each as both a return count and an amount, plus
the cover-page total. The Form 1040 line numbers differ by era (interest
8a/8b, dividends 9a/9b, AGI 37, taxable income 43 through TY2017; 2b/2a,
3b/3a, 7→8b→11, 10→11b→15 after) and were derived from the panel's own line
descriptions rather than from memory. The checks read `aligned/line_items.csv`
itself, so a parser regression fails the gate rather than passing a
separately-derived side file.

All four differences are **exactly ±1 in the last digit** — TY2014 total
returns (148,606,579 vs 148,606,578), TY2015 AGI and taxable income, TY2017
AGI. In each case both raw cells were read to confirm they are published that
way: the two publications round the same weighted estimate independently, so
the final digit can disagree by one. They are pinned in
`checks/known_differences.csv` with their exact expected differences, so the
check stays strict — the same item differing by any other amount still fails.

## Source-naming: three eras plus a moving target

| Tax years | Pub 4801 | Directory |
|---|---|---|
| 2003 | `03linecnt.pdf` | `/pub/irs-soi` |
| 2004–2007 | `{YYYY}linecnt.pdf` | `/pub/irs-soi` |
| 2008–2016 | `{yy}inlinecount.pdf` | `/pub/irs-soi` |
| 2017–2022 | `p4801--{rev}.pdf` | `/pub/irs-prior` |
| 2023 | `p4801.pdf` | `/pub/irs-pdf` |

`{rev}` is a publication date that cannot be derived from the tax year
(2017→`2019`, 2018→`2020`, 2019→`2021`, 2020→`2022`, 2021→`2024`,
2022→`122024`), so the downloader hardcodes the map and the source page is its
only authority. Pub 5385 is the same shape: 2017→`p5385--2019`,
2020→`p5385--2023`, 2021→`p5385--2024`, 2022→`p5385--042025`, 2023→ the
current `/pub/irs-pdf/p5385.pdf`.

**`/pub/irs-pdf/p4801.pdf` always holds the newest tax year.** When TY2024
publishes, that URL's content changes and the TY2023 revision moves to
`/pub/irs-prior/`. `manifest.csv`'s md5 is what catches the swap. Every
mirrored file's declared cover year was checked against the year the map
assigned it: **28 publications, 0 disagreements**.

## Two files that are not what they look like

- **`p5385_2018-2019.pdf` is a PDF Portfolio holding two tax years.** The
  outer document is one page of "open this in Acrobat" boilerplate; the real
  content is two embedded 94-page PDFs declaring TY2018 and TY2019. That is
  why the source page links two tax years to one URL. It is fetched once and
  stored under a range name; a reader must unwrap it (`embfile_get`) and route
  each part by its cover year.
- **`p4801_2022.pdf` is NOT a portfolio, despite having an attachment.** It is
  an ordinary 238-page publication carrying a 2-page *accessibility report*, a
  by-product of IRS PDF remediation. Deciding "portfolio" from
  `embfile_count() > 0` therefore skips TY2022's entire content and tries to
  parse the accessibility report instead. Decide on the **outer page count**:
  a true portfolio is a stub of ≤3 pages.

## Extraction: anchor on the line label, not the entry box

An earlier spike concluded that the estimates sit in the form's **drawn entry
boxes**, so the boxes were the anchor. That is true of the Form 1040 and
badly wrong in general: **the 1040 paints filled rectangles behind its entry
cells, but most schedules rule theirs with bare line segments**, so box
detection finds nothing on them and returns no values at all — silently, since
a page with no boxes simply yields an empty list. Anchoring on boxes covered
41 of TY2023's 222 data pages; anchoring on the line label covers 179.

The rule now: **a value is a numeric token immediately to the right of a line
label that stands in one of the form's label columns.** Label columns are
found per page as the x positions several label-shaped tokens share, which
keeps distant body-text numerals out — "Attach Form 4797" sits ~180pt from the
nearest label and is ignored, whereas a stray "1" from "Schedule 1, line 22"
had previously captured TY2018's AGI row and dropped its value.

Label adjacency alone is not enough, because forms are full of
**cross-references that sit right beside a label**: "19 If line 18 is more
than line 15" put the 18 one label-width from the 19, and it was published as
line 19's estimate — 18 returns where the truth is millions. A candidate is
therefore kept only if it is **either inside one of the drawn boxes or ends
its row**: an estimate is printed in the entry column with nothing after it,
while a cross-reference has the rest of its sentence to the right. That test
removed about 1,960 spurious values (those under 100 fell from 598 to 163),
and the surviving small values are real — Form 3468's rare energy credits
genuinely have counts of 0 and 27.

Three further traps, all from TY2018:

- **Forms print each line number twice** — left of the description and again
  beside the entry column (x=477 versus x=104) — and the value aligns with
  the second, so the label must be taken from the value's own row.
- **A description can wrap onto two printed lines**, leaving the row text
  only the tail of the description. Never key anything on `line_text`.
- The AGI row is therefore located by **line number** from an explicit
  per-year map, not by matching its printed wording, which the TY2018
  redesign changes as well as wraps.

Form 1040's AGI line: **37** (TY2003–2017), **7** (TY2018), **8b** (TY2019),
**11** (TY2020–2023). TY2019 is the only year it sits on 8b.

Smaller traps: TY2013 typesets "filed" with an **fi ligature** that extracts as
`fi led` — with a space; TY2014–15 put the summary count and its label on one
**tab-separated** line where other years use a newline.

## What the scraper produces

`parse_line_items.py <dest>` writes `aligned/line_items.csv`: one row per
(tax year, form, universe, line, measure) with the value, the page it came
from and a best-effort description. **24,838 values for TY2011–2023**, about
1,900 a year across ~57 forms.

Page classification comes from three independent signals: the measure from the
page header ("Number of returns filed…" vs "Amounts of selected lines
filed…"), the form from the bottom-of-form legend, and the universe from the
table of contents, which is the only thing distinguishing the Form 1040's
repeated printings — the pages themselves are identical in every other
respect. **Every vintage prints the 1040 more than once.** TY2018 onward
prints it for *all returns* and again for *electronically filed returns*;
TY2017 and earlier print it **three** times — all returns (every filer,
consolidated onto the 1040 layout), **Form 1040 filers only**, and
electronically filed — ahead of separate sections for Forms 1040A and 1040EZ.
The `universe` column carries all three values. Recognising only the
electronic heading had labelled the "1040 only" pages as all returns, so
every pre-2018 line appeared twice and those years could not be emitted.

Two TY2011-only quirks in the same machinery: its contents page writes page
references as "`pg 14`" rather than a bare number, and its *amounts* pages
print no page number in their header at all, so a page without one is taken
to follow the previous data page. Without the second fix every TY2011 amounts
page fell to the default universe while its returns page did not.

Legend formats vary more than they look: `Form 1040 (2023)`,
`Schedule C (Form 1040) 2023`, `Schedule 1 (Form 1040 or 1040-SR) 2019`,
`Form 965-A (Rev. 1-2021)` and `Form 965-A (1-2019)` — the same form in two
vintages, one with the "Rev." prefix and one without. A form's continuation
pages carry no legend and inherit it from the page before, which is dangerous:
when the TY2019 pattern stopped matching, 38 pages silently inherited "Form
1040" and the 1040's own AGI line then had six candidate rows instead of one.
The parser now reports any run of more than four inherited pages, and any
ambiguous check selection, rather than picking one quietly.

### The structural check: the forms' own arithmetic

`run_checks.R` compares a dozen curated lines a year against Pub 1304. That
proves the lines it names and nothing else, and it missed a bug that a glance
at the output caught (see above). The forms, however, state their own
arithmetic — "Add lines 1z, 2b, 3b, 4b, 5b, 6b, 7, and 8", "Subtract line 10
from line 9" — so every subtotal can be checked against its own components.
`parse_line_items.py` records those statements in `aligned/line_relations.csv`
(9,228 of them) and `check_arithmetic.R` evaluates them.

**Amounts only.** Return *counts* are not additive: one return carries several
component lines, so a total's count is not the sum of its parts.

**Most stated arithmetic does not survive aggregation**, which is the main
thing this check taught. The 9,228 statements (TY2011–2023) dedupe to 4,625
distinct ones, of which **1,293 are outright nonlinear per return** — "if zero
or less, enter -0-" floors a result, "enter the smaller of" caps it, and a sum
of floored values is not the floor of the sum — and those are flagged and set
aside. That leaves **3,332 linear statements**, of which **1,218 are fully
evaluable** (the rest reference a line the parser did not extract, mostly on
the grid-layout forms below). Of those 1,218, **67.5% reconcile exactly** —
the same rate as the TY2018–2023 slice alone, which is itself evidence that
the older vintages extracted at the same quality.

Judging linearity is easy to get subtly wrong: an earlier version tested the
row *plus the next printed row*, so a statement was set aside whenever the
row **after** it happened to say "if zero or less". That halved the check's
coverage — 439 evaluable instead of 584 — for a qualifier that was not its
own. The caveat is now judged on the same text the statement was matched in,
and the reconcile rate is unchanged at ~67%, which is the evidence that those
900-odd relations were being excluded for no reason. The rest mostly fail for the same reason one step
further out: lines that are conditional per return (an amount owed on one line
*or* an overpayment on another) total over different sets of returns. So this
is a **screen, not a gate** — `run_checks.R` remains the gate.

Its value is the separation it makes. When a stated sum lands *exactly on
another line of the same form*, that is an extraction defect, not form
semantics, and the report names it. That surfaced nine, of which six shared
one cause: the target label was a line number quoted **inside the phrase**, so
the relation was filed under one of its own components ("Subtract line 5 from
line 4" recorded against line 5, which belongs to line 6). A line is never
defined in terms of itself, so the parser now rejects any such relation
outright rather than guessing a target.

The last three were subtler and are also fixed: a **trailing cross-reference
can land its line number in one of the page's label columns** and then beat
the row's own label. TY2021 Form 8959 line 18 ends "…also include this amount
on Schedule 2 (Form 1040), line 11", so the relation was filed under 11. A
label introduced by "line", "Schedule" or "Form" points elsewhere and is no
longer a candidate. The check now reports **no relation resolved to the wrong
line**.

**Ranges are expanded or dropped, never narrowed.** "Combine lines 1 through
8" originally matched only the list pattern, which kept the two endpoints and
recorded a two-term sum — 146 rows of the panel carried a truncated component
list that then failed its own check. A range the parser cannot expand (mixed
stems like "10 through 32f", or a compound "Add lines 27a and 28 through 31")
is now left out entirely rather than recorded short.

The same check also drove two earlier fixes: relation statements were being
attributed to the row *above* (the wrap-lookahead was supplying a neighbour's
complete sentence rather than finishing a wrapped one), and sub-lettered rows
print only the letter on the description side, so the target must be read from
the label beside the entry column.

```bash
Rscript check_arithmetic.R --dest /path/to/store   # writes checks/_arithmetic.csv
```

### Coverage and limits

- **TY2011–2023.** Pub 1304 targets exist from 2011, so that is where
  validation — and therefore the default range — begins. TY2003–2010 can be
  requested explicitly; they classify (the older 1040 layout's AGI is line 37
  as well) but nothing checks them, and the cover-page total is the only
  figure read for them by default.
- **About one estimate in seven is not reached.** Across TY2018–2023, 368 of
  ~1,330 data pages yield nothing. Counting the comma-bearing numerals on
  them (SOI's thousands separators mark real estimates; a bare "2023" or
  "8880" is a year or a form number, which an earlier count wrongly included),
  **1,796 estimates sit on those pages against 10,890 in the panel — 14.2%
  unreached.** 73 of the 368 pages hold no estimates at all and are
  legitimately empty (instructions, or the 1040's page 1, whose figures are
  checkbox counts rather than line values); 149 hold one to three.

  The missing mass is concentrated in a handful of **grid-layout credit
  forms**: Form 3800 (354 estimates), 8880 (183), 4136 (164), 8938 (139),
  4562 (132), Schedule EIC (114), 8863 (96), 8936 (89). Their values sit in
  cells addressed by row *and column* — Form 3800's credit-by-source matrix,
  Schedule EIC's per-child columns — with a word or another number to their
  left rather than a line label, so label adjacency cannot reach them.
  Reaching them needs cell reconstruction from the ruling segments **and a
  schema change**: `line_items.csv` has no column dimension. That is a design
  decision, not a parser patch, and the 14.2% figure is what it would buy.
- `line_text` is best effort and can be a fragment; it is for eyeballing, not
  for keying.

## Known consumers

None yet. The intended use is as a **regression test for every parser this
repo grows** (see [expansion_plan.md](expansion_plan.md)), and as the
line-level detail behind Pub 1304's aggregates.
