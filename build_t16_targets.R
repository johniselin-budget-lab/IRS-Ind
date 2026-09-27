#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# build_t16_targets.R
#
# The merged Table 1.6 target view: number of returns by age x filing status
# x AGI class, with SOI's combined ("**") cells folded into target blocks, so
# a reweighting consumer (Tax-Data's TY2018-2023 filer refit) can target the
# table without reimplementing the disclosure rule.
#
# Why blocks. To prevent disclosure SOI blanks a small cell and adds its
# count to a neighbour, marking both "**". The neighbour can sit in the next
# age row (TY2018: 18-25 at $40-75k moved into 26-34) or the next AGI column,
# and one receiver can absorb several blanked cells, so a blanked cell has no
# single partner. The unit that survives is the connected set of "**" cells
# (adjacent across rows or columns) within one status block: its published
# values sum to its true total, and that sum is the target. Every other
# interior cell is a target on its own.
#
# The check that the rule is right: a row's published total ("All returns"
# column) less the sum of its published cells is zero unless counts left or
# entered the row through a block, and then the residuals of all rows a block
# group touches sum to zero. Same for columns against the block's total row.
# A group whose residuals do not cancel means a combination the adjacency
# rule misses. Such blocks are merged into one unit when the merged unit
# balances (TY2011 only, as of 2026-09-27); otherwise the run stops.
#
# Input:   <dest>/aligned/bysize_returns_marital_age.csv   (align_bysize.R)
# Output, under <dest>/aligned/:
#   targets_returns_marital_age.csv  one row per interior cell:
#       tax_year, panel, age, agi_lo, agi_hi, value, flag,
#       block_id, block_n_cells, block_value
#     panel     the published status block, lower case ('all returns',
#               'returns of single persons', ...); TY2011-2014 publish
#               surviving spouses separately, TY2015 on inside the joint block
#     age       the published age band ('under 26', '18 under 26', ...);
#               'all returns' carries 'under 18' separately, the status
#               blocks start at 'under 26'
#     value     as published; NA for a blanked (combined zero) cell
#     block_id  NA for a cell that is its own target; else the block, and
#               block_value its target (the sum of its published cells)
#   _t16_target_checks.csv  per (year, panel, axis, group): residuals of the
#       rows or columns a block group touches, and of untouched ones;
#       merged_blocks > 0 where blocks linked only through the margins were
#       merged into one unit (TY2011, below)
#
# Usage:
#   Rscript build_t16_targets.R --dest /path/to/store
#------------------------------------------------------------------------------

suppressMessages(library(data.table))

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

aligned_dir = file.path(dest, 'aligned')

# Every published count is rounded to a whole return, so a margin can miss
# the sum of n cells by up to about n/2.
rounding_tolerance = function(n_cells) n_cells

t16 = fread(file.path(aligned_dir, 'bysize_returns_marital_age.csv'), na.strings = '')
t16[, panel := tolower(panel)]
t16[, row_label := tolower(row_label)]
t16[, is_total_row := grepl(', total$', row_label)]
t16[, is_total_col := is.na(col_agi_lo)]
stopifnot(t16[is_total_col == TRUE, all(col_label == 'All returns')])

#-----------------------
# Blocks
#-----------------------

# Connected components of the combined cells of one (year, panel) grid, cells
# adjacent when they share a row and neighbouring columns or a column and
# neighbouring rows. Returns an integer component per combined cell.
components = function(ri, ci) {
  n = length(ri)
  comp = seq_len(n)
  find = function(k) { while (comp[k] != k) k = comp[k]; k }
  for (a in seq_len(n)) for (b in seq_len(n)) {
    if (b <= a) next
    if (abs(ri[a] - ri[b]) + abs(ci[a] - ci[b]) == 1) {
      ra = find(a); rb = find(b)
      if (ra != rb) comp[rb] = ra
    }
  }
  vapply(seq_len(n), find, integer(1))
}

# Residual checks on one axis: margin minus the sum of published cells, per
# row (or column). Rows touched by the same block group -- blocks linked
# through a shared row -- are pooled; untouched rows stand alone.
axis_checks = function(cells, margins, line_col, key) {
  res = merge(cells[, .(sum_cells = sum(value, na.rm = TRUE),   # a blanked cell is NA: its count sits in a receiver
                        n_cells = .N), by = line_col],
              margins, by = line_col)
  res[, residual := margin - sum_cells]
  # group the lines: two lines share a group when one block touches both
  touch = unique(cells[!is.na(block), c(line_col, 'block'), with = FALSE])
  res[, group := paste0('line ', get(line_col))]
  if (nrow(touch) > 0) {
    lines = sort(unique(touch[[line_col]]))
    g = setNames(seq_along(lines), lines)
    repeat {
      changed = FALSE
      for (b in unique(touch$block)) {
        # relabel every line already in a group this block touches
        old = unique(g[as.character(touch[block == b][[line_col]])])
        if (length(old) > 1) { g[g %in% old] = min(old); changed = TRUE }
      }
      if (!changed) break
    }
    hit = res[[line_col]] %in% lines
    res[hit, group := paste0('block group ', g[as.character(get(line_col))])]
  }
  out = res[, .(lines = paste(get(line_col), collapse = ' '), n_cells = sum(n_cells),
                margin_na = anyNA(margin), residual = sum(residual)), by = group]
  out[, status := fifelse(margin_na, 'margin_combined',
                  fifelse(abs(residual) <= rounding_tolerance(n_cells), 'ok', 'fail'))]
  cbind(key, out)
}

targets = list()
checks = list()
for (k in unique(t16[, .(tax_year, panel)])[, paste(tax_year, panel, sep = '\r')]) {
  y = as.integer(sub('\r.*', '', k))
  p = sub('.*\r', '', k)
  g = t16[tax_year == y & panel == p]
  cells = g[is_total_row == FALSE & is_total_col == FALSE,
            .(row_seq, col_seq, age = row_label, agi_lo = col_agi_lo, agi_hi = col_agi_hi,
              value, flag)]
  cells[, ri := match(row_seq, sort(unique(row_seq)))]
  cells[, ci := match(col_seq, sort(unique(col_seq)))]
  cells[, block := NA_integer_]
  comb = which(cells$flag %in% 'combined')
  if (length(comb) > 0) cells[comb, block := components(ri, ci)]
  if (any(is.na(cells$value) & !(cells$flag %in% 'combined'))) {
    stop(y, ' ', p, ': a missing interior cell that is not combined')
  }

  key = data.table(tax_year = y, panel = p)
  row_margins = g[is_total_row == FALSE & is_total_col == TRUE, .(row_seq, margin = value)]
  col_margins = g[is_total_row == TRUE & is_total_col == FALSE, .(col_seq, margin = value)]
  both_axes = function() rbind(
    cbind(axis = 'rows', axis_checks(cells, row_margins, 'row_seq', key)),
    cbind(axis = 'cols', axis_checks(cells, col_margins, 'col_seq', key)))
  chk = both_axes()
  # Blocks can also be linked through a receiver SOI left unflagged: TY2011's
  # heads-of-household block blanks a whole $500k column and puts the counts
  # into the flagged $100k cells two columns over, so neither group balances
  # alone and the pair does (-13,848 + 13,138 + 707 = -3). Blocks in failing
  # groups of one grid become one target unit, and the checks run again.
  if (any(chk$status == 'fail')) {
    bad = chk[status == 'fail']
    lines_of = function(ax) as.integer(unlist(strsplit(bad[axis == ax]$lines, ' ')))
    merged = unique(cells[(row_seq %in% lines_of('rows') | col_seq %in% lines_of('cols')) &
                            !is.na(block)]$block)
    cells[block %in% merged, block := min(merged)]
    chk = both_axes()
    chk[, merged_blocks := length(merged)]
  }
  checks[[length(checks) + 1]] = chk

  cells[, block_id := fifelse(is.na(block), NA_character_, sprintf('%d|%s|b%d', y, p, block))]
  cells[, `:=`(block_n_cells = fifelse(is.na(block), NA_integer_, .N),
               block_value   = fifelse(is.na(block), NA_real_, sum(value, na.rm = TRUE))),
        by = block_id]
  targets[[length(targets) + 1]] = cbind(key, cells[order(ri, ci),
    .(age, agi_lo, agi_hi, value, flag, block_id, block_n_cells, block_value)])
}
targets = rbindlist(targets)
checks = rbindlist(checks, fill = TRUE)

fwrite(targets, file.path(aligned_dir, 'targets_returns_marital_age.csv'), na = '')
fwrite(checks, file.path(aligned_dir, '_t16_target_checks.csv'), na = '')

#-----------------------
# Report
#-----------------------

blocks = unique(targets[!is.na(block_id), .(tax_year, block_id, block_n_cells)])
cat(sprintf('Table 1.6 targets: %d cells, %d years; %d blocks holding %d combined cells\n',
            nrow(targets), uniqueN(targets$tax_year), nrow(blocks), sum(blocks$block_n_cells)))
print(blocks[, .(blocks = .N, cells = sum(block_n_cells), largest = max(block_n_cells)),
             by = tax_year][order(tax_year)])
cat('\nMargin checks (rows: the "All returns" column; cols: the block total row):\n')
print(table(paste(checks$axis, fifelse(grepl('^block', checks$group), 'block groups',
                                       'untouched lines')), checks$status))
n_fail = sum(checks$status == 'fail')
if (n_fail > 0) {
  cat(sprintf('\n%d margin check(s) failed; see aligned/_t16_target_checks.csv\n', n_fail))
  quit(status = 1)
}
cat('\nEvery margin balances once combined cells are read as blocks.\n')
