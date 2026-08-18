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
# Families (--only, comma-separated; default all): geo, by_size. Flags may be
# given in any order; the two positional arguments are the year range.
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

FAMILIES = c('geo', 'by_size')

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

years = if (length(pos) == 2) as.integer(pos[1]):as.integer(pos[2]) else 2011:2023

dir.create(dest, recursive = TRUE, showWarnings = FALSE)
message('Destination: ', normalizePath(dest))
message('Families:    ', paste(only, collapse = ', '))

# Source directory on irs.gov. Targets carry a COMPLETE url, so families that
# publish elsewhere (/pub/irs-pdf, /pub/irs-prior, /pub/irs-tai) can name their
# own directory without touching the fetch machinery.
SOI = 'https://www.irs.gov/pub/irs-soi'

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

# One flat target list for the families selected on the command line.
targets = function(year, families) {
  out = list()
  if ('geo'     %in% families) out = c(out, targets_geo(year))
  if ('by_size' %in% families) out = c(out, targets_by_size(year))
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
