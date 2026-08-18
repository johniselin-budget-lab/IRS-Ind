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

Result over the TY2011–2023 overlap (26 comparisons of total returns filed and
Form 1040 AGI): **23 exact matches, 3 documented differences, 0 unexplained**.

The three differences are all **exactly ±1 in the last digit** — TY2014 total
returns (148,606,579 vs 148,606,578), TY2015 AGI and TY2017 AGI. Both sides'
raw cells were read directly to confirm they are published that way. The two
publications round the same underlying weighted estimate independently, so the
final digit can disagree by one. They are pinned in
`checks/known_differences.csv` with the exact expected difference, so the
check stays strict: the same item differing by any other amount still fails.

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

## Extraction gotchas (what `parse_line_items.py` had to handle)

The estimates sit in the form's drawn entry boxes, so the boxes are the anchor
— but three assumptions that hold for TY2023 fail elsewhere:

- **Values are not always inside their box.** TY2018 prints each value ~5pt
  *above* the rectangle. Strict containment silently drops the row; match the
  nearest box within a small tolerance instead.
- **Take the line label from the value's row, not the box's.** Forms print the
  line number twice — left of the description and again beside the entry box
  (TY2018 at x=477 versus the description column at x=104) — and the value
  aligns with the second. Taking the rightmost label-shaped token left of the
  value on its row also handles rows with two entry boxes (2a mid-page, 2b at
  the margin) and ignores body-text numerals: a stray "1" from "Schedule 1,
  line 22" otherwise captured TY2018's AGI row and dropped the value.
- **A description can wrap onto two printed lines** with the box aligned to
  the second (TY2018 line 7), so row text assembled from the box's own band is
  only the tail of the description. This is why the AGI row is located by
  **line number** from an explicit per-year map rather than by matching its
  printed wording — the TY2018 redesign also drops the phrase "this is your
  adjusted gross income" that every other vintage uses.

Form 1040's AGI line: **37** (TY2003–2017), **7** (TY2018), **8b** (TY2019),
**11** (TY2020–2023). TY2019 is the only year it sits on 8b.

Smaller traps: TY2013 typesets "filed" with an **fi ligature** that extracts as
`fi led` — with a space; TY2014–15 put the summary count and its label on one
**tab-separated** line where other years use a newline.

## Coverage of the extractor today

`parse_line_items.py` currently emits only the two check items. It gets both
for **TY2011–2023**, the whole window where Pub 1304 targets exist. Pre-2011
AGI extraction fails (TY2003–2008 find no 1040 page carrying line 37;
TY2005/2009/2010 find the returns page but not the matching amounts page) —
those vintages use an older layout and are Tier B/C work in
[expansion_plan.md](expansion_plan.md). Total returns filed extracts cleanly
for all 21 years.

## Known consumers

None yet. The intended use is as a **regression test for every parser this
repo grows** (see [expansion_plan.md](expansion_plan.md)), and as the
line-level detail behind Pub 1304's aggregates.
