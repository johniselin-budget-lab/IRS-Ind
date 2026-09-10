# Notes: Sales of capital assets (`national/capital_assets/`)

Documentation compiled 2026-09-10, verified against the local files and an
HTTP probe of seven filename shapes × TY1985–2024 (7,920 candidate URLs).
Source: [SOI Tax Stats — Sales of capital assets reported on individual tax
returns][soca].

[soca]: https://www.irs.gov/statistics/soi-tax-stats-sales-of-capital-assets-reported-on-individual-tax-returns

## What it is, and why it is closed

The SOI **Sales of Capital Assets study**: Schedule D transactions tabulated by
**asset type**, **month of sale**, **length of time held**, and size of AGI —
detail no other SOI individual series carries. It is a **closed series**: the
last cross-section is TY2015, and every plausible TY2016–2018 stub was probed
and is absent. The live successor is Pub 1304 **Table 1.4A**
(`national/by_size/capital_assets_{year}.xls`, TY2012–2023, see
[national_bysize.md](national_bysize.md)), which keeps the AGI dimension but
has none of the asset-type, month or holding-period cuts. 73 files.

**Units are not uniform across vintages** — TY1985 is in *millions* of
dollars where later years use thousands, and several tables count
*transactions* rather than returns. Read each file's bracketed header line
before comparing years.

## Coverage

| Files | Tables | Tax years | Notes |
|---|---|---|---|
| `soca_t{n}_{year}.xls[x]` | 1–4 | 1985, 1997, 1998, 1999, 2007–2015 | Cross-section. **No TY2000–2006** — those years exist only inside the panel files |
| `soca_t{5,6}_1985.xls` | 5–6 | 1985 | Sales of principal residences; installment sale transactions |
| `soca_t{5..9}_2012.xls` | 5–9 | 2012 | T5 stratum definitions and sample sizes; T6–T9 coefficients of variation for T1–T4 |
| `soca_t{n}_1997rev.xlsx` | 1–4 | 1997 (revised) | See below — captioned Tables 5a–8a |
| `soca_panel_1999-2003_t{n}.xls` | 1–5 | 1999–2003 | SOI Individual **Panel**, wave 1 |
| `soca_panel_2004-2007_t{n}.xls` | 1–5 | 2004–2007 | Panel, wave 2 |

**Table numbers do not mean the same thing across years.** 1985's Table 5 is
principal residences; 2012's Table 5 is stratum definitions; the panel's Table 5
is a cross-section companion to the panel tables. Key any cross-year work on
the *table content*, not the number — the same trap as the IRA family's
pre-2005 numbering ([ira.md](ira.md)).

Tables 1–4 are consistent in content throughout: **1** by asset type, **2** by
AGI group, **3** by month of sale, **4** by length of time held. TY2012's
Table 1 workbook has two sheets (1A, 1B); the panel workbooks have three each.

## Eight filename eras for one table series

| Tax years | Stub | Ext |
|---|---|---|
| 1985 | `85in0{n}cg` | xlsx (T1–4), xls (T5–6) |
| 1997 | `97soca{n}a` | xlsx |
| 1998 | `98in{n}ab` — **unpadded** | xlsx |
| 1999 | `99in0{n}ab` | xlsx |
| 2007 | `07in0{n}ab` | xls |
| 2008–2009 | `{yy}in0{n}soca` | xls |
| 2010–2012 | **`{yy}0{n}insoca`** — year and table **transposed** | xls |
| 2013–2015 | `{yy}in0{n}soca` | xlsx |

The 2010–2012 stub puts the table number before `in` (`1201insoca`) where
every other era puts it after (`13in01soca`). A sweep that assumes one word
order misses three years entirely — the same lesson as the W-2 family's
`inallw2` / `w2all` flip ([w2.md](w2.md)).

**TY1985, 1997, 1998 and 1999 each exist twice on the server**: the linked
`.xlsx` and an unlisted `.xls` twin. The `.xls` files are **BIFF4** — the
legacy Excel format `readxl` cannot open — and are presumably the originals;
the `.xlsx` are re-saves. The linked `.xlsx` is what is mirrored. Only 1985's
Tables 5–6 have no `.xlsx` and are stored as BIFF4 (`xlrd` reads them, via the
`read_biff4.py` bridge in IRS-Corp).

## The "1997 (Revised)" set is the 1998 publication's Tables 5a–8a

The source page lists a "1997 (Revised)" column. Those files are captioned
**"Table 5a … Tax Year 1997 (Revised)"** through **"Table 8a …"** — they were
published *as part of the 1998 set*, numbered after 1998's own Tables 1a–4a,
and are revised 1997 versions of Tables 1–4. They are stored here **by
content**: `soca_t1_1997rev` is the asset-type table (captioned 5a),
`soca_t2_1997rev` the AGI table (6a), and so on. Expect the caption inside to
disagree with the filename.

**Three of the page's four links for this set are dead.** It points at
`/pub/irs-tai/98in{5..8}ab.xlsx`, but only `98in5ab.xlsx` exists there — the
other three return a 404 that `curl -L` follows to an HTML error page (a
"spreadsheet" beginning `<!DOCTYPE html>`). The full set is live under
`/pub/irs-soi/` (as both `.xls` and `.xlsx`), which is what the downloader
uses for 6a–8a. The one `/pub/irs-tai/` file is the only thing in this store
fetched from that directory.

## The panel: two waves, and a neighbour that is not what it looks like

The **SOI Individual Panel** follows the same returns across years; its tables
are keyed by a year *range*, so they are not year-keyed files. Rather than a
separate mechanism, the downloader **pins each to the first year it covers**
— wave 1 (TY1999–2003) to 1999, wave 2 (TY2004–2007) to 2004 — and the
revised-1997 set to 1997, so `manifest.csv`'s `year` column stays meaningful.

Each wave has Tables 1–4 in the same content order as the cross-section, plus
a **Table 5 cross-section companion** ("…by Asset Type, Cross Section, Tax
Years 1999–2003"). Wave 2's stubs are inconsistent within the wave: Table 1 is
`04-07in01st.xls` but Tables 2–5 are `07in0{n}{suffix}.xls`, and **its Table 5
(`07in05st.xls`) is live but unlinked** on the page.

**`07in01st.xls` exists and is NOT a capital-assets file.** It is "Individual
Income and Tax Data, by State and Size of Adjusted Gross Income, Tax Year
2007" — a state table that happens to share the stub. A stub-pattern sweep
will surface it as a plausible wave-2 Table 1; the title check is what caught
it. Wave 2's real Table 1 is `04-07in01st.xls`.

## Known consumers

None yet. The natural cross-check is the Schedule D lines in the Pub 4801
line-item panel ([line_items.md](line_items.md)), but that panel currently
covers TY2018–2023 and this study ends at TY2015, so there is no overlap until
earlier line-item years are emitted. Against Pub 1304 Table 1.4A the overlap
is TY2012–2015, four years.
