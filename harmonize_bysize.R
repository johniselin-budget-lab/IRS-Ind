#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# harmonize_bysize.R
#
# The harmonized layer of notes/bysize_panels_plan.md: one panel per Pub 1304
# by-size table, built from the aligned panels (align_bysize.R) with every
# concept change resolved.
#
#   condense / expand  (checks/bysize_concepts.csv, and AGI classes
#       automatically): the one category is a consistent total in every year
#       -- published where published, the sum of its components where not --
#       and the components are kept, NA in the years they are not published.
#   other: kept as published and flagged. Every series published in only
#       some years of its table is flagged automatically; the map adds the
#       reason, and can flag a series that runs every year but changes
#       meaning (Table 3.5's brackets).
#
# A derived number of returns is summed only across mutually exclusive
# components (filing statuses, AGI classes). Otherwise it is NA with bounds
# [largest component, sum of components], and, on the all-returns total row,
# the national count from Pub 4801 where the concept map names the line
# (Schedule E line 32 for partnership + S corporation). No overlap is
# modelled.
#
# Output, under <dest>/aligned/:
#   panel_{family}.csv  tax_year, table, family, panel, section, row, agi_lo,
#       agi_hi, series, measure, value, flag, derived, change, change_note,
#       agi_change, agi_note, bound_lo, bound_hi
#     panel   the stacked block, lower case; for tables without stacked
#             blocks their sections are promoted to it (3.1's computation
#             types, 3.2's status blocks), else 'all returns'
#     row     'total' for a total row, the category for a non-class row
#             (1.6's age bands), NA for an AGI-class row
#     agi_lo/agi_hi  the class, dollars, [lo, hi), from whichever axis
#     series, measure  the aligned item split into what and how: measure is
#             'returns', 'amount' or 'value' (a single-measure column)
#     derived TRUE for a number built here rather than published
#     change  NA, condense_total, condense_component, expand_total,
#             expand_component, other -- the series (or panel) concept change;
#             change_note says what and why
#     agi_change  NA, expand_total, expand_component -- the AGI-class role,
#             kept apart because a row can be both (TY2011-2012's $200k-$250k
#             wages): the consistent classes are agi_change != 'expand_component'
#   _panel_seams.csv    per concept-map entry, the all-returns total of the
#       consistent series and the sum of its components, every year
#   _panel_changes.csv  every changed or flagged series and AGI class: its
#       role, the years it is published, derived and NA-filled, and the note
#
# Usage:
#   Rscript harmonize_bysize.R --dest /path/to/store
#
# Stops if a published cell does not come through exactly once and unchanged,
# or if a national anchor disagrees with a published count where both exist
# (beyond last-digit rounding).
#------------------------------------------------------------------------------

suppressMessages(library(data.table))

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

source(file.path(script_dir, 'alignment_helpers.R'))

aligned_dir = file.path(dest, 'aligned')

CONCEPTS = fread(file.path(script_dir, 'checks', 'bysize_concepts.csv'), na.strings = '',
                 strip.white = FALSE)

# Net income less net loss, derived for each of these bases before the
# concept map applies (Table 1.4's partnership and S corporation, decision 1)
NET_BASES = list(income_sources = c('partnership and s corporation', 'partnership',
                                    's corporation'))

# A national anchor and a published count it overlaps agree to within this:
# Table 1.4's partnership + S corporation count is two rounded cells (net
# income plus net loss returns) against Pub 4801's one, so the last digit
# can differ (TY2011, 2014, 2015 differ by 1; the other ten years are equal)
ANCHOR_TOLERANCE = 2

# Section and panel labels that differ in form only (see national_bysize.md)
DIMENSION_SYNONYMS = data.table(
  family = 'tax_pct_of_agi', from = 'all returns', to = 'all returns with total income tax',
  reason = 'TY2011-2015 label of the same universe: its total equals Table 3.3 returns with total income tax (99,040,729 in TY2015)')

#-----------------------
# Helpers
#-----------------------

years_text = function(y) {
  y = sort(unique(y))
  runs = split(y, cumsum(c(1, diff(y) != 1)))
  paste(vapply(runs, function(r) if (length(r) == 1) as.character(r) else
    paste0(r[1], '-', r[length(r)]), character(1)), collapse = ', ')
}

# The flag a derived value inherits: why a missing component is missing,
# else 'caution' if any component carries it
derived_flag = function(values, flags) {
  miss = flags[is.na(values)]
  if (length(miss)) return(if (all(is.na(miss))) 'blank' else miss[!is.na(miss)][1])
  if (any(flags %in% 'caution')) 'caution' else NA_character_
}

# Does a series fall under a concept-map prefix? Returns the suffix ('' or
# ' > rest') or NA.
prefix_suffix = function(series, prefix) {
  ifelse(series == prefix, '',
         ifelse(startsWith(series, paste0(prefix, ' > ')), substring(series, nchar(prefix) + 1),
                NA_character_))
}

#-----------------------
# Normalize one table
#-----------------------

normalize = function(a) {
  d = as.data.table(a)
  d[, cell_id := paste(tax_year, row_seq, col_seq)]
  lower = function(x) trimws(gsub('\\s+', ' ', tolower(x)))
  d[, panel := lower(panel)]
  d[, section := lower(section)]
  syn = DIMENSION_SYNONYMS[family == d$family[1]]
  for (i in seq_len(nrow(syn))) {
    d[panel %in% syn$from[i], panel := syn$to[i]]
    d[section %in% syn$from[i], section := syn$to[i]]
  }
  if (all(is.na(d$panel))) {
    d[, panel := fifelse(is.na(section), 'all returns', section)]
    d[, section := NA_character_]
  }
  for (v in c('row_agi_lo', 'row_agi_hi', 'col_agi_lo', 'col_agi_hi')) set(d, j = v, value = as.numeric(d[[v]]))
  is_col_class = !is.na(d$col_agi_lo)
  d[, agi_lo := fifelse(is_col_class, col_agi_lo, row_agi_lo)]
  d[, agi_hi := fifelse(is_col_class, col_agi_hi, row_agi_hi)]
  rl = sub(',? total$', '', lower(d$row_label))
  d[, row := fifelse(!is.na(row_agi_lo), NA_character_,
                     fifelse(rl %in% c('total', 'all returns') | rl == panel, 'total', rl))]
  if (any(is_col_class)) {
    # Table 1.6: the columns are AGI classes (and their total), one measure
    d[, `:=`(series = 'number of returns', measure = 'returns')]
  } else {
    d[, measure := fifelse(grepl('(^| > )number of returns$', item), 'returns',
                           fifelse(grepl('(^| > )amount$', item), 'amount', 'value'))]
    d[, series := sub('(^| > )(number of returns|amount)$', '', item)]
    d[series == '', series := 'all']
  }
  d[, `:=`(derived = FALSE, change = NA_character_, change_note = NA_character_,
           agi_change = NA_character_, agi_note = NA_character_,
           bound_lo = NA_real_, bound_hi = NA_real_)]
  d[, .(cell_id, tax_year, table, family, panel, section, row, agi_lo, agi_hi, series,
        measure, value = as.numeric(value), flag, derived, change, change_note,
        agi_change, agi_note, bound_lo, bound_hi)]
}

# Cells within a year: everything but the series and measure
CELL = c('tax_year', 'panel', 'section', 'row', 'agi_lo', 'agi_hi')

#-----------------------
# Net income less loss
#-----------------------

add_net_items = function(d, bases) {
  out = list()
  for (b in bases) {
    inc = d[series == paste(b, '> net income')]
    los = d[series == paste(b, '> net loss')]
    if (nrow(inc) == 0) next
    x = merge(inc, los, by = c(CELL, 'measure'), suffixes = c('', '.loss'))
    if (nrow(x) != nrow(inc)) stop(b, ': net income and net loss cells do not pair up')
    x[, flag := mapply(function(v1, v2, f1, f2) derived_flag(c(v1, v2), c(f1, f2)),
                       value, value.loss, flag, flag.loss)]
    # a return has either a net income or a net loss from a base, so return
    # counts add; amounts are published positive, so the net is the difference
    x[, value := fifelse(measure == 'returns', value + value.loss, value - value.loss)]
    x[, `:=`(series = paste(b, '> net income less loss'), derived = TRUE, cell_id = NA_character_,
             change_note = 'net income less net loss, derived')]
    out[[b]] = x[, names(d), with = FALSE]
  }
  rbind(d, rbindlist(out))
}

#-----------------------
# Concept-map entries
#-----------------------

anchor_values = function(spec) {
  li = fread(file.path(aligned_dir, 'line_items.csv'))
  parts = strsplit(spec, '\\|')[[1]]
  a = li[publication == 4801 & universe == 'all returns' & form == parts[1] & line == parts[2] &
           measure == 'returns', .(tax_year, anchor = as.numeric(value))]
  if (nrow(a) == 0 || anyDuplicated(a$tax_year)) stop('anchor ', spec, ': not one value per year')
  a
}

# Apply one condense/expand entry. axis 'series': totals and components are
# series prefixes, and the consistent series is e$series + the suffix (1.2's
# eight joint-filer items share one entry); axis 'panel': they are panel
# names. Returns list(d, seam).
apply_entry = function(d, e) {
  kind = e$kind
  totals = strsplit(e$totals, '\\|')[[1]]
  comps  = strsplit(e$components, '\\|')[[1]]
  on = e$axis
  target = d[[on]]
  role = rep(NA_character_, nrow(d)); suffix = role; comp = role
  for (p in c(totals, comps)) {
    sfx = if (on == 'series') prefix_suffix(target, p) else ifelse(target == p, '', NA_character_)
    hit = !is.na(sfx) & is.na(role)
    role[hit] = if (p %in% totals) 'total' else 'component'
    suffix[hit] = sfx[hit]
    if (!(p %in% totals)) comp[hit] = p
  }
  d[, `:=`(.role = role, .suffix = suffix, .comp = comp)]
  if (!any(role %in% 'total') || !any(role %in% 'component')) {
    stop(e$family, ' / ', e$series, ': concept-map entry matches no total or no component')
  }
  consistent = function(sfx) if (on == 'series') paste0(e$series, sfx) else e$series
  d[.role == 'total', (on) := consistent(.suffix)]
  d[.role == 'total', `:=`(change = paste0(kind, '_total'), change_note = e$note)]
  d[.role == 'component', `:=`(change = paste0(kind, '_component'), change_note = e$note)]

  # a cell of the consistent category: the cell less the axis, plus the
  # suffix (axis series) or the series (axis panel)
  sk  = if (on == 'series') c('measure', '.suffix') else c('series', 'measure')
  key = unique(c(setdiff(CELL, on), sk))
  tot = d[.role == 'total']
  cmp = d[.role == 'component']
  # which components ever publish each (suffix or series, measure); the rest
  # are structurally absent there (1.4A: no adjustments without Form 8949)
  struct = unique(cmp[, c(sk, '.comp'), with = FALSE])
  exclusive = isTRUE(as.logical(e$exclusive))

  # the consistent total where only components are published
  need = cmp[!unique(tot[, key, with = FALSE]), on = key]
  derived = if (nrow(need) == 0) NULL else need[, {
    expected = struct[as.data.table(.BY)[, sk, with = FALSE], on = sk]$.comp
    got = .SD[match(expected, .comp)]
    complete = !anyNA(got$.comp)
    additive = is_additive(if (on == 'series') consistent(.BY$.suffix) else .BY$series)
    v = got$value
    val = NA_real_; lo = NA_real_; hi = NA_real_; note = e$note
    if (!complete) {
      note = paste0(note, '; not derivable: a component is missing this year')
    } else if (!additive) {
      note = paste0(note, '; not additive, not derived')
    } else if (.BY$measure == 'returns' && !exclusive) {
      if (!anyNA(v)) { lo = max(v); hi = sum(v) }
      note = paste0(note, '; a return can fall in more than one component, so the count is ',
                    'NA, with bounds [largest component, sum]')
    } else if (!anyNA(v)) {
      val = sum(v)
    }
    list(value = val, flag = if (complete) derived_flag(v, got$flag) else 'blank',
         bound_lo = lo, bound_hi = hi, change_note = note)
  }, by = key]
  if (!is.null(derived)) {
    derived[, (on) := consistent(if (on == 'series') .suffix else '')]
    derived[, `:=`(table = d$table[1], family = d$family[1], cell_id = NA_character_,
                   derived = TRUE, change = paste0(kind, '_total'), .role = 'total',
                   .comp = NA_character_)]
    if (on == 'panel') derived[, .suffix := '']
  }

  # the components, NA in the years only the total is published
  filler = merge(unique(tot[, key, with = FALSE]), struct, by = sk, allow.cartesian = TRUE)
  filler = filler[!unique(cmp[, c(key, '.comp'), with = FALSE]), on = c(key, '.comp')]
  if (nrow(filler)) {
    filler[, (on) := if (on == 'series') paste0(.comp, .suffix) else .comp]
    filler[, `:=`(table = d$table[1], family = d$family[1], cell_id = NA_character_,
                  value = NA_real_, flag = NA_character_, derived = FALSE,
                  change = paste0(kind, '_component'),
                  change_note = paste0(e$note, '; not published this year: included in ', e$series),
                  bound_lo = NA_real_, bound_hi = NA_real_, .role = 'component')]
    if (on == 'panel') filler[, .suffix := '']
  }
  d = rbind(d, derived, filler, fill = TRUE)

  # the national count on the all-returns total row
  is_top = function(x) x$.role %in% 'total' & x$row %in% 'total' & is.na(x$agi_lo) &
    x$measure == 'returns' & x$.suffix %in% '' & (on == 'panel' | x$panel == 'all returns')
  if (!is.na(e$anchor)) {
    a = anchor_values(e$anchor)
    chk = merge(d[is_top(d) & !is.na(value), .(tax_year, value)], a, by = 'tax_year')
    if (nrow(chk) == 0) stop(e$series, ': anchor ', e$anchor, ' overlaps no published count')
    bad = chk[abs(value - anchor) > ANCHOR_TOLERANCE]
    if (nrow(bad)) stop(e$series, ': anchor ', e$anchor, ' disagrees with the published count in ',
                        years_text(bad$tax_year))
    d[a, on = 'tax_year', .anchor := i.anchor]
    d[is_top(d) & derived == TRUE & is.na(value) & !is.na(.anchor),
      `:=`(value = .anchor, bound_lo = .anchor, bound_hi = .anchor,
           change_note = paste0(change_note, '; the national count is Pub 4801 ', e$anchor,
                                ', which matches the published total (within rounding) in TY',
                                years_text(chk$tax_year)))]
    d[, .anchor := NULL]
  }

  # seam: the top cell of the consistent category and of its components
  top_rows = d[!is.na(.role) & row %in% 'total' & is.na(agi_lo) &
                 (on == 'panel' | panel == 'all returns')]
  top_rows[, item := if (on == 'series') .suffix else series]
  seam = top_rows[, .(value = if (anyNA(value)) NA_real_ else sum(value),
                      bound_lo = if (all(is.na(bound_lo))) NA_real_ else sum(bound_lo),
                      bound_hi = if (all(is.na(bound_hi))) NA_real_ else sum(bound_hi),
                      derived = any(derived), n = .N),
                  by = .(item, measure, tax_year, role = .role)]
  seam = dcast(seam, item + measure + tax_year ~ role,
               value.var = c('value', 'derived', 'n', 'bound_lo', 'bound_hi'))
  seam[, `:=`(family = e$family, entry = e$series, kind = kind)]
  d[, c('.role', '.suffix', '.comp') := NULL]
  list(d = d, seam = seam)
}

#-----------------------
# AGI classes
#-----------------------

# Within each (panel, section), the class bounds published in every year that
# block exists are the consistent classes; a finer split published in some
# years is an expansion. Blocks whose classes do not tile (1.1's accumulated
# sections) pass through.
harmonize_classes = function(d) {
  blocks = unique(d[!is.na(agi_lo), .(panel, section)])
  added = list()
  for (b in seq_len(nrow(blocks))) {
    in_block = d$panel %in% blocks$panel[b] & d$section %in% blocks$section[b] & !is.na(d$agi_lo)
    per_year = unique(d[in_block, .(tax_year, agi_lo, agi_hi)])
    tiles = per_year[, .(ok = is_partition(agi_lo, agi_hi) && min(agi_lo) == -Inf &&
                           max(agi_hi) == Inf), by = tax_year]
    if (!all(tiles$ok)) next
    n_years = uniqueN(per_year$tax_year)
    brk = unique(per_year[, .(b = c(agi_lo, agi_hi)), by = tax_year])
    common = sort(brk[, .N, by = b][N == n_years]$b)
    fine_years = per_year[!(agi_lo %in% common & agi_hi %in% common), unique(tax_year)]
    if (length(fine_years) == 0) next
    cons = data.table(k = seq_len(length(common) - 1), lo = head(common, -1), hi = common[-1])
    note = function(x) paste0('AGI class split more finely in TY', years_text(fine_years), x)
    d[, .k := findInterval(agi_lo, common)]
    d[, .cons := in_block & paste(agi_lo, agi_hi) %in% paste(cons$lo, cons$hi)]
    split_k = unique(d[in_block & !.cons, .k])
    # the finer classes are components; a consistent class that is split in
    # some years is the total
    d[in_block & !.cons, `:=`(agi_change = 'expand_component', agi_note = note(''))]
    d[in_block & .cons & .k %in% split_k, `:=`(agi_change = 'expand_total', agi_note = note(''))]
    dims = c('tax_year', 'table', 'family', 'panel', 'section', 'row', 'series', 'measure', '.k')
    # derived consistent classes where only the split is published
    have = unique(d[in_block & .cons, dims, with = FALSE])
    der = d[in_block & !.cons][!have, on = dims][, .(
      value = if (!is_additive(series[1]) || anyNA(value)) NA_real_ else sum(value),
      flag = derived_flag(value, flag),
      bound_lo = if (anyNA(bound_lo)) NA_real_ else sum(bound_lo),
      bound_hi = if (anyNA(bound_hi)) NA_real_ else sum(bound_hi),
      change = change[1], change_note = change_note[1]), by = dims]
    der[, `:=`(agi_lo = cons$lo[.k], agi_hi = cons$hi[.k], cell_id = NA_character_,
               derived = TRUE, agi_change = 'expand_total',
               agi_note = note(': the consistent class, derived as the sum of the split'))]
    # the finer classes, NA in the years only the consistent class is published
    fine_cls = unique(d[in_block & !.cons, .(.k, agi_lo, agi_hi)])
    fill = merge(have[.k %in% split_k], fine_cls, by = '.k', allow.cartesian = TRUE)
    fill = fill[!d[in_block & !.cons], on = c(setdiff(dims, '.k'), 'agi_lo', 'agi_hi')]
    fill = merge(fill, unique(d[in_block & .cons, c(dims, 'change', 'change_note'), with = FALSE]),
                 by = dims)
    fill[, `:=`(cell_id = NA_character_, value = NA_real_, flag = NA_character_, derived = FALSE,
                agi_change = 'expand_component', agi_note = note(': not published this year'),
                bound_lo = NA_real_, bound_hi = NA_real_)]
    added[[length(added) + 1]] = rbind(der, fill, fill = TRUE)
    d[, c('.k', '.cons') := NULL]
  }
  if (length(added)) {
    add = rbindlist(added, use.names = TRUE, fill = TRUE)
    add[, .k := NULL]
    d = rbind(d, add[, names(d), with = FALSE])
  }
  d
}

#-----------------------
# Other
#-----------------------

flag_other = function(d, family_years) {
  entries = CONCEPTS[family == d$family[1] & kind == 'other']
  # published in only some years of the table
  pres = d[derived == FALSE & !is.na(cell_id), .(yrs = list(sort(unique(tax_year)))),
           by = .(panel, section, series, measure)]
  pres[, partial := lengths(yrs) < length(family_years)]
  pres[, note := vapply(yrs, function(y) paste0('published TY', years_text(y)), character(1))]
  d[pres[partial == TRUE], on = .(panel, section, series, measure),
    `:=`(change = fcoalesce(change, 'other'),
         change_note = fifelse(is.na(change_note), i.note, paste0(change_note, '; ', i.note)))]
  for (i in seq_len(nrow(entries))) {
    target = if (entries$axis[i] == 'panel') d$panel else d$series
    hit = grepl(entries$series[i], target, perl = TRUE)
    if (!any(hit)) stop(d$family[1], ': "other" entry matches nothing: ', entries$series[i])
    d[hit, `:=`(change = fcoalesce(change, 'other'),
                change_note = fifelse(is.na(change_note), entries$note[i],
                                      paste0(change_note, '; ', entries$note[i])))]
  }
  d
}

#-----------------------
# Build
#-----------------------

files = sort(list.files(aligned_dir, pattern = '^bysize_[a-z0-9_]+\\.csv$'))
if (length(files) == 0) stop('no aligned by-size panels under ', aligned_dir, '; run align_bysize.R')
unknown = setdiff(CONCEPTS$family, sub('^bysize_(.*)\\.csv$', '\\1', files))
if (length(unknown)) stop('concept map names unknown tables: ', paste(unknown, collapse = ', '))

seams = list()
changes = list()
for (f in files) {
  a = fread(file.path(aligned_dir, f), na.strings = '')
  fam = a$family[1]
  d = normalize(a)
  family_years = sort(unique(d$tax_year))
  if (!is.null(NET_BASES[[fam]])) d = add_net_items(d, NET_BASES[[fam]])
  for (i in which(CONCEPTS$family == fam & CONCEPTS$kind != 'other')) {
    r = apply_entry(d, CONCEPTS[i])
    d = r$d
    seams[[length(seams) + 1]] = r$seam
  }
  d = harmonize_classes(d)
  d = flag_other(d, family_years)

  # every published cell exactly once, unchanged
  pub = d[!is.na(cell_id)]
  if (anyDuplicated(pub$cell_id) || nrow(pub) != nrow(a)) stop(fam, ': published cells lost or duplicated')
  a[, cell_id := paste(tax_year, row_seq, col_seq)]
  chk = merge(pub[, .(cell_id, value, flag)], a[, .(cell_id, v0 = as.numeric(value), f0 = flag)],
              by = 'cell_id')
  if (!isTRUE(all.equal(chk$value, chk$v0)) || !identical(chk$flag, chk$f0)) {
    stop(fam, ': a published value or flag changed')
  }
  key = c(CELL, 'series', 'measure')
  if (anyDuplicated(d[, key, with = FALSE])) {
    dup = d[duplicated(d[, key, with = FALSE])][1]
    stop(fam, ': two rows for one cell, e.g. ', paste(unlist(dup[, key, with = FALSE]), collapse = ' / '))
  }

  setorderv(d, c('tax_year', 'panel', 'section', 'row', 'agi_lo', 'series', 'measure'), na.last = FALSE)
  out = d[, .(tax_year, table, family, panel, section, row, agi_lo, agi_hi, series, measure,
              value, flag, derived, change, change_note, agi_change, agi_note, bound_lo, bound_hi)]
  fwrite(out, file.path(aligned_dir, sprintf('panel_%s.csv', fam)), na = '')
  yrs = function(y) if (length(y)) years_text(y) else NA_character_
  catalog = function(x, by) x[, .(published = yrs(tax_year[!is.na(cell_id)]),
                                   derived = yrs(tax_year[derived]),
                                   na_filler = yrs(tax_year[is.na(cell_id) & !derived]),
                                   note = sub(';.*', '', note[1])), by = by]
  changes[[fam]] = rbind(
    catalog(d[!is.na(change), .(family, table, axis = 'series', series, measure, change,
                                note = change_note, tax_year, cell_id, derived)],
            c('family', 'table', 'axis', 'series', 'measure', 'change')),
    catalog(d[!is.na(agi_change), .(family, table, axis = 'agi class',
                                    series = paste0('[', agi_lo, ', ', agi_hi, ')'),
                                    measure = NA_character_, change = agi_change, note = agi_note,
                                    tax_year, cell_id, derived)],
            c('family', 'table', 'axis', 'series', 'measure', 'change')))
  cat(sprintf('%-24s Table %-5s %8d rows: %6d published cells, %5d derived, %5d NA fillers, %5d flagged other\n',
              fam, d$table[1], nrow(d), nrow(pub), sum(d$derived),
              sum(is.na(d$cell_id) & !d$derived), sum(d$change %in% 'other')))
}

seams = rbindlist(seams, fill = TRUE)
fwrite(seams, file.path(aligned_dir, '_panel_seams.csv'), na = '')
fwrite(rbindlist(changes), file.path(aligned_dir, '_panel_changes.csv'), na = '')
cat('\nWrote panel_*.csv, _panel_seams.csv and _panel_changes.csv to', aligned_dir, '\n')
