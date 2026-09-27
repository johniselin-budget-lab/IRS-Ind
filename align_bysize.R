#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# align_bysize.R
#
# Tier 1 of notes/alignment_plan.md: turns every mirrored Pub 1304 by-size
# table (national/by_size/*.xls) into one long panel per table family, and
# checks the result against the tables' own arithmetic.
#
# Output, under <dest>/aligned/:
#   bysize_{family}.csv   one row per published cell, all years stacked:
#       tax_year, table, family, row_seq, panel, section, row_label,
#       row_agi_lo, row_agi_hi, col_seq, col_group, col_label,
#       col_agi_lo, col_agi_hi, value, flag
#     family is the store's file stem (returns_marital_age = Table 1.6; the
#     map is in notes/national_bysize.md). Values are as published: money in
#     $ thousands, counts in returns. AGI bounds are dollars, [lo, hi), with
#     'No adjusted gross income' = (-Inf, 1). flag: NA, 'caution' (*),
#     'combined' (**; a combined zero is NA), 'd' (suppressed), '-' (none
#     reported, value 0), 'blank', or a footnote marker '[n]'.
#   _bysize_additivity.csv  per (file, panel, section, column): the panel's
#     total against the sum of its size classes
#   _bysize_crosstable.csv  returns by AGI class in every all-returns table
#     against Table 1.4's, both summed to the classes the two share (Table
#     3.5's $2,000 steps against 1.4's, 1.4's split at $250k in TY2011-2012)
#   _bysize_labels.csv  coverage: the years each (family, col_group,
#     col_label) appears in. Labels drift (Table 1.4's and 1.7's wage column
#     reads "Total wages" in TY2022) and are NOT harmonized here -- a merge is
#     adopted only after a continuity check at the seam (alignment_plan.md)
#
# Usage:
#   Rscript align_bysize.R                          # this repo's data/
#   Rscript align_bysize.R --dest /path/to/store
#
# Exits non-zero, so it can gate a build, if any additivity or cross-table
# comparison fails without an explanation (a combined, suppressed or
# footnote-only cell in the group), if a cell a comparison needs is blank, or
# if a table meant for the cross-table check yields no comparison for a year
# Table 1.4 covers. The reader needs python3 with xlrd (read_xls_cells.py).
#------------------------------------------------------------------------------

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

source(file.path(script_dir, 'alignment_helpers.R'))

by_size_dir = file.path(dest, 'national', 'by_size')
aligned_dir = file.path(dest, 'aligned')
dir.create(aligned_dir, showWarnings = FALSE)

# Column labels that are not additive across size classes
NONADDITIVE_REGEX = 'percent|average|rate|ratio|mean|median'

# Size-class rounding: every published cell is rounded to a whole unit, so a
# total can miss the sum of n classes by up to about n/2 units. The check
# allows one unit per class, twice that, as notes/national_bysize.md states.
rounding_tolerance = function(n_classes) n_classes

# Returns by AGI class agree across tables to within this many returns per
# class compared (both are rounded from the same weighted sample)
CROSSTABLE_TOLERANCE_PER_CLASS = 2

# Tables whose universe is all returns, so their returns-by-AGI must agree
# with Table 1.4's (the same weighted sample)
ALL_RETURNS_FAMILIES = c('income_tax_items', 'marital_status', 'returns_marital_age',
                         'exemptions', 'tax_liability', 'tax_generated_byrate')

#-----------------------
# Extract
#-----------------------

files = sort(list.files(by_size_dir, pattern = '^[a-z0-9_]+_[0-9]{4}\\.xls$'))
if (length(files) == 0) stop('no by-size tables under ', by_size_dir)
family_of = sub('_[0-9]{4}\\.xls$', '', files)

panels = list()
for (fam in unique(family_of)) {
  parts = lapply(files[family_of == fam], function(f) {
    d = extract_bysize_sheet(file.path(by_size_dir, f), script_dir)
    table_no = regmatches(attr(d, 'title'),
                          regexec('^Table ([0-9]+\\.[0-9]+[A-Z]?)', attr(d, 'title')))[[1]][2]
    if (is.na(table_no)) stop(f, ': no table number in title "', attr(d, 'title'), '"')
    cbind(tax_year = as.integer(sub('.*_([0-9]{4})\\.xls$', '\\1', f)),
          table = table_no, family = fam, d, stringsAsFactors = FALSE)
  })
  panels[[fam]] = do.call(rbind, parts)
  if (length(unique(panels[[fam]]$table)) != 1) {
    stop(fam, ': files carry more than one table number: ',
         paste(unique(panels[[fam]]$table), collapse = ', '))
  }
  utils::write.csv(panels[[fam]], file.path(aligned_dir, sprintf('bysize_%s.csv', fam)),
                   row.names = FALSE, na = '')
  cat(sprintf('%-24s Table %-5s %2d years, %7d cells\n', fam, panels[[fam]]$table[1],
              length(unique(panels[[fam]]$tax_year)), nrow(panels[[fam]])))
}

#-----------------------
# Label coverage
#-----------------------

labels = do.call(rbind, lapply(panels, function(d) {
  u = unique(d[, c('family', 'table', 'col_group', 'col_label', 'tax_year')])
  a = aggregate(tax_year ~ family + table + col_group + col_label, u, function(y)
    paste(sort(y), collapse = ' '))
  names(a)[names(a) == 'tax_year'] = 'years'
  a$n_years = lengths(strsplit(a$years, ' '))
  a
}))
utils::write.csv(labels, file.path(aligned_dir, '_bysize_labels.csv'), row.names = FALSE)

#-----------------------
# Additivity
#-----------------------

# Do the classes [lo, hi) tile one interval with no gap or overlap?
is_partition = function(lo, hi) {
  o = order(lo)
  length(lo) >= 2 && all(hi[o][-length(o)] == lo[o][-1])
}

# Status of one total-against-classes comparison. A missing value is
# explained when its cell says why (combined, suppressed, footnote-only) and
# unexplained -- 'blank' -- when the cell is simply empty.
explains_missing = function(flags) flags %in% c('combined', 'd') | grepl('^\\[', flags)

additivity_status = function(total, total_flag, parts, flags) {
  if (is.na(total)) return(if (explains_missing(total_flag)) 'no_total' else 'blank')
  if (any(flags %in% 'combined')) {
    diff = total - sum(parts, na.rm = TRUE)   # a combined zero is NA: its count sits elsewhere
    return(if (abs(diff) <= rounding_tolerance(length(parts))) 'ok' else 'combined')
  }
  if (any(flags %in% 'd')) return('suppressed')
  if (any(is.na(parts) & !explains_missing(flags))) return('blank')
  if (anyNA(parts)) return('footnote')   # e.g. [2] in Table 3.3's credit columns
  if (abs(total - sum(parts)) <= rounding_tolerance(length(parts))) 'ok' else 'fail'
}

# One comparison per group that carries at least two size classes. A group
# that has classes but no single total, or classes that do not tile, is
# reported ('no_total_row', 'not_partition') rather than dropped, so check
# coverage cannot shrink unseen on a new vintage.
skipped = function(n_classes, why) {
  data.frame(total = NA_real_, sum_classes = NA_real_, n_classes = n_classes, status = why)
}

check_group = function(g, axis) {
  lo = g[[paste0(axis, '_agi_lo')]]
  hi = g[[paste0(axis, '_agi_hi')]]
  is_class = !is.na(lo)
  if (sum(is_class) < 2) return(NULL)
  is_total = !is_class & (grepl(', total$', tolower(g[[paste0(axis, '_label')]])) |
                            tolower(g[[paste0(axis, '_label')]]) %in% c('all returns', 'total'))
  if (sum(is_total) != 1) return(skipped(sum(is_class), 'no_total_row'))
  if (!is_partition(lo[is_class], hi[is_class])) return(skipped(sum(is_class), 'not_partition'))
  parts = g$value[is_class]
  data.frame(total = g$value[is_total], sum_classes = sum(parts, na.rm = TRUE),
             n_classes = sum(is_class),
             status = additivity_status(g$value[is_total], g$flag[is_total], parts,
                                        g$flag[is_class]))
}

additivity = list()
for (fam in names(panels)) {
  d = panels[[fam]]
  d = d[!grepl(NONADDITIVE_REGEX, tolower(paste(d$col_group, d$col_label))) &
          !grepl('accumulated', tolower(d$section)), ]
  if (any(!is.na(d$row_agi_lo))) {
    # classes down the rows: one comparison per (year, panel, section, column)
    key = paste(d$tax_year, d$panel, d$section, d$col_seq, sep = '\r')
    res = lapply(split(d, key), function(g) {
      r = check_group(g, 'row')
      if (is.null(r)) return(NULL)
      cbind(family = fam, tax_year = g$tax_year[1], panel = g$panel[1],
            section = g$section[1], along = 'rows',
            label = paste(g$col_group[1], g$col_label[1]), r)
    })
    additivity[[paste(fam, 'rows')]] = do.call(rbind, res)
  }
  if (all(is.na(d$row_agi_lo))) {
    # category rows under a panel total (Table 1.6's age bands): one
    # comparison per (year, panel, column)
    key = paste(d$tax_year, d$panel, d$col_seq, sep = '\r')
    res = lapply(split(d, key), function(g) {
      is_total = grepl(', total$', tolower(g$row_label))
      if (sum(!is_total) < 2) return(NULL)
      parts = g$value[!is_total]
      r = if (sum(is_total) != 1) skipped(length(parts), 'no_total_row') else
        data.frame(total = g$value[is_total], sum_classes = sum(parts, na.rm = TRUE),
                   n_classes = length(parts),
                   status = additivity_status(g$value[is_total], g$flag[is_total], parts,
                                              g$flag[!is_total]))
      cbind(family = fam, tax_year = g$tax_year[1], panel = g$panel[1],
            section = g$section[1], along = 'category rows', label = g$col_label[1], r)
    })
    additivity[[paste(fam, 'categories')]] = do.call(rbind, res)
  }
  if (any(!is.na(d$col_agi_lo))) {
    # classes across the columns (Table 1.6): one comparison per row
    key = paste(d$tax_year, d$row_seq, sep = '\r')
    res = lapply(split(d, key), function(g) {
      r = check_group(g, 'col')
      if (is.null(r)) return(NULL)
      cbind(family = fam, tax_year = g$tax_year[1], panel = g$panel[1],
            section = g$section[1], along = 'cols', label = g$row_label[1], r)
    })
    additivity[[paste(fam, 'cols')]] = do.call(rbind, res)
  }
}
additivity = do.call(rbind, additivity)
utils::write.csv(additivity, file.path(aligned_dir, '_bysize_additivity.csv'),
                 row.names = FALSE, na = '')

#-----------------------
# Cross-table returns
#-----------------------

# Number of returns by AGI class in the all-returns panel of one table. A
# table with no stacked panels (Table 3.5) is all returns throughout.
returns_by_class = function(d) {
  fam = d$family[1]
  all_returns = if (all(is.na(d$panel))) TRUE else d$panel %in% 'All returns'
  if (fam == 'returns_marital_age') {
    r = d[all_returns & grepl('^all returns', tolower(d$row_label)) & !is.na(d$col_agi_lo), ]
    return(data.frame(tax_year = r$tax_year, agi_lo = r$col_agi_lo, agi_hi = r$col_agi_hi,
                      returns = r$value))
  }
  r = d[d$col_seq == 1 & d$col_label == 'Number of returns' & all_returns &
          !is.na(d$row_agi_lo) & !grepl('accumulated', tolower(d$section)), ]
  data.frame(tax_year = r$tax_year, agi_lo = r$row_agi_lo, agi_hi = r$row_agi_hi,
             returns = r$value)
}

# Two tables' classes for one year, each summed to the coarsest classes both
# can express: the intervals between the class bounds they share. Each
# table's classes must tile (-Inf, Inf), so every class nests in one shared
# interval. A class that cannot be summed (a combined zero, NA) makes its
# interval NA, which the check then fails.
sum_to_shared_classes = function(x, y, what) {
  for (z in list(x, y)) {
    if (!is_partition(z$agi_lo, z$agi_hi) || min(z$agi_lo) != -Inf || max(z$agi_hi) != Inf) {
      stop(what, ': AGI classes do not tile (-Inf, Inf)')
    }
  }
  breaks = sort(intersect(c(x$agi_lo, x$agi_hi), c(y$agi_lo, y$agi_hi)))
  n = length(breaks) - 1
  to_shared = function(z) {
    k = findInterval(z$agi_lo, breaks)
    stopifnot(all(z$agi_hi <= breaks[k + 1]))
    list(returns = vapply(seq_len(n), function(j) sum(z$returns[k == j]), numeric(1)),
         n_classes = tabulate(k, n))
  }
  sx = to_shared(x)
  sy = to_shared(y)
  data.frame(agi_lo = breaks[-(n + 1)], agi_hi = breaks[-1],
             returns = sx$returns, n_classes = sx$n_classes,
             returns_t14 = sy$returns, n_classes_t14 = sy$n_classes)
}

reference = returns_by_class(panels[['income_sources']])
crosstable = list()
uncovered = character(0)   # (table, year) pairs Table 1.4 covers but no comparison reached
for (fam in intersect(ALL_RETURNS_FAMILIES, names(panels))) {
  own = returns_by_class(panels[[fam]])
  for (yr in intersect(unique(panels[[fam]]$tax_year), unique(reference$tax_year))) {
    x = own[own$tax_year == yr, ]
    if (nrow(x) < 2) {
      uncovered = c(uncovered, sprintf('%s %d', fam, yr))
      next
    }
    crosstable[[paste(fam, yr)]] = cbind(
      family = fam, tax_year = yr,
      sum_to_shared_classes(x, reference[reference$tax_year == yr, ], sprintf('%s %d', fam, yr)))
  }
}
crosstable = do.call(rbind, crosstable)
crosstable$diff = crosstable$returns - crosstable$returns_t14
crosstable$status = ifelse(!is.na(crosstable$diff) &
                             abs(crosstable$diff) <= CROSSTABLE_TOLERANCE_PER_CLASS *
                               pmax(crosstable$n_classes, crosstable$n_classes_t14),
                           'ok', 'fail')

# Differences already traced to the published cells. Each entry pins the
# exact difference for one comparison; any other difference still fails.
known = utils::read.csv(file.path(script_dir, 'checks', 'bysize_known_differences.csv'),
                        stringsAsFactors = FALSE)
key = function(z) sprintf('%s %d %.0f %.0f %.0f', z$family, z$tax_year, z$agi_lo, z$agi_hi, z$diff)
crosstable$status[crosstable$status == 'fail' & key(crosstable) %in% key(known)] = 'known'
stale = known[!key(known) %in% key(crosstable), ]
if (nrow(stale) > 0) {
  stop('checks/bysize_known_differences.csv entries no comparison produced:\n',
       paste(key(stale), collapse = '\n'))
}
utils::write.csv(crosstable, file.path(aligned_dir, '_bysize_crosstable.csv'),
                 row.names = FALSE, na = '')

#-----------------------
# Report
#-----------------------

cat('\nAdditivity (total against the sum of its size classes):\n')
print(table(paste(additivity$family, additivity$along), additivity$status))
cat('\nCross-table returns by AGI class, against Table 1.4:\n')
print(table(crosstable$family, crosstable$status))

# Blank cells are unexplained missing values; groups that carry classes but
# could not be compared are listed, and gate only if a check was expected
unexplained = additivity$status %in% c('fail', 'blank')
if (any(additivity$status %in% c('no_total_row', 'not_partition'))) {
  cat('\nGroups with size classes that could not be compared:\n')
  print(table(paste(additivity$family, additivity$along),
              additivity$status)[, c('no_total_row', 'not_partition'), drop = FALSE])
}
if (length(uncovered) > 0) {
  cat('\nNo cross-table comparison for:', paste(uncovered, collapse = ', '), '\n')
}

n_fail = sum(unexplained) + sum(crosstable$status == 'fail') + length(uncovered)
if (n_fail > 0) {
  cat(sprintf('\n%d unexplained comparison(s) failed; see aligned/_bysize_*.csv\n', n_fail))
  quit(status = 1)
}
cat('\nAll comparisons pass or are explained by combined, suppressed or footnote cells.\n')
