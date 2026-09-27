#------------------------------------------------------------------------------
# alignment_helpers.R
#
# Parsing machinery for the Pub 1304 by-size tables (align_bysize.R). Ported
# from the IRS-Corp engine of the same name (notes/alignment_plan.md): the
# column-number-row locator, label normalization, header stacking over merged
# cells and the spanner hierarchy are that engine's, trimmed to what the
# individual tables need. Two things differ, and both come from how Pub 1304
# is published:
#
#   * Cells are read through read_xls_cells.py, not readxl. SOI's disclosure
#     marks ("*" caution, "**" combined) are Excel NUMBER FORMATS, so readxl
#     returns the bare number and a combined cell arrives as a true 0. The
#     python reader carries the mark as a per-cell flag.
#   * Panels are stacked by TOTAL ROWS that carry data ("Taxable returns,
#     total", "Returns of single persons, total"), not by label-only section
#     rows, so a row ending ", total" opens a panel.
#
# Sourced with `helper_dir` pointing at this repo (for read_xls_cells.py).
#------------------------------------------------------------------------------

#-----------------------
# Read a sheet
#-----------------------

# The first sheet as list(m, flag, merges): m and flag are character matrices
# in absolute sheet coordinates ('' where empty), merges a data.frame of
# 1-based inclusive ranges.
read_bysize_sheet = function(path, helper_dir) {
  lines = suppressWarnings(system2(
    'python3', c(shQuote(file.path(helper_dir, 'read_xls_cells.py')), shQuote(path)),
    stdout = TRUE, stderr = TRUE))
  status = attr(lines, 'status')
  if (!is.null(status) && status != 0) {
    stop('read_xls_cells.py failed on ', path, ':\n', paste(lines, collapse = '\n'))
  }
  recs = utils::read.csv(text = paste(lines, collapse = '\n'), header = FALSE,
                         colClasses = 'character', col.names = paste0('V', 1:5),
                         fill = TRUE)
  cells = recs[recs$V1 == 'C', ]
  mg    = recs[recs$V1 == 'M', ]
  r = as.integer(cells$V2)
  k = as.integer(cells$V3)
  m    = matrix('', max(r), max(k))
  flag = matrix('', max(r), max(k))
  m[cbind(r, k)]    = trimws(cells$V5)
  flag[cbind(r, k)] = cells$V4
  merges = data.frame(first_row = as.integer(mg$V2), last_row = as.integer(mg$V3),
                      first_col = as.integer(mg$V4), last_col = as.integer(mg$V5))
  list(m = m, flag = flag, merges = merges)
}

#--------------------------------
# Locate the column-number row
#--------------------------------

# A strictly-increasing integer run, allowing the occasional skipped number.
well_formed_run = function(run) {
  all(run == round(run)) && max(run) < 1000 && all(diff(run) >= 1) &&
    mean(diff(run) == 1) >= 0.9
}

# "(1) (2) ..." in accounting format arrives as -1 -2 ..., so absolute values
# are the fallback (Table 1.2 numbers its columns that way).
numrow_run = function(v) {
  if (well_formed_run(v)) return(v)
  a = abs(v)
  if (well_formed_run(a)) return(a)
  NULL
}

# SOI marks data columns with a row of consecutive numbers under the header
# block. Old vintages (Table 2.3 through TY2004) print further COLUMNS of the
# same rows as a second block below the first, with its own header and a
# number row that continues the first's numbering (1..8, then 9..16). A
# continuation row holds nothing but the run. Returns a list of list(row,
# cols), one per block, in sheet order; empty if the sheet has none.
find_numrows = function(m, max_scan = 30) {
  as_run = function(i) {
    v = suppressWarnings(as.numeric(gsub('^\\((.*)\\)$', '\\1', m[i, ])))
    idx = unname(which(!is.na(v)))
    if (length(idx) < 3) return(NULL)
    run = numrow_run(v[idx])
    if (is.null(run)) NULL else list(row = i, cols = idx, vals = run)
  }
  first = NULL
  for (i in seq_len(min(max_scan, nrow(m)))) {
    r = as_run(i)
    if (!is.null(r) && length(r$cols) >= 5 && r$vals[1] == 1) { first = r; break }
  }
  if (is.null(first)) return(list())
  blocks = list(first)
  for (i in seq(first$row + 1, length.out = max(0, nrow(m) - first$row))) {
    if (!identical(unname(which(m[i, ] != '')), as_run(i)$cols)) next
    r = as_run(i)
    if (r$vals[1] == max(blocks[[length(blocks)]]$vals) + 1) blocks[[length(blocks) + 1]] = r
  }
  blocks
}

#----------------------
# Labels and values
#----------------------

normalize_label = function(x) {
  x = gsub('\\[[0-9]+(\\s*,\\s*[0-9]+)*\\]', '', x)   # footnote refs "[1]", "[1,2]"
  x = gsub('[.*:]+$', '', trimws(x))                   # dot leaders, asterisks
  trimws(gsub('\\s+', ' ', x))
}

# One cell -> list(value, flag). Money in $ thousands as published.
#   combined  "**": combined with another cell to prevent disclosure. A zero
#             under this mark is not a zero -- the count sits in a neighbour --
#             so it becomes NA; a nonzero one is the receiving cell and keeps
#             its value.
#   caution   "*": sampling variability; value kept.
#   blank     empty cell inside the data block.
#   [n]       footnote-only cell (e.g. a percent SOI does not compute).
#   d         suppressed ("d" printed in place of the value).
#   '-'       a printed dash: none reported (0).
clean_value = function(x, fmt_flag) {
  if (x == '') return(list(value = NA_real_, flag = 'blank'))
  if (tolower(x) == 'd') return(list(value = NA_real_, flag = 'd'))
  if (grepl('^\\[[0-9]+\\]$', x)) return(list(value = NA_real_, flag = x))
  if (grepl('^-+$', x)) return(list(value = 0, flag = '-'))
  raw = gsub(',', '', trimws(gsub('\\[[0-9]+\\]', '', x)))
  flag = if (fmt_flag == '') NA_character_ else fmt_flag
  if (startsWith(raw, '*')) {                  # a text-typed mark, belt and braces
    flag = if (startsWith(raw, '**')) 'combined' else 'caution'
    raw  = trimws(sub('^\\*+', '', raw))
    if (raw == '') return(list(value = NA_real_, flag = flag))
  }
  val = suppressWarnings(as.numeric(raw))
  if (is.na(val)) stop('unparseable value: "', x, '"')
  if (identical(flag, 'combined') && val == 0) val = NA_real_
  list(value = val, flag = flag)
}

#-------------------------------------------------
# Header stacking and the spanner hierarchy
#-------------------------------------------------

# Blank every cell a merged range covers except its anchor.
blank_covered = function(m, merges) {
  for (r in seq_len(nrow(merges))) {
    rows = merges$first_row[r]:merges$last_row[r]
    cols = merges$first_col[r]:merges$last_col[r]
    rows = rows[rows <= nrow(m)]
    cols = cols[cols <= ncol(m)]
    if (length(rows) == 0 || length(cols) == 0) next
    anchor = m[rows[1], cols[1]]
    m[rows, cols] = ''
    m[rows[1], cols[1]] = anchor
  }
  m
}

# Merged header ranges spanning >= 2 data columns: these are spanners (item
# names over a Number/Amount pair, filing-status groups in 1.2, the "Size of
# adjusted gross income" band over all of 1.6), not the column's own label.
header_spanners = function(m, hdr_rows, cols, merges) {
  mg = merges[merges$first_row %in% hdr_rows & merges$first_col <= ncol(m), ,
              drop = FALSE]
  if (nrow(mg) == 0) return(cbind(mg, text = character(0), span = integer(0)))
  mg$text = normalize_label(m[cbind(mg$first_row, mg$first_col)])
  mg$span = vapply(seq_len(nrow(mg)), function(r)
    sum(cols >= mg$first_col[r] & cols <= mg$last_col[r]), integer(1))
  mg[mg$span >= 2 & mg$text != '', , drop = FALSE]
}

# Each data column's own label: its header cells stacked top to bottom,
# leaving out spanner anchors (they go to col_groups) and title lines (a
# header row whose only filled data cell is a long sentence).
stack_headers = function(m, hdr_rows, cols, merges, spanners) {
  m = blank_covered(m, merges[merges$first_row %in% hdr_rows, , drop = FALSE])
  if (nrow(spanners) > 0) m[cbind(spanners$first_row, spanners$first_col)] = ''
  keep = vapply(hdr_rows, function(i) {
    filled = which(m[i, cols] != '')
    !(length(filled) == 1 && nchar(m[i, cols[filled]]) > 40)
  }, logical(1))
  vapply(cols, function(j) {
    normalize_label(paste(m[hdr_rows[keep], j], collapse = ' '))
  }, character(1))
}

# The ' > '-joined spanners covering each data column, top to bottom. A
# spanner over > 80% of the data columns describes the table, not a split,
# and is left out.
col_groups = function(spanners, cols) {
  sp = spanners[spanners$span <= 0.8 * length(cols), , drop = FALSE]
  sp = sp[order(sp$first_row, sp$first_col), , drop = FALSE]
  vapply(cols, function(j) {
    paste(sp$text[sp$first_col <= j & sp$last_col >= j], collapse = ' > ')
  }, character(1))
}

#-------------------------------------
# AGI size classes
#-------------------------------------

# A size-of-AGI label -> c(lo, hi), dollars, [lo, hi). 'No adjusted gross
# income' is (-Inf, 1); '$X or more' / '$X and over' is [X, Inf); a label that
# is no class returns NULL. Every class bound carries a '$' -- which is what
# keeps Table 1.6's age rows ("18 under 26") from reading as classes -- and a
# parenthetical ("Under $5,000 (includes deficit)") is dropped. Totals are the
# caller's business.
parse_agi_class = function(label) {
  h = tolower(gsub('\\s+', ' ', label))
  h = trimws(gsub('\\([^)]*\\)', '', h))
  num = function(s) as.numeric(gsub('[$,]', '', s))
  if (grepl('^no adjusted gross income', h)) return(c(-Inf, 1))
  mm = regmatches(h, regexec('^\\$([0-9][0-9,]*) under \\$([0-9][0-9,]*)$', h))[[1]]
  if (length(mm) == 3) return(c(num(mm[2]), num(mm[3])))
  # an open bottom class: in tables with no "No adjusted gross income" row it
  # carries the deficit returns too (Table 2.3's "Under $5,000")
  mm = regmatches(h, regexec('^under \\$([0-9][0-9,]*)$', h))[[1]]
  if (length(mm) == 2) return(c(-Inf, num(mm[2])))
  mm = regmatches(h, regexec('^\\$([0-9][0-9,]*) (or more|and over)$', h))[[1]]
  if (length(mm) == 3) return(c(num(mm[2]), Inf))
  NULL
}

#-------------------------------------------------
# Whole-sheet extraction
#-------------------------------------------------

# Long rows for one column block: every data row between the block's number
# row and data_end, crossed with the block's columns. Column numbers are the
# published ones, so they continue across blocks; panel and section restart
# with each block.
extract_block = function(sh, blk, hdr_rows, data_end, path) {
  m = sh$m
  cols = blk$cols
  spanners = header_spanners(m, hdr_rows, cols, sh$merges)
  headers  = stack_headers(m, hdr_rows, cols, sh$merges, spanners)
  groups   = col_groups(spanners, cols)
  col_agi  = lapply(headers, parse_agi_class)
  label_cols = seq_len(min(cols) - 1)

  note_regex = '^(notes?\\s*:|source\\s*:|footnotes?\\b|\\*|\\[)'
  panel = NA_character_
  section = NA_character_
  out = list()
  for (i in seq(blk$row + 1, length.out = max(0, data_end - blk$row))) {
    lab_cells = m[i, label_cols]
    lab_idx = rev(which(lab_cells != ''))[1]
    label_raw = if (is.na(lab_idx)) '' else lab_cells[lab_idx]
    if (grepl(note_regex, tolower(label_raw))) break   # footnotes close the table
    label = normalize_label(label_raw)
    cells = m[i, cols]
    n_filled = sum(cells != '')
    if (label == '' && n_filled == 0) next
    if (n_filled == 0) {
      section = label
      next
    }
    if (label == '') stop(path, ': data in row ', i, ' with no label')
    if (grepl(', total$', tolower(label)) || tolower(label) == 'all returns') {
      panel = sub(',? total$', '', label, ignore.case = TRUE)
    }
    agi = parse_agi_class(label)
    cleaned = mapply(clean_value, cells, sh$flag[i, cols], SIMPLIFY = FALSE)
    out[[length(out) + 1]] = data.frame(
      row_seq    = i,
      panel      = panel,
      section    = section,
      row_label  = label,
      row_agi_lo = if (is.null(agi)) NA_real_ else agi[1],
      row_agi_hi = if (is.null(agi)) NA_real_ else agi[2],
      col_seq    = blk$vals,
      col_label  = headers,
      col_group  = groups,
      col_agi_lo = vapply(col_agi, function(a) if (is.null(a)) NA_real_ else a[1], numeric(1)),
      col_agi_hi = vapply(col_agi, function(a) if (is.null(a)) NA_real_ else a[2], numeric(1)),
      value      = unname(vapply(cleaned, function(v) v$value, numeric(1))),
      flag       = unname(vapply(cleaned, function(v) v$flag,  character(1))),
      row.names = NULL, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

# Parse one published sheet into long rows, one per (data row, data column):
#   panel      the stacked panel: opened by any row whose label ends ", total"
#              (the panel's own total row belongs to it) or reads "All returns"
#   section    the last label-only row (1.1's "Accumulated from smallest size")
#   row_label, col_label, col_group   as published, normalized
#   row_agi_lo/hi, col_agi_lo/hi      the size-of-AGI class on either axis,
#                                     dollars, [lo, hi)
#   col_seq    the published column number (continuing across stacked blocks)
#   value, flag                       see clean_value
extract_bysize_sheet = function(path, helper_dir) {
  sh = read_bysize_sheet(path, helper_dir)
  m = sh$m
  blocks = find_numrows(m)
  if (length(blocks) == 0) stop(path, ': no column-number row')
  out = list()
  for (k in seq_along(blocks)) {
    blk = blocks[[k]]
    # a lower block's header runs from just past the previous block's last
    # data-carrying row up to its own number row
    hdr_start = if (k == 1) 1 else {
      i = blk$row - 1
      while (i > blocks[[k - 1]]$row && sum(m[i, blk$cols] != '' &
             !is.na(suppressWarnings(as.numeric(m[i, blk$cols])))) < 2) i = i - 1
      i + 1
    }
    data_end = if (k < length(blocks)) {
      nb = blocks[[k + 1]]
      i = nb$row - 1
      while (i > blk$row && sum(m[i, nb$cols] != '' &
             !is.na(suppressWarnings(as.numeric(m[i, nb$cols])))) < 2) i = i - 1
      i
    } else nrow(m)
    out[[k]] = extract_block(sh, blk, hdr_start:(blk$row - 1), data_end, path)
  }
  df = do.call(rbind, out)
  if (is.null(df) || length(unique(df$row_seq)) < 10) {
    stop(path, ': parsed only ', length(unique(df$row_seq)), ' data rows')
  }
  # the title is A1, except TY1997 (Table 2.3) heads it with the report name
  title_rows = grep('^table [0-9]', tolower(m[seq_len(min(5, nrow(m))), 1]))
  attr(df, 'title') = gsub('\\s+', ' ', m[if (length(title_rows)) title_rows[1] else 1, 1])
  df
}

#-------------------------------------------------
# Label cleanup (align_bysize.R)
#-------------------------------------------------

# The column's item key: col_group > col_label with differences of FORM
# removed, never differences of meaning. Applied in order:
#   1. case, hyphens and dashes, quotes, whitespace ("S-corporation" = "S
#      corporation", "Social security" = "Social Security")
#   2. a year stamp equal to tax_year + 1 becomes {next year} ("Credited to
#      2012 estimated tax" in TY2011)
#   3. regex rewrites (perl) from checks/bysize_label_synonyms.csv
#      (family, from, to, reason; family '*' for all), each justified there:
#      typos, spelled-out abbreviations, spanner paths that moved without the
#      item changing
# A merge that changes what is counted is a concept change and belongs in
# the concept map instead.
item_key = function(family, col_group, col_label, tax_year, synonyms) {
  k = ifelse(col_group == '', col_label, paste(col_group, '>', col_label))
  k = tolower(k)
  k = gsub('["\u201c\u201d]', '', k)
  k = gsub('\\s*[-\u2013\u2014]+\\s*', ' ', k)
  k = trimws(gsub('\\s+', ' ', k))
  k = mapply(function(s, y) gsub(as.character(y + 1), '{next year}', s, fixed = TRUE),
             k, tax_year, USE.NAMES = FALSE)
  for (i in seq_len(nrow(synonyms))) {
    hit = synonyms$family[i] == '*' | family == synonyms$family[i]
    k[hit] = gsub(synonyms$from[i], synonyms$to[i], k[hit], perl = TRUE)
  }
  k
}

# Is a column additive across size classes (and across disjoint categories)?
# Percents of a total, percent-of ratios and averages are not. Matched on the
# cleaned item key and on whole words: a bare 'rate' would also catch
# "corporation", "separately" and "generated", and 'percent' alone would catch
# Table 3.5's rate groups ("15 percent > income taxed at rate") and 3.2's
# ratio bands, all of which are additive dollars or counts.
is_additive = function(item) {
  !grepl('percent of|percentage|average|\\bmean\\b|\\bmedian\\b|\\bratio\\b', item, perl = TRUE)
}

# Do the classes [lo, hi) tile one interval with no gap or overlap?
is_partition = function(lo, hi) {
  o = order(lo)
  length(lo) >= 2 && all(hi[o][-length(o)] == lo[o][-1])
}
