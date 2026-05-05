require(tidyverse)
require(rvest)
require(httr)

manifest_path <- "eci_assembly_manifest_2021_2026.csv"
output_dir <- "eci_assembly_results"

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

safe_numeric <- function(x) {
  x %>%
    str_replace_all(",", "") %>%
    na_if("-") %>%
    na_if("") %>%
    as.numeric()
}

clean_header <- function(x) {
  x %>%
    str_to_lower() %>%
    str_replace_all("[^a-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

locate_header_row <- function(tbl) {
  if (nrow(tbl) == 0) {
    return(NA_integer_)
  }

  row_signals <- apply(tbl, 1, \(row_vals) {
    vals <- clean_header(as.character(row_vals))
    any(vals == "candidate") &&
      any(vals == "party") &&
      any(vals %in% c("total_votes", "votes"))
  })

  which(row_signals) %>% first()
}

normalise_result_table <- function(tbl) {
  tbl <- tbl %>%
    mutate(across(everything(), as.character)) %>%
    mutate(across(everything(), str_squish))

  existing_names <- names(tbl) %>% clean_header()
  has_header_names <- any(existing_names == "candidate") &&
    any(existing_names == "party") &&
    any(existing_names %in% c("total_votes", "votes"))

  if (has_header_names) {
    names(tbl) <- existing_names
  } else {
  header_row <- locate_header_row(tbl)
    if (is.na(header_row)) {
      return(tibble())
    }

    if (header_row >= nrow(tbl)) {
      return(tibble())
    }

    names(tbl) <- tbl[header_row, ] %>% unlist() %>% clean_header()
    tbl <- tbl %>%
      slice((header_row + 1):n()) %>%
      filter(if_any(everything(), ~ !is.na(.x) & .x != ""))
  }

  required_cols <- c("candidate", "party")
  if (!all(required_cols %in% names(tbl))) {
    return(tibble())
  }

  if (!any(c("total_votes", "votes") %in% names(tbl))) {
    return(tibble())
  }

  if ("s_n" %in% names(tbl)) {
    tbl <- tbl %>% rename(sl_no = s_n)
  }

  if ("of_votes" %in% names(tbl)) {
    tbl <- tbl %>% rename(vote_pct = of_votes)
  }

  if ("_of_votes" %in% names(tbl)) {
    tbl <- tbl %>% rename(vote_pct = `_of_votes`)
  }

  if ("%_of_votes" %in% names(tbl)) {
    tbl <- tbl %>% rename(vote_pct = `%_of_votes`)
  }

  if ("votes" %in% names(tbl) && !"total_votes" %in% names(tbl)) {
    tbl <- tbl %>% rename(total_votes = votes)
  }

  tbl %>%
    filter(!is.na(candidate), candidate != "", str_to_lower(candidate) != "total") %>%
    mutate(
      evm_votes = if ("evm_votes" %in% names(.)) safe_numeric(evm_votes) else NA_real_,
      postal_votes = if ("postal_votes" %in% names(.)) safe_numeric(postal_votes) else NA_real_,
      total_votes = safe_numeric(total_votes),
      vote_pct = if ("vote_pct" %in% names(.)) safe_numeric(vote_pct) else NA_real_
    )
}

parse_constituency_meta <- function(page_text, expected_state) {
  pattern <- "Assembly\\s+Constituency\\s+(\\d+)\\s*-\\s*(.*?)\\s*\\((.*?)\\)"
  match <- regmatches(page_text, regexec(pattern, page_text))[[1]]

  if (length(match) >= 4) {
    return(
      tibble(
        parsed_constituency_no = as.integer(match[2]),
        constituency_name = str_squish(match[3]),
        parsed_state_name = str_squish(match[4])
      )
    )
  }

  tibble(
    parsed_constituency_no = NA_integer_,
    constituency_name = NA_character_,
    parsed_state_name = expected_state
  )
}

fetch_constituency_html <- function(url) {
  tmp <- tempfile(fileext = ".html")
  ua <- paste(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/124.0.0.0 Safari/537.36"
  )

  curl_attempt <- try(
    {
      curl_args <- c(
        "-L",
        "-s",
        "-o",
        tmp,
        url
      )

      curl_cmd <- paste(c("curl", shQuote(curl_args)), collapse = " ")
      system(curl_cmd, intern = TRUE, ignore.stderr = FALSE)
    },
    silent = TRUE
  )

  if (!inherits(curl_attempt, "try-error") && file.exists(tmp) && file.size(tmp) > 0) {
    return(list(ok = TRUE, page = read_html(tmp), method = "curl", url = url))
  }

  download_attempt <- try(
    download.file(
      url = url,
      destfile = tmp,
      quiet = TRUE,
      mode = "wb",
      method = "libcurl",
      headers = c(
        "User-Agent" = ua,
        "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language" = "en-IN,en;q=0.9",
        "Referer" = "https://results.eci.gov.in/",
        "Cache-Control" = "no-cache",
        "Pragma" = "no-cache"
      )
    ),
    silent = TRUE
  )

  if (!inherits(download_attempt, "try-error") && file.exists(tmp) && file.size(tmp) > 0) {
    return(list(ok = TRUE, page = read_html(tmp), method = "download.file", url = url))
  }

  response <- try(
    GET(
      url,
      user_agent(ua),
      add_headers(
        Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        `Accept-Language` = "en-IN,en;q=0.9",
        Referer = "https://results.eci.gov.in/",
        Connection = "keep-alive",
        `Cache-Control` = "no-cache",
        Pragma = "no-cache"
      ),
      timeout(60)
    ),
    silent = TRUE
  )

  if (inherits(response, "try-error")) {
    return(list(ok = FALSE, error = "request_failed", url = url))
  }

  if (status_code(response) != 200) {
    return(list(ok = FALSE, error = paste0("http_", status_code(response)), url = url))
  }

  list(ok = TRUE, page = read_html(response), method = "httr", url = url)
}

build_constituency_url <- function(base_url, state_type, eci_state_code, constituency_no, include_ac_query = FALSE) {
  url <- paste0(
    base_url,
    "/Constituencywise",
    state_type,
    str_pad(eci_state_code, 2, pad = "0"),
    constituency_no,
    ".htm"
  )

  if (include_ac_query) {
    url <- paste0(url, "?ac=", constituency_no)
  }

  url
}

download_constituency_results <- function(base_url, state_type, eci_state_code, constituency_no, election_id, state_name) {
  candidate_urls <- c(
    build_constituency_url(base_url, state_type, eci_state_code, constituency_no, include_ac_query = FALSE),
    build_constituency_url(base_url, state_type, eci_state_code, constituency_no, include_ac_query = TRUE)
  ) %>%
    unique()

  for (url in candidate_urls) {
    response <- fetch_constituency_html(url)

    if (!isTRUE(response$ok)) {
      next
    }

    page <- response$page
    tables <- page %>% html_elements("table") %>% html_table(convert = FALSE)
    cleaned_tables <- map(tables, ~ suppressWarnings(normalise_result_table(as_tibble(.x))))
    result_tbl <- cleaned_tables %>% keep(~ nrow(.x) > 0) %>% first()

    if (is.null(result_tbl)) {
      next
    }

    meta <- parse_constituency_meta(page %>% html_text2(), state_name)

    return(
      result_tbl %>%
        mutate(
          election_id = election_id,
          source_url = url,
          fetch_method = response$method,
          state_name = coalesce(meta$parsed_state_name[1], state_name),
          constituency_name = meta$constituency_name[1],
          constituency_no = constituency_no,
          eci_state_code = eci_state_code,
          state_type = state_type
        )
    )
  }

  tibble(error = "no_result_table", url = candidate_urls[[1]])
}

download_election <- function(manifest_row) {
  election_id <- manifest_row$election_id[[1]]
  output_path <- file.path(output_dir, manifest_row$output_file[[1]])

  message("Downloading ", election_id, " -> ", output_path)

  results <- map_dfr(seq_len(manifest_row$total_constituencies[[1]]), \(constituency_no) {
    res <- download_constituency_results(
      base_url = manifest_row$base_url[[1]],
      state_type = manifest_row$state_type[[1]],
      eci_state_code = manifest_row$eci_state_code[[1]],
      constituency_no = constituency_no,
      election_id = election_id,
      state_name = manifest_row$state_name[[1]]
    )

    message("  ", election_id, " constituency ", constituency_no, " done")
    res
  })

  write_csv(results, output_path, na = "")
  results
}

run_downloader <- function(args = commandArgs(trailingOnly = TRUE)) {
  manifest <- read_csv(manifest_path, show_col_types = FALSE)

  if (length(args) == 0) {
    selected_manifest <- manifest
  } else if (args[[1]] %in% c("recent", "backfill")) {
    selected_manifest <- manifest %>% filter(download_group == args[[1]])
  } else {
    selected_manifest <- manifest %>% filter(election_id %in% args)
  }

  if (nrow(selected_manifest) == 0) {
    stop("No elections matched the requested arguments.", call. = FALSE)
  }

  all_results <- selected_manifest %>%
    split(seq_len(nrow(.))) %>%
    map_dfr(download_election)

  save(all_results, file = file.path(output_dir, "eci_assembly_results_2021_2026.RData"))
  invisible(all_results)
}

if (sys.nframe() == 0) {
  run_downloader()
}
