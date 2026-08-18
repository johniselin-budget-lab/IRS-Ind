#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# run_checks.R
#
# Cross-checks the SOI line item estimates (Pub 4801) against the Pub 1304
# by-size tables already mirrored in the store.
#
# Both publications are built from the SAME weighted SOI sample, so matching
# items must agree EXACTLY. A difference is a parse bug or an SOI revision --
# never something to absorb into a tolerance. Items whose universes genuinely
# differ get an explicit relation in the crosswalk instead.
#
# Inputs:
#   checks/crosswalk_line_items.csv   curated map, versioned with this repo
#   <dest>/checks/line_item_values.csv  written by parse_line_items.py
#   <dest>/national/by_size/*.xls     the Pub 1304 targets
# Output:
#   <dest>/checks/_report.csv         one row per (tax year, item, measure)
#
# Usage:
#   python3 parse_line_items.py /path/to/store
#   Rscript run_checks.R --dest /path/to/store
#
# Exits non-zero if any comparison fails, so it can gate a build.
#------------------------------------------------------------------------------

suppressMessages(library(readxl))

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

crosswalk = utils::read.csv(file.path(script_dir, 'checks', 'crosswalk_line_items.csv'),
                            stringsAsFactors = FALSE)
# Differences already investigated and explained. Each entry pins an exact
# expected difference for one comparison; anything else -- including the same
# item differing by a different amount -- still fails.
known = utils::read.csv(file.path(script_dir, 'checks', 'known_differences.csv'),
                        stringsAsFactors = FALSE)

# The checks read the real deliverable, aligned/line_items.csv, so a parser
# regression fails here rather than passing a separately-derived side file.
# The cover-page total is not a form line, so it comes from the summary file.
lines   = utils::read.csv(file.path(dest, 'aligned', 'line_items.csv'),
                          stringsAsFactors = FALSE)
summary_values = utils::read.csv(file.path(dest, 'checks', 'line_item_values.csv'),
                                 stringsAsFactors = FALSE)

extracted = function(cw) {
  if (cw$form == '(summary)') {
    hit = summary_values[summary_values$tax_year == cw$tax_year &
                         summary_values$item == cw$line &
                         summary_values$measure == cw$measure, 'value']
  } else {
    hit = lines[lines$tax_year == cw$tax_year & lines$form == cw$form &
                lines$universe == cw$universe & lines$line == cw$line &
                lines$measure == cw$measure, 'value']
  }
  if (length(hit) == 1) hit else NA_real_   # 0 = missing, >1 = ambiguous
}

#--------------------------------------------
# Read one "All returns" row from a Pub 1304 table
#--------------------------------------------

# The item name sits in a merged cell spanning each Number-of-returns / Amount
# pair, so readxl gives it to the first column only and every Amount column
# would otherwise flatten to an indistinguishable "Amount | n". Carry the item
# name across the pair, keeping the published column number as a stable anchor.
flatten_header = function(x, hdr_rows) {
  hdr = apply(x[hdr_rows, ], 2,
              function(col) gsub('\\s+', ' ', paste(na.omit(col), collapse = ' | ')))
  for (j in seq_along(hdr)[-1]) {
    if (grepl('^Amount', hdr[j])) {
      hdr[j] = paste(sub(' \\| Number of returns.*$', '', hdr[j - 1]), '|', hdr[j])
    }
  }
  hdr
}

target_value = function(file, header_pattern, stub_pattern) {
  path = file.path(dest, 'national', 'by_size', file)
  if (!file.exists(path)) return(NA_real_)
  x   = as.data.frame(suppressMessages(read_excel(path, col_names = FALSE, n_max = 40)))
  hdr = flatten_header(x, 3:8)
  j   = grep(header_pattern, hdr)
  i   = grep(stub_pattern, trimws(x[[1]]))
  if (length(j) != 1 || length(i) < 1) return(NA_real_)
  suppressWarnings(as.numeric(unlist(x[i[1], ])))[j]
}

#----------------
# Run the checks
#----------------

report = do.call(rbind, lapply(seq_len(nrow(crosswalk)), function(k) {
  cw     = crosswalk[k, ]
  source = extracted(cw)
  target = target_value(sub('\\{year\\}', cw$tax_year, cw$target_file),
                        cw$header_pattern, cw$stub_pattern)
  data.frame(tax_year = cw$tax_year, form = cw$form, line = cw$line,
             measure = cw$measure, pub4801 = source, pub1304 = target,
             diff = source - target, relation = cw$relation,
             stringsAsFactors = FALSE)
}))

report$status = ifelse(is.na(report$pub4801), 'not extracted',
                ifelse(is.na(report$pub1304), 'no target',
                ifelse(report$relation == '==' & report$diff == 0, 'ok', 'MISMATCH')))

# Demote documented differences, matched on the exact expected amount
pinned = merge(report[report$status == 'MISMATCH', ], known,
               by = c('tax_year', 'line', 'measure', 'diff'))
if (nrow(pinned) > 0) {
  key = function(d) paste(d$tax_year, d$line, d$measure, d$diff)
  report$status[key(report) %in% key(pinned)] = 'known diff'
}
report = report[order(report$tax_year, report$line, report$measure), ]

dir.create(file.path(dest, 'checks'), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(report, file.path(dest, 'checks', '_report.csv'), row.names = FALSE)

bad = report[report$status %in% c('MISMATCH', 'not extracted'), ]
if (nrow(bad) > 0) {
  print(bad[, c('tax_year', 'form', 'line', 'measure', 'pub4801', 'pub1304',
                'diff', 'status')], row.names = FALSE)
} else {
  message('all ', nrow(report), ' comparisons resolved')
}
print(table(report$tax_year, report$status))

n_ok  = sum(report$status == 'ok')
n_bad = sum(report$status %in% c('MISMATCH', 'not extracted'))
message('\n', n_ok, ' exact matches, ',
        sum(report$status == 'known diff'), ' known differences, ',
        n_bad, ' unexplained mismatches, ',
        sum(report$status == 'no target'), ' without a Pub 1304 target, ',
        sum(report$status == 'not extracted'), ' not extracted')
if (n_bad > 0) quit(status = 1)
