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
#
# Budget Lab internal users: pass the lab's shared raw_data store (documented
# internally) via --dest.
#
# Idempotent: existing target files are skipped (delete a file to re-fetch).
# Missing years/files (HTTP 404) are skipped with a message. manifest.csv is
# rewritten from what is on disk each run (prior retrieval dates preserved).
# Base R only; gzip via the system binary.
#------------------------------------------------------------------------------

#-----------------
# Parse arguments
#-----------------

args = commandArgs(trailingOnly = TRUE)

script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) > 0 && args[1] == '--dest') {
  if (length(args) < 2) stop('--dest requires a path')
  dest = args[2]
  args = args[-(1:2)]
}
years = if (length(args) >= 2) as.integer(args[1]):as.integer(args[2]) else 2011:2023

dir.create(dest, recursive = TRUE, showWarnings = FALSE)
message('Destination: ', normalizePath(dest))

BASE = 'https://www.irs.gov/pub/irs-soi'

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

# One row per (source file, target path); gz = whether to gzip after download.
# Documentation targets whose pattern does not exist for a given year (e.g.
# HT2 docguides, published sporadically) simply 404 and are skipped
targets = function(year) {
  yy = sprintf('%02d', year %% 100)
  list(

    # Data
    list(url = ht2_file(yy, year),
         to  = sprintf('state/HT2/ht2_%d.csv.gz', year),           gz = TRUE),
    list(url = sprintf('%sinstateshares.csv', yy),
         to  = sprintf('state/percentile/state_shares_%d.csv.gz', year), gz = TRUE),
    list(url = sprintf('%sincyallagi.csv', yy),
         to  = sprintf('county/county_%d_agi.csv.gz', year),        gz = TRUE),
    list(url = sprintf('%sincyallnoagi.csv', yy),
         to  = sprintf('county/county_%d_noagi.csv.gz', year),      gz = TRUE),
    list(url = sprintf('%szpallagi.csv', yy),
         to  = sprintf('zip/zip_%d_agi.csv.gz', year),              gz = TRUE),
    list(url = sprintf('%szpallnoagi.csv', yy),
         to  = sprintf('zip/zip_%d_noagi.csv.gz', year),            gz = TRUE),

    # --- National companion tables (by size of AGI) -----------------------
    # SOI Complete-Report (Pub 1304) basic tables, NATIONAL only (no geography).
    # These are the distributional backbone the geographic files lack: they
    # resolve AGI classes up to $10,000,000+ with full sources of income, so
    # they anchor the top of the distribution when the state x AGI (HT2) files
    # are reweighted. Published as .xls, not CSV -> stored raw (readxl reads
    # .xls directly; gzip would break direct reads). Table 1.4A begins TY2012
    # (2011 404s and is skipped). Naming: {yy}in{tbl}{suffix}.xls. See
    # notes/national_bysize.md for the table -> filename map and gotchas.
    list(url = sprintf('%sin11si.xls',  yy),
         to  = sprintf('national/by_size/income_tax_items_%d.xls',    year), gz = FALSE),  # T1.1
    list(url = sprintf('%sin12ms.xls',  yy),
         to  = sprintf('national/by_size/marital_status_%d.xls',      year), gz = FALSE),  # T1.2
    list(url = sprintf('%sin14ar.xls',  yy),
         to  = sprintf('national/by_size/income_sources_%d.xls',      year), gz = FALSE),  # T1.4
    list(url = sprintf('%sin14acg.xls', yy),
         to  = sprintf('national/by_size/capital_assets_%d.xls',      year), gz = FALSE),  # T1.4A
    list(url = sprintf('%sin21id.xls',  yy),
         to  = sprintf('national/by_size/itemized_deductions_%d.xls', year), gz = FALSE),  # T2.1

    # Wider Pub 1304 by-size set (added 2026-08; published through TY2023).
    # Single filename pattern per table holds for 2003+ vintages -- earlier
    # years use different suffixes (e.g. {yy}in12ar, {yy}in35mt; 1997 drops
    # suffixes entirely), so extend the per-table maps before pulling
    # pre-2003. Late starters (T1.6 2008, T1.7 2012, T2.7 2014, T3.1A 2008)
    # simply 404 and are skipped in earlier years.
    list(url = sprintf('%sin16ag.xls',  yy),
         to  = sprintf('national/by_size/returns_marital_age_%d.xls',        year), gz = FALSE),  # T1.6
    list(url = sprintf('%sin17dp.xls',  yy),
         to  = sprintf('national/by_size/dependent_returns_%d.xls',          year), gz = FALSE),  # T1.7
    list(url = sprintf('%sin25ic.xls',  yy),
         to  = sprintf('national/by_size/eitc_%d.xls',                       year), gz = FALSE),  # T2.5
    list(url = sprintf('%sin27aca.xls', yy),
         to  = sprintf('national/by_size/aca_items_%d.xls',                  year), gz = FALSE),  # T2.7
    list(url = sprintf('%sin31mt.xls',  yy),
         to  = sprintf('national/by_size/modified_taxable_income_%d.xls',    year), gz = FALSE),  # T3.1
    list(url = sprintf('%sin31amt.xls', yy),
         to  = sprintf('national/by_size/form8615_%d.xls',                   year), gz = FALSE),  # T3.1A
    list(url = sprintf('%sin32tt.xls',  yy),
         to  = sprintf('national/by_size/tax_pct_of_agi_%d.xls',             year), gz = FALSE),  # T3.2
    list(url = sprintf('%sin33ar.xls',  yy),
         to  = sprintf('national/by_size/tax_liability_%d.xls',              year), gz = FALSE),  # T3.3
    list(url = sprintf('%sin35tr.xls',  yy),
         to  = sprintf('national/by_size/tax_generated_byrate_%d.xls',       year), gz = FALSE),  # T3.5

    # Documentation, saved alongside the data
    list(url = sprintf('%sinstatesharesdocguide.pdf', yy),
         to  = sprintf('state/percentile/state_shares_docguide_%d.pdf', year), gz = FALSE),
    list(url = sprintf('%sin54cmdocguide.doc', yy),
         to  = sprintf('state/HT2/ht2_docguide_%d.doc', year),      gz = FALSE),
    # {yy}incmdocguide.doc is titled "State Data Documentation Guide": it
    # documents the HT2-companion state files AND the variable set shared
    # with the county files, and SOI links it from both pages -- save it
    # alongside both (see notes/county.md caveat)
    list(url = sprintf('%sincmdocguide.doc', yy),
         to  = sprintf('state/HT2/state_docguide_%d.doc', year),    gz = FALSE),
    list(url = sprintf('%sincmdocguide.doc', yy),
         to  = sprintf('county/county_docguide_%d.doc', year),      gz = FALSE),
    list(url = zpdoc_file(yy, year),
         to  = sprintf('zip/zip_docguide_%d.%s', year,
                       if (year >= 2017) 'docx' else 'doc'),        gz = FALSE)
  )
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
    utils::download.file(file.path(BASE, url), raw, mode = 'wb', quiet = TRUE) == 0,
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
  for (tg in targets(year)) {
    status = fetch_one(tg$url, tg$to, tg$gz)
    if (file.exists(tg$to)) {
      manifest[[tg$to]] = data.frame(
        path      = tg$to,
        url       = file.path(BASE, tg$url),
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
}
mf = mf[order(mf$path), ]
utils::write.csv(mf, 'manifest.csv', row.names = FALSE)
message('Wrote manifest.csv (', nrow(mf), ' files)')
