#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# check_arithmetic.R
#
# Structural check on the extracted line items: every subtotal a form states
# about itself must equal its own components.
#
# The forms carry their own arithmetic -- "Add lines 1z, 2b, 3b, 4b, 5b, 6b, 7,
# and 8", "Subtract line 10 from line 9" -- and parse_line_items.py records
# those statements in aligned/line_relations.csv. Checking them exercises
# EVERY extracted amount, where the curated crosswalk in run_checks.R can only
# name a dozen lines a year. It is the check that catches a value quietly
# landing on the wrong line.
#
# Amounts only. Return COUNTS are not additive -- one return can carry several
# component lines, so a total's count is not the sum of its parts -- and
# checking them would produce failures that mean nothing.
#
# Usage:  Rscript check_arithmetic.R --dest /path/to/store
# Writes: <dest>/checks/_arithmetic.csv
#------------------------------------------------------------------------------

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'
dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

items = utils::read.csv(file.path(dest, 'aligned', 'line_items.csv'),
                        stringsAsFactors = FALSE)
# caveat must be read as character: if a narrowed run happens to produce no
# nonlinear statements at all, read.csv types the empty column as logical NA
# and every downstream comparison silently returns NA rather than FALSE.
rels  = utils::read.csv(file.path(dest, 'aligned', 'line_relations.csv'),
                        stringsAsFactors = FALSE,
                        colClasses = c(caveat = 'character'))
rels$caveat[is.na(rels$caveat)] = ''

# The same statement is printed on a form's returns page and its amounts page
rels = unique(rels[, c('tax_year', 'form', 'universe', 'target_line', 'op',
                       'components', 'caveat', 'phrase')])

# Only linear statements can be checked in aggregate (see NONLINEAR in
# parse_line_items.py). The rest are counted and set aside, not silently
# dropped, so the share of the form that goes unchecked stays visible.
nonlinear = sum(rels$caveat == 'nonlinear')
rels = rels[rels$caveat != 'nonlinear', ]

amounts = items[items$measure == 'amount', ]
key = paste(amounts$tax_year, amounts$form, amounts$universe, amounts$line)
value_of = function(year, form, universe, line) {
  hit = amounts$value[key == paste(year, form, universe, line)]
  if (length(hit) == 1) hit else NA_real_
}

report = do.call(rbind, lapply(seq_len(nrow(rels)), function(i) {
  r     = rels[i, ]
  parts = strsplit(r$components, '|', fixed = TRUE)[[1]]
  target = value_of(r$tax_year, r$form, r$universe, r$target_line)
  vals   = vapply(parts, function(p) value_of(r$tax_year, r$form, r$universe, p),
                  numeric(1))
  expected = if (r$op == 'subtract') {
    if (length(vals) == 2) vals[1] - vals[2] else NA_real_
  } else sum(vals)

  data.frame(tax_year = r$tax_year, form = r$form, universe = r$universe,
             target_line = r$target_line, op = r$op, components = r$components,
             n_components = length(parts), n_missing = sum(is.na(vals)),
             target = target, expected = expected,
             diff = target - expected, phrase = r$phrase,
             stringsAsFactors = FALSE)
}))

report$status = ifelse(is.na(report$target), 'target not extracted',
                ifelse(report$n_missing > 0, 'component not extracted',
                ifelse(report$diff == 0, 'ok',
                ifelse(abs(report$diff) <= report$n_components, 'rounding', 'MISMATCH'))))

# A mismatch splits into two very different things, and only one is a defect:
#
#  * the stated sum lands exactly on ANOTHER line of the same form -- the
#    statement was filed under the wrong line, which is an extraction bug and
#    is worth chasing;
#  * the sum matches nothing -- almost always because the identity does not
#    survive aggregation. Beyond the outright nonlinear wording already set
#    aside, many lines are conditional per return (a return reports an amount
#    owed on one line OR an overpayment on another), so the totals of the
#    parts and of the whole are taken over different sets of returns.
#
# Separating them is the point of this check: it is a screen that surfaces the
# first kind, not a pass/fail gate on the second.
lands_on = rep(NA_character_, nrow(report))
for (i in which(report$status == 'MISMATCH')) {
  same = amounts[amounts$tax_year == report$tax_year[i] &
                 amounts$form     == report$form[i] &
                 amounts$universe == report$universe[i], ]
  hit = same$line[same$value == report$expected[i]]
  if (length(hit) > 0) lands_on[i] = paste(unique(hit), collapse = ',')
}
report$lands_on = lands_on
report$status[!is.na(lands_on)] = 'target mislabelled'
report = report[order(report$status, report$tax_year, report$form), ]

dir.create(file.path(dest, 'checks'), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(report, file.path(dest, 'checks', '_arithmetic.csv'),
                 row.names = FALSE)

cat('linear relations checked: ', nrow(report),
    '  (', nonlinear, ' nonlinear statements set aside)\n\n', sep = '')
print(table(report$status))

evaluable = report[report$status %in% c('ok', 'rounding', 'MISMATCH',
                                        'target mislabelled'), ]
cat('\nof ', nrow(evaluable), ' evaluable relations: ',
    round(100 * sum(evaluable$status %in% c('ok', 'rounding')) / nrow(evaluable), 1),
    '% reconcile\n', sep = '')

defects = report[report$status == 'target mislabelled', ]
if (nrow(defects) > 0) {
  cat('\nEXTRACTION DEFECTS -- the stated sum lands on another line:\n')
  print(defects[, c('tax_year', 'form', 'target_line', 'lands_on', 'phrase')],
        row.names = FALSE)
} else {
  cat('\nno relation resolved to the wrong line\n')
}
