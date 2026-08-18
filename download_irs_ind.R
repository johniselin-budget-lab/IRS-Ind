#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# download_irs_ind.R
#
# Downloads an organized copy of IRS SOI individual income tax statistics:
# the "data by geographic area" files
# https://www.irs.gov/statistics/soi-tax-stats-data-by-geographic-area
# plus the national Complete Report (Pub 1304) basic tables by size of AGI
#
# The DESTINATION is configurable: by default data lands in this repo's own
# (gitignored) data/ folder; pass --dest to download to a separate location
# instead (e.g. the shared cluster store). Layout under the destination:
#
#   state/HT2/         ht2_{year}.csv.gz          Historic Table 2 all-states
#                                                 CSV (state x AGI class)
#   state/percentile/  state_shares_{year}.csv.gz AGI percentile data by state
#                      state_shares_docguide_{year}.pdf
#   county/            county_{year}_agi.csv.gz   County income, by AGI class
#                      county_{year}_noagi.csv.gz County income, county totals
#   zip/               zip_{year}_agi.csv.gz      ZIP code data, by AGI class
#                      zip_{year}_noagi.csv.gz    ZIP code data, ZIP totals
#   national/line_items/ p4801_{year}.pdf          SOI line item estimates: every
#                      p5385_{year}.pdf           form/schedule line, no AGI cut
#   national/sole_prop/ sp_t{nn}_{year}.xls       Nonfarm sole proprietorship
#                      sp_t{nn}_sic_{year}.xls    (Schedule C); _sic = the
#                                                 1996-98 SIC-era companions
#   national/w2/       w2_t{n}_{year}.xlsx        Form W-2 statistics
#   national/ira/      ira_t{nn}_{year}.xls[x]    IRA accumulation/distribution,
#                      ira_t{nn}_ci_{year}.xlsx   ten tables; ci = confidence
#                      ira_t{nn}_cv_{year}.xlsx   intervals, cv = coeffs of var
#   national/by_size/  income_sources_{year}.xls  SOI Complete-Report (Pub 1304)
#                      capital_assets_{year}.xls  basic tables by size of AGI,
#                      income_tax_items_{year}.xls NATIONAL (no geography) -- the
#                      marital_status_{year}.xls   top-of-distribution anchor for
#                      itemized_deductions_{year}.xls the geographic reweighting,
#                      returns_marital_age_{year}.xls plus the wider Pub 1304
#                      dependent_returns_{year}.xls   by-size set (tax items,
#                      eitc_{year}.xls                credits, rate brackets)
#                      aca_items_{year}.xls
#                      modified_taxable_income_{year}.xls
#                      form8615_{year}.xls
#                      tax_pct_of_agi_{year}.xls
#                      tax_liability_{year}.xls
#                      tax_generated_byrate_{year}.xls
#   manifest.csv       path, source url, year, bytes, md5, retrieval date
#
# SOI file-naming quirks encoded below (verified against irs.gov 2026-07-12):
#   - HT2 all-states CSV: {yy}in54cmcsv.csv for 2012-2017 (2013 unpublished),
#     18in55cmagi.csv for 2018 (one-off), {yy}in55cmcsv.csv for 2019+. No
#     all-states CSV before 2012 (per-state spreadsheets only).
#   - Percentile (instateshares): 2013+.
#   - County CSVs ({yy}incyallagi/noagi): 2011 and 2013+; 2012 and earlier are
#     zip archives on the county page (not pulled here).
#   - ZIP CSVs ({yy}zpallagi/noagi): 2011+.
#
# Usage:
#   Rscript download_irs_ind.R                              # -> ./data, 2011-2023
#   Rscript download_irs_ind.R 2017 2023                    # custom year range
#   Rscript download_irs_ind.R --dest /path/to/store        # separate location
#   Rscript download_irs_ind.R --dest /path/to/store 2017 2023
#   Rscript download_irs_ind.R --only by_size               # one family only
#
# Families (--only, comma-separated; default all): geo, by_size, ira,
# sole_prop, w2, line_items. Flags may be given in any order; the two
# positional arguments are the year range. Each family is clamped to the
# first year it publishes (see FIRST_YEAR), so the default run covers
# 1996-2023 without probing years a family lacks.
#
# Budget Lab internal users: pass the lab's shared raw_data store (documented
# internally) via --dest.
#
# Idempotent: existing target files are skipped (delete a file to re-fetch).
# Missing years/files (HTTP 404) are skipped with a message. manifest.csv is
# rewritten each run: rows for the files this run visited, plus every prior
# row whose file is still on disk (so a narrowed run does not truncate it).
# Prior retrieval dates are preserved.
# Base R only; gzip via the system binary.
#------------------------------------------------------------------------------

#-----------------
# Parse arguments
#-----------------

args = commandArgs(trailingOnly = TRUE)

script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

FAMILIES = c('geo', 'by_size', 'ira', 'sole_prop', 'w2', 'line_items')

# First tax year each family publishes. The default run spans their union
# and every family is clamped to its own floor, so no year is fetched
# pointlessly (IRA reaches back to 2000; the others start at 2011).
FIRST_YEAR = c(geo = 2011, by_size = 2011, ira = 2000,
               sole_prop = 1996, w2 = 2019, line_items = 2003)

dest = file.path(script_dir, 'data')
only = FAMILIES
pos  = character(0)

i = 1
while (i <= length(args)) {
  flag = args[i]
  if (flag == '--dest') {
    if (i == length(args)) stop('--dest requires a path')
    dest = args[i + 1]
    i = i + 2
  } else if (flag == '--only') {
    if (i == length(args)) stop('--only requires a comma-separated family list')
    only = trimws(strsplit(args[i + 1], ',')[[1]])
    i = i + 2
  } else {
    pos = c(pos, flag)
    i = i + 1
  }
}

unknown = setdiff(only, FAMILIES)
if (length(unknown) > 0) {
  stop('unknown family: ', paste(unknown, collapse = ', '),
       '  (known: ', paste(FAMILIES, collapse = ', '), ')')
}

# Catch a mistyped flag before it is silently read as a year
if (!(length(pos) %in% c(0, 2))) {
  stop('expected two positional arguments (first year, last year), got: ',
       paste(pos, collapse = ' '))
}
if (length(pos) == 2 && anyNA(suppressWarnings(as.integer(pos)))) {
  stop('year range must be two integers, got: ', paste(pos, collapse = ' '))
}

years = if (length(pos) == 2) as.integer(pos[1]):as.integer(pos[2]) else min(FIRST_YEAR):2023

dir.create(dest, recursive = TRUE, showWarnings = FALSE)
message('Destination: ', normalizePath(dest))
message('Families:    ', paste(only, collapse = ', '))

# Source directory on irs.gov. Targets carry a COMPLETE url, so families that
# publish elsewhere (/pub/irs-pdf, /pub/irs-prior, /pub/irs-tai) can name their
# own directory without touching the fetch machinery.
SOI       = 'https://www.irs.gov/pub/irs-soi'
IRS_PDF   = 'https://www.irs.gov/pub/irs-pdf'      # current revision of a pub
IRS_PRIOR = 'https://www.irs.gov/pub/irs-prior'    # superseded revisions

#---------------------------
# Source file specifications
#---------------------------

# HT2 filename lineage
ht2_file = function(yy, year) {
  if (year >= 2019) return(sprintf('%sin55cmcsv.csv', yy))
  if (year == 2018) return('18in55cmagi.csv')
  sprintf('%sin54cmcsv.csv', yy)   # 2012-2017 (2013 unpublished)
}

# ZIP-code documentation switched .doc -> .docx in 2017
zpdoc_file = function(yy, year) {
  sprintf('%szpdoc.%s', yy, if (year >= 2017) 'docx' else 'doc')
}

# Each family builds one row per (source file, target path); url is complete,
# gz = whether to gzip after download. Documentation targets whose pattern does
# not exist for a given year (e.g. HT2 docguides, published sporadically)
# simply 404 and are skipped.

# --- geo: the by-geographic-area CSVs, plus their documentation guides -------
targets_geo = function(year) {
  yy = sprintf('%02d', year %% 100)
  list(

    # Data
    list(url = file.path(SOI, ht2_file(yy, year)),
         to  = sprintf('state/HT2/ht2_%d.csv.gz', year),           gz = TRUE),
    list(url = file.path(SOI, sprintf('%sinstateshares.csv', yy)),
         to  = sprintf('state/percentile/state_shares_%d.csv.gz', year), gz = TRUE),
    list(url = file.path(SOI, sprintf('%sincyallagi.csv', yy)),
         to  = sprintf('county/county_%d_agi.csv.gz', year),        gz = TRUE),
    list(url = file.path(SOI, sprintf('%sincyallnoagi.csv', yy)),
         to  = sprintf('county/county_%d_noagi.csv.gz', year),      gz = TRUE),
    list(url = file.path(SOI, sprintf('%szpallagi.csv', yy)),
         to  = sprintf('zip/zip_%d_agi.csv.gz', year),              gz = TRUE),
    list(url = file.path(SOI, sprintf('%szpallnoagi.csv', yy)),
         to  = sprintf('zip/zip_%d_noagi.csv.gz', year),            gz = TRUE),

    # Documentation, saved alongside the data
    list(url = file.path(SOI, sprintf('%sinstatesharesdocguide.pdf', yy)),
         to  = sprintf('state/percentile/state_shares_docguide_%d.pdf', year), gz = FALSE),
    list(url = file.path(SOI, sprintf('%sin54cmdocguide.doc', yy)),
         to  = sprintf('state/HT2/ht2_docguide_%d.doc', year),      gz = FALSE),
    # {yy}incmdocguide.doc is titled "State Data Documentation Guide": it
    # documents the HT2-companion state files AND the variable set shared
    # with the county files, and SOI links it from both pages -- save it
    # alongside both (see notes/county.md caveat)
    list(url = file.path(SOI, sprintf('%sincmdocguide.doc', yy)),
         to  = sprintf('state/HT2/state_docguide_%d.doc', year),    gz = FALSE),
    list(url = file.path(SOI, sprintf('%sincmdocguide.doc', yy)),
         to  = sprintf('county/county_docguide_%d.doc', year),      gz = FALSE),
    list(url = file.path(SOI, zpdoc_file(yy, year)),
         to  = sprintf('zip/zip_docguide_%d.%s', year,
                       if (year >= 2017) 'docx' else 'doc'),        gz = FALSE)
  )
}

# SOI Complete-Report (Pub 1304) basic tables, NATIONAL only (no geography).
# These are the distributional backbone the geographic files lack: they
# resolve AGI classes up to $10,000,000+ with full sources of income, so
# they anchor the top of the distribution when the state x AGI (HT2) files
# are reweighted. Published as .xls, not CSV -> stored raw (readxl reads
# .xls directly; gzip would break direct reads). Table 1.4A begins TY2012
# (2011 404s and is skipped). Naming: {yy}in{tbl}{suffix}.xls. See
# notes/national_bysize.md for the table -> filename map and gotchas.
#
# Single filename pattern per table holds for 2003+ vintages -- earlier years
# use different suffixes (e.g. {yy}in12ar, {yy}in35mt; 1997 drops suffixes
# entirely), so extend the per-table maps before pulling pre-2003. Late
# starters (T1.6 2008, T1.7 2012, T2.7 2014, T3.1A 2008) simply 404 and are
# skipped in earlier years.

# --- by_size: national Pub 1304 basic tables by size of AGI ------------------
targets_by_size = function(year) {
  yy = sprintf('%02d', year %% 100)
  list(
    list(url = file.path(SOI, sprintf('%sin11si.xls',  yy)),
         to  = sprintf('national/by_size/income_tax_items_%d.xls',    year), gz = FALSE),  # T1.1
    list(url = file.path(SOI, sprintf('%sin12ms.xls',  yy)),
         to  = sprintf('national/by_size/marital_status_%d.xls',      year), gz = FALSE),  # T1.2
    list(url = file.path(SOI, sprintf('%sin14ar.xls',  yy)),
         to  = sprintf('national/by_size/income_sources_%d.xls',      year), gz = FALSE),  # T1.4
    list(url = file.path(SOI, sprintf('%sin14acg.xls', yy)),
         to  = sprintf('national/by_size/capital_assets_%d.xls',      year), gz = FALSE),  # T1.4A
    list(url = file.path(SOI, sprintf('%sin21id.xls',  yy)),
         to  = sprintf('national/by_size/itemized_deductions_%d.xls', year), gz = FALSE),  # T2.1
    list(url = file.path(SOI, sprintf('%sin16ag.xls',  yy)),
         to  = sprintf('national/by_size/returns_marital_age_%d.xls',        year), gz = FALSE),  # T1.6
    list(url = file.path(SOI, sprintf('%sin17dp.xls',  yy)),
         to  = sprintf('national/by_size/dependent_returns_%d.xls',          year), gz = FALSE),  # T1.7
    list(url = file.path(SOI, sprintf('%sin25ic.xls',  yy)),
         to  = sprintf('national/by_size/eitc_%d.xls',                       year), gz = FALSE),  # T2.5
    list(url = file.path(SOI, sprintf('%sin27aca.xls', yy)),
         to  = sprintf('national/by_size/aca_items_%d.xls',                  year), gz = FALSE),  # T2.7
    list(url = file.path(SOI, sprintf('%sin31mt.xls',  yy)),
         to  = sprintf('national/by_size/modified_taxable_income_%d.xls',    year), gz = FALSE),  # T3.1
    list(url = file.path(SOI, sprintf('%sin31amt.xls', yy)),
         to  = sprintf('national/by_size/form8615_%d.xls',                   year), gz = FALSE),  # T3.1A
    list(url = file.path(SOI, sprintf('%sin32tt.xls',  yy)),
         to  = sprintf('national/by_size/tax_pct_of_agi_%d.xls',             year), gz = FALSE),  # T3.2
    list(url = file.path(SOI, sprintf('%sin33ar.xls',  yy)),
         to  = sprintf('national/by_size/tax_liability_%d.xls',              year), gz = FALSE),  # T3.3
    list(url = file.path(SOI, sprintf('%sin35tr.xls',  yy)),
         to  = sprintf('national/by_size/tax_generated_byrate_%d.xls',       year), gz = FALSE)   # T3.5
  )
}

# --- ira: accumulation and distribution of IRAs -----------------------------
# Ten tables, TY2000-2023 (TY2003 was never published). Modern naming is
# {yy}in{nn}ira.{xls,xlsx} with nn = the table number, .xls through TY2016 and
# .xlsx from TY2017. TY2000-2004 number the FILES differently from the tables
# the modern series uses, so those years need an explicit map: modern table ->
# published file slot. Verified by opening the files -- 02in06ira.xls is
# titled "Table 6 ... by Type" (modern Table 1), 02in09/04in05 are "by Filing
# Status and Gender" (modern Table 7), and 04in06/04in07 are the traditional/
# Roth contribution tables (modern Tables 5/6). Tables absent from a year's
# map were not published that year. See notes/ira.md.
IRA_SLOTS = list(
  '2000' = c('1' = 1, '2' = 2, '3' = 3, '4' = 5, '7' = 4),
  '2001' = c('1' = 1, '2' = 2, '3' = 3, '4' = 5, '7' = 4),
  '2002' = c('1' = 6, '2' = 7, '3' = 8, '4' = 10, '7' = 9),
  '2004' = c('1' = 1, '2' = 2, '3' = 3, '4' = 4, '5' = 6, '6' = 7, '7' = 5)
)

ira_file = function(yy, year, slot, kind = '') {
  stem = if (year == 2000) 'ir' else 'ira'    # TY2000 drops the final 'a'
  ext  = if (year >= 2017) 'xlsx' else 'xls'
  sprintf('%sin%02d%s%s.%s', yy, slot, stem, kind, ext)
}

targets_ira = function(year) {
  yy    = sprintf('%02d', year %% 100)
  slots = IRA_SLOTS[[as.character(year)]]
  if (is.null(slots)) slots = setNames(1:10, 1:10)
  ext   = if (year >= 2017) 'xlsx' else 'xls'

  out = lapply(names(slots), function(tbl) {
    list(url = file.path(SOI, ira_file(yy, year, slots[[tbl]])),
         to  = sprintf('national/ira/ira_t%02d_%d.%s', as.integer(tbl), year, ext),
         gz  = FALSE)
  })

  # Precision companions, published under the modern numbering only:
  # confidence intervals from TY2022 (all ten tables), coefficients of
  # variation from TY2018 for tables 1-7 (TY2019 has none -- the source page's
  # 2019 "CV" links point at the data files themselves).
  if (year >= 2018) {
    out = c(out, lapply(1:10, function(t)
      list(url = file.path(SOI, ira_file(yy, year, t, 'ci')),
           to  = sprintf('national/ira/ira_t%02d_ci_%d.xlsx', t, year), gz = FALSE)))
    out = c(out, lapply(1:7, function(t)
      list(url = file.path(SOI, ira_file(yy, year, t, '-cv')),
           to  = sprintf('national/ira/ira_t%02d_cv_%d.xlsx', t, year), gz = FALSE)))
  }
  out
}

# --- sole_prop: nonfarm sole proprietorships (Schedule C) -------------------
# Tables 1-2 are the durable series and run 1998-2023; Table 3 (by size of
# business receipts) covers 2016-2020 and Table 4 (Schedule C returns by AGI,
# marital status, age and industry) 2017-2020. Both were probed as absent for
# TY2021+ on 2026-08-17.
#
# TY1998 is the SIC -> NAICS transition and published BOTH classifications:
# its Tables 1-2 are SIC and its Tables 3-4 are the NAICS versions. The
# canonical sp_t{nn}_{year} series is therefore NAICS throughout (taking
# sp03ic/sp04ic for 1998), and the SIC pair is stored alongside as
# sp_t{nn}_sic_{year}. Verified by opening the files -- see notes/sole_prop.md.
SP_STEM = list('1' = 'sp01br', '2' = 'sp02is', '3' = 'sp03szbr', '4' = 'sp04ra')
SP_YEARS = list('1' = 1998:2023, '2' = 1998:2023, '3' = 2016:2020, '4' = 2017:2020)
SP_OVERRIDE = list(
  '1' = c('1998' = 'sp03ic', '2000' = 'sp01is', '2001' = 'sp01ic',
          '2002' = 'sp01is', '2003' = 'sp01cs'),
  '2' = c('1998' = 'sp04ic', '2001' = 'sp02ic', '2003' = 'sp02cs'),
  '3' = c('2016' = 'sp03br')
)
SP_SIC = list(
  '1996' = c('1' = 'spo1ig', '2' = 'sp02ig'),   # Table 1 has a letter o, not 01
  '1997' = c('1' = 'sp01ig', '2' = 'sp02ig'),
  '1998' = c('1' = 'sp01ic', '2' = 'sp02ic')
)

targets_sole_prop = function(year) {
  yy  = sprintf('%02d', year %% 100)
  key = as.character(year)
  out = list()

  for (tbl in names(SP_STEM)) {
    if (!(year %in% SP_YEARS[[tbl]])) next
    ov   = SP_OVERRIDE[[tbl]]
    stem = if (!is.null(ov) && key %in% names(ov)) unname(ov[[key]]) else SP_STEM[[tbl]]
    out  = c(out, list(list(
      url = file.path(SOI, sprintf('%s%s.xls', yy, stem)),
      to  = sprintf('national/sole_prop/sp_t%02d_%d.xls', as.integer(tbl), year),
      gz  = FALSE)))
  }

  sic = SP_SIC[[key]]
  for (tbl in names(sic)) {
    out = c(out, list(list(
      url = file.path(SOI, sprintf('%s%s.xls', yy, sic[[tbl]])),
      to  = sprintf('national/sole_prop/sp_t%02d_sic_%d.xls', as.integer(tbl), year),
      gz  = FALSE)))
  }

  # TY2015 one-off: published as "Table 3" but carrying Table 2's content --
  # an expanded income statement. Named for the content, not the caption.
  if (year == 2015) out = c(out, list(list(
    url = file.path(SOI, '15sp03isexpanded.xls'),
    to  = 'national/sole_prop/sp_t02_expanded_2015.xls', gz = FALSE)))

  out
}

# --- w2: Form W-2 statistics ------------------------------------------------
# Four tables cross-tabulating wage income, elective retirement contributions
# and the retirement-plan indicator by age, sex, size of wages and size of AGI.
# TY2019-2020 only; TY2021+ probed and absent 2026-08-17. The stub is stable,
# so a new year is picked up automatically once SOI publishes it.
targets_w2 = function(year) {
  yy = sprintf('%02d', year %% 100)
  lapply(1:4, function(t)
    list(url = file.path(SOI, sprintf('%sin0%dw2all.xlsx', yy, t)),
         to  = sprintf('national/w2/w2_t%d_%d.xlsx', t, year),
         gz  = FALSE))
}

# --- line_items: Pub 4801 / Pub 5385 line item estimates --------------------
# Estimated number of returns and amount for EVERY line of every form and
# schedule -- far more line detail than Pub 1304, with no AGI dimension. Both
# publications are PDFs printed on facsimiles of the forms themselves.
#
# Three filename eras plus a moving current-revision URL, and the revision
# token is a publication date that cannot be derived from the tax year, so
# the map is explicit. The source page is the only authority for it.
#
# NOTE: /pub/irs-pdf/p4801.pdf always holds the NEWEST tax year. When TY2024
# publishes, that URL changes content and the TY2023 revision moves to
# /pub/irs-prior/. manifest.csv's md5 is what catches the swap -- re-check
# the source page's year -> URL map whenever a new year is expected.
P4801 = c(
  setNames(file.path(SOI, sprintf('%dlinecnt.pdf', 2004:2007)), 2004:2007),
  setNames(file.path(SOI, sprintf('%02dinlinecount.pdf', (2008:2016) %% 100)), 2008:2016),
  c('2003' = file.path(SOI, '03linecnt.pdf'),
    '2017' = file.path(IRS_PRIOR, 'p4801--2019.pdf'),
    '2018' = file.path(IRS_PRIOR, 'p4801--2020.pdf'),
    '2019' = file.path(IRS_PRIOR, 'p4801--2021.pdf'),
    '2020' = file.path(IRS_PRIOR, 'p4801--2022.pdf'),
    '2021' = file.path(IRS_PRIOR, 'p4801--2024.pdf'),
    '2022' = file.path(IRS_PRIOR, 'p4801--122024.pdf'),
    '2023' = file.path(IRS_PDF,   'p4801.pdf'))
)

# Pub 5385 (information returns). TY2018 and TY2019 share ONE url: it is a PDF
# Portfolio wrapping both revisions as embedded files, so it is fetched once
# and stored under a range name rather than downloaded twice. See notes.
P5385 = c(
  '2017' = file.path(IRS_PRIOR, 'p5385--2019.pdf'),
  '2018' = file.path(IRS_PRIOR, 'p5385--2021.pdf'),
  '2020' = file.path(IRS_PRIOR, 'p5385--2023.pdf'),
  '2021' = file.path(IRS_PRIOR, 'p5385--2024.pdf'),
  '2022' = file.path(IRS_PRIOR, 'p5385--042025.pdf'),
  '2023' = file.path(IRS_PDF,   'p5385.pdf')
)
P5385_NAME = c('2018' = 'p5385_2018-2019.pdf')     # the portfolio's two years

targets_line_items = function(year) {
  key = as.character(year)
  out = list()
  if (key %in% names(P4801)) {
    out = c(out, list(list(url = unname(P4801[key]),
                           to  = sprintf('national/line_items/p4801_%d.pdf', year),
                           gz  = FALSE)))
  }
  if (key %in% names(P5385)) {
    name = if (key %in% names(P5385_NAME)) unname(P5385_NAME[key])
           else sprintf('p5385_%d.pdf', year)
    out = c(out, list(list(url = unname(P5385[key]),
                           to  = file.path('national/line_items', name),
                           gz  = FALSE)))
  }
  out
}

# One flat target list for the families selected on the command line, each
# clamped to the first year it publishes.
targets = function(year, families) {
  wanted = function(fam) fam %in% families && year >= FIRST_YEAR[[fam]]
  out = list()
  if (wanted('geo'))        out = c(out, targets_geo(year))
  if (wanted('by_size'))    out = c(out, targets_by_size(year))
  if (wanted('ira'))        out = c(out, targets_ira(year))
  if (wanted('sole_prop'))  out = c(out, targets_sole_prop(year))
  if (wanted('w2'))         out = c(out, targets_w2(year))
  if (wanted('line_items')) out = c(out, targets_line_items(year))
  out
}

#----------
# Download
#----------

fetch_one = function(url, to, gz) {

  if (file.exists(to)) {
    message('  exists, skipping: ', to)
    return(invisible('exists'))
  }
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)

  raw = if (gz) sub('\\.gz$', '', to) else to
  ok  = tryCatch(
    utils::download.file(url, raw, mode = 'wb', quiet = TRUE) == 0,
    error   = function(e) FALSE,
    warning = function(w) FALSE
  )
  if (!ok || !file.exists(raw) || file.size(raw) == 0) {
    unlink(raw)
    message('  not available (skipped): ', url)
    return(invisible('missing'))
  }
  if (gz) {
    system2('gzip', c('-f', shQuote(raw)))
  }
  message('  downloaded: ', to, '  (', format(file.size(to), big.mark = ','), ' bytes)')
  invisible('downloaded')
}

setwd(dest)

manifest = list()
for (year in years) {
  message('=== ', year, ' ===')
  for (tg in targets(year, only)) {
    status = fetch_one(tg$url, tg$to, tg$gz)
    if (file.exists(tg$to)) {
      manifest[[tg$to]] = data.frame(
        path      = tg$to,
        url       = tg$url,
        year      = year,
        bytes     = file.size(tg$to),
        md5       = unname(tools::md5sum(tg$to)),
        retrieved = if (status == 'downloaded') format(Sys.Date()) else NA,
        stringsAsFactors = FALSE
      )
    }
  }
}

#----------------
# Write manifest
#----------------

mf = do.call(rbind, manifest)
if (file.exists('manifest.csv')) {
  old = utils::read.csv('manifest.csv', stringsAsFactors = FALSE)
  mf$retrieved = ifelse(is.na(mf$retrieved),
                        old$retrieved[match(mf$path, old$path)],
                        mf$retrieved)
  # A narrowed run (--only, or a short year range) visits a subset of the
  # store, so carry over every prior row this run did not look at and whose
  # file is still on disk -- otherwise the manifest silently loses them.
  kept = old[!(old$path %in% mf$path) & file.exists(old$path), ]
  if (nrow(kept) > 0) mf = rbind(mf, kept)
}
mf = mf[order(mf$path), ]
utils::write.csv(mf, 'manifest.csv', row.names = FALSE)
message('Wrote manifest.csv (', nrow(mf), ' files)')
