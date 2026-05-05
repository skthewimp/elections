require(tidyverse)
require(arrow)
require(readxl)

bundle_dir <- "eci_assembly_results_since_2009"
data_dir <- file.path(bundle_dir, "data")
scripts_dir <- file.path(bundle_dir, "scripts")
manifest_path <- "eci_assembly_manifest_2021_2026.csv"
current_results_dir <- "eci_assembly_results"

dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(scripts_dir, recursive = TRUE, showWarnings = FALSE)

safe_num <- function(x) {
  x %>%
    as.character() %>%
    str_replace_all(",", "") %>%
    str_replace_all("%", "") %>%
    na_if("") %>%
    na_if("-") %>%
    na_if("NA") %>%
    as.numeric()
}

clean_text <- function(x) {
  x %>%
    as.character() %>%
    str_replace_all("[\r\n\t]+", " ") %>%
    str_squish() %>%
    na_if("")
}

standardise_state_name <- function(x) {
  y <- x %>%
    clean_text() %>%
    str_replace_all("_", " ") %>%
    str_replace_all("\\s*&\\s*", " & ")

  case_when(
    y %in% c("Delhi", "NCT OF Delhi", "NCT OF DELHI", "Nct Of Delhi") ~ "NCT of Delhi",
    y %in% c("Orissa") ~ "Odisha",
    y %in% c("Jammu and Kashmir") ~ "Jammu & Kashmir",
    TRUE ~ y
  )
}

slug_state <- function(x) {
  y <- standardise_state_name(x)
  y[y == "Jammu & Kashmir"] <- "Jammu Kashmir"

  y %>%
    str_to_lower() %>%
    str_replace_all("[^a-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
}

month_label <- function(x) {
  x_num <- suppressWarnings(as.integer(x))
  ifelse(!is.na(x_num) & x_num >= 1 & x_num <= 12, month.abb[x_num], NA_character_)
}

build_result_frame <- function(
  df,
  election_id,
  election_year,
  election_month = NA_integer_,
  state_name = NULL,
  constituency_no,
  constituency_name,
  candidate,
  party,
  total_votes,
  vote_pct = NULL,
  evm_votes = NULL,
  postal_votes = NULL,
  position = NULL,
  source_kind,
  source_dataset,
  source_file,
  source_url = NA_character_,
  fetch_method = NA_character_
) {
  state_vec <- if (is.null(state_name)) NA_character_ else state_name

  res <- tibble(
    election_id = election_id,
    election_year = as.integer(election_year),
    election_month = as.integer(election_month),
    election_month_label = month_label(election_month),
    state_name = standardise_state_name(state_vec),
    constituency_no = as.integer(safe_num(constituency_no)),
    constituency_name = clean_text(constituency_name),
    candidate = clean_text(candidate),
    party = clean_text(party),
    evm_votes = if (!is.null(evm_votes)) safe_num(evm_votes) else NA_real_,
    postal_votes = if (!is.null(postal_votes)) safe_num(postal_votes) else NA_real_,
    total_votes = safe_num(total_votes),
    vote_pct = if (!is.null(vote_pct)) safe_num(vote_pct) else NA_real_,
    source_kind = source_kind,
    source_dataset = source_dataset,
    source_file = source_file,
    source_url = source_url,
    fetch_method = fetch_method,
    source_position = if (!is.null(position)) safe_num(position) else NA_real_
  ) %>%
    filter(!is.na(candidate), !is.na(party), !is.na(total_votes)) %>%
    filter(candidate != "", party != "") %>%
    group_by(election_id, constituency_no) %>%
    mutate(
      vote_pct = if_else(
        is.na(vote_pct) & sum(total_votes, na.rm = TRUE) > 0,
        100 * total_votes / sum(total_votes, na.rm = TRUE),
        vote_pct
      ),
      position = min_rank(desc(total_votes)),
      winner = position == 1
    ) %>%
    ungroup() %>%
    mutate(
      position = coalesce(as.integer(source_position), as.integer(position)),
      winner = position == 1
    ) %>%
    select(
      election_id,
      election_year,
      election_month,
      election_month_label,
      state_name,
      constituency_no,
      constituency_name,
      candidate,
      party,
      evm_votes,
      postal_votes,
      total_votes,
      vote_pct,
      position,
      winner,
      source_kind,
      source_dataset,
      source_file,
      source_url,
      fetch_method
    )

  res
}

load_historical_2009_2017 <- function() {
  e <- new.env()
  load("allhistoricalelectionsEC.RData", envir = e)

  e$cands %>%
    filter(!Parliament, Year >= 2009, Year <= 2017) %>%
    mutate(
      state_name = standardise_state_name(StateName),
      election_id = paste0(slug_state(state_name), "_", Year)
    ) %>%
    build_result_frame(
      election_id = .$election_id,
      election_year = .$Year,
      election_month = .$Month,
      state_name = .$state_name,
      constituency_no = .$ConstNum,
      constituency_name = .$ConstName,
      candidate = .$Name,
      party = .$Party,
      total_votes = .$Votes,
      position = .$`Position `,
      source_kind = "local_historical_eci",
      source_dataset = "allhistoricalelectionsEC.RData",
      source_file = "allhistoricalelectionsEC.RData"
    ) %>%
    filter(election_id != "gujarat_2017")
}

load_gujarat_2017 <- function() {
  e <- new.env()
  load("gujarat2017.RData", envir = e)

  build_result_frame(
    df = e$gj,
    election_id = "gujarat_2017",
    election_year = 2017,
    state_name = e$gj$State,
    constituency_no = e$gj$Constnum,
    constituency_name = e$gj$Const,
    candidate = e$gj$Candidate,
    party = e$gj$Party,
    total_votes = e$gj$Votes,
    source_kind = "local_state_rdata",
    source_dataset = "gujarat2017.RData",
    source_file = "gujarat2017.RData"
  )
}

load_karnataka_2018 <- function() {
  df <- read_csv("Karnataka Elections 2018.csv", show_col_types = FALSE)

  build_result_frame(
    df = df,
    election_id = "karnataka_2018",
    election_year = 2018,
    election_month = 5,
    state_name = df$State,
    constituency_no = df$Constnum,
    constituency_name = df$Const,
    candidate = df$Candidate,
    party = df$Party,
    total_votes = df$Votes,
    vote_pct = 100 * safe_num(df$VotePerc),
    position = ifelse(df$Winner, 1, NA_real_),
    source_kind = "local_state_csv",
    source_dataset = "Karnataka Elections 2018.csv",
    source_file = "Karnataka Elections 2018.csv"
  )
}

load_mprjcgmzts_2018 <- function() {
  e <- new.env()
  load("mprajcgmzts2018.RData", envir = e)

  e$allelec %>%
    mutate(
      state_name = standardise_state_name(State),
      election_id = paste0(slug_state(state_name), "_2018")
    ) %>%
    build_result_frame(
      election_id = .$election_id,
      election_year = 2018,
      election_month = 12,
      state_name = .$state_name,
      constituency_no = .$Constnum,
      constituency_name = .$Const,
      candidate = .$Candidate,
      party = .$Party,
      total_votes = .$Votes,
      source_kind = "local_state_rdata",
      source_dataset = "mprajcgmzts2018.RData",
      source_file = "mprajcgmzts2018.RData"
    )
}

load_northeast_2018 <- function() {
  e <- new.env()
  load("northeast2018.RData", envir = e)

  bind_rows(
    e$megh %>% mutate(election_id = "meghalaya_2018", election_month = 2),
    e$nagaland %>% mutate(election_id = "nagaland_2018", election_month = 2),
    e$tripura %>% mutate(election_id = "tripura_2018", election_month = 2)
  ) %>%
    build_result_frame(
      election_id = .$election_id,
      election_year = 2018,
      election_month = .$election_month,
      state_name = .$State,
      constituency_no = .$Constnum,
      constituency_name = .$Const,
      candidate = .$Candidate,
      party = .$Party,
      total_votes = .$Votes,
      source_kind = "local_state_rdata",
      source_dataset = "northeast2018.RData",
      source_file = "northeast2018.RData"
    )
}

load_local_2019_2020 <- function() {
  e <- new.env()
  load("haryana2019.RData", envir = e)
  load("jharkhand2019.RData", envir = e)
  load("maharashtra2019.RData", envir = e)
  load("delhi2020.RData", envir = e)
  load("bihar2020.RData", envir = e)

  bind_rows(
    build_result_frame(
      df = e$hr,
      election_id = "haryana_2019",
      election_year = 2019,
      election_month = 10,
      state_name = e$hr$State,
      constituency_no = e$hr$ConstNum,
      constituency_name = e$hr$Const,
      candidate = e$hr$Candidate,
      party = e$hr$Party,
      evm_votes = e$hr$`EVM Votes`,
      postal_votes = e$hr$`Postal Votes`,
      total_votes = e$hr$`Total Votes`,
      source_kind = "local_state_rdata",
      source_dataset = "haryana2019.RData",
      source_file = "haryana2019.RData"
    ),
    build_result_frame(
      df = e$jhar,
      election_id = "jharkhand_2019",
      election_year = 2019,
      election_month = 12,
      state_name = e$jhar$State,
      constituency_no = e$jhar$ConstNum,
      constituency_name = e$jhar$Const,
      candidate = e$jhar$Candidate,
      party = e$jhar$Party,
      evm_votes = e$jhar$`EVM Votes`,
      postal_votes = e$jhar$`Postal Votes`,
      total_votes = e$jhar$`Total Votes`,
      source_kind = "local_state_rdata",
      source_dataset = "jharkhand2019.RData",
      source_file = "jharkhand2019.RData"
    ),
    build_result_frame(
      df = e$mh,
      election_id = "maharashtra_2019",
      election_year = 2019,
      election_month = 10,
      state_name = e$mh$State,
      constituency_no = e$mh$ConstNum,
      constituency_name = e$mh$Const,
      candidate = e$mh$Candidate,
      party = e$mh$Party,
      evm_votes = e$mh$`EVM Votes`,
      postal_votes = e$mh$`Postal Votes`,
      total_votes = e$mh$`Total Votes`,
      source_kind = "local_state_rdata",
      source_dataset = "maharashtra2019.RData",
      source_file = "maharashtra2019.RData"
    ),
    build_result_frame(
      df = e$del,
      election_id = "nct_of_delhi_2020",
      election_year = 2020,
      election_month = 2,
      state_name = e$del$State,
      constituency_no = e$del$ConstNum,
      constituency_name = e$del$Const,
      candidate = e$del$Candidate,
      party = e$del$Party,
      evm_votes = e$del$`EVM Votes`,
      postal_votes = e$del$`Postal Votes`,
      total_votes = e$del$`Total Votes`,
      source_kind = "local_state_rdata",
      source_dataset = "delhi2020.RData",
      source_file = "delhi2020.RData"
    ),
    build_result_frame(
      df = e$bihar,
      election_id = "bihar_2020",
      election_year = 2020,
      election_month = 11,
      state_name = e$bihar$State,
      constituency_no = e$bihar$ConstNum,
      constituency_name = e$bihar$Const,
      candidate = e$bihar$Candidate,
      party = e$bihar$Party,
      evm_votes = e$bihar$`EVM Votes`,
      postal_votes = e$bihar$`Postal Votes`,
      total_votes = e$bihar$`Total Votes`,
      source_kind = "local_state_rdata",
      source_dataset = "bihar2020.RData",
      source_file = "bihar2020.RData"
    )
  )
}

load_latest_fallback_2019 <- function() {
  e <- new.env()
  load("latestAssemblyElectionsIndia.RData", envir = e)

  year_map <- c(
    "Andhra Pradesh" = 2019,
    "Arunachal Pradesh" = 2019,
    "Odisha" = 2019,
    "Sikkim" = 2019
  )

  e$allAssembly %>%
    filter(State %in% names(year_map)) %>%
    mutate(
      state_name = standardise_state_name(State),
      election_year = unname(year_map[state_name]),
      election_month = 5L,
      election_id = paste0(slug_state(state_name), "_", election_year)
    ) %>%
    build_result_frame(
      election_id = .$election_id,
      election_year = .$election_year,
      election_month = .$election_month,
      state_name = .$state_name,
      constituency_no = .$Constnum,
      constituency_name = .$Const,
      candidate = .$Candidate,
      party = .$Party,
      total_votes = .$Votes,
      source_kind = "local_latest_fallback",
      source_dataset = "latestAssemblyElectionsIndia.RData",
      source_file = "latestAssemblyElectionsIndia.RData"
    )
}

load_tcpd_2021_2023 <- function() {
  df <- read_csv("TCPD_AE_All_States_2023-5-9.csv", show_col_types = FALSE)

  df %>%
    filter(Year >= 2021, Year <= 2023) %>%
    filter(!(Year == 2023 & State_Name == "Karnataka")) %>%
    mutate(
      state_name = standardise_state_name(State_Name),
      election_id = paste0(slug_state(state_name), "_", Year)
    ) %>%
    build_result_frame(
      election_id = .$election_id,
      election_year = .$Year,
      election_month = .$month,
      state_name = .$state_name,
      constituency_no = .$Constituency_No,
      constituency_name = .$Constituency_Name,
      candidate = .$Candidate,
      party = .$Party,
      total_votes = .$Votes,
      vote_pct = .$Vote_Share_Percentage,
      position = .$Position,
      source_kind = "tcpd_candidate_data",
      source_dataset = "TCPD_AE_All_States_2023-5-9.csv",
      source_file = "TCPD_AE_All_States_2023-5-9.csv"
    )
}

load_karnataka_2023 <- function() {
  e <- new.env()
  load("kar23.RData", envir = e)

  build_result_frame(
    df = e$k23,
    election_id = "karnataka_2023",
    election_year = 2023,
    election_month = 5,
    state_name = e$k23$State,
    constituency_no = e$k23$ConstNum,
    constituency_name = e$k23$Const,
    candidate = e$k23$Candidate,
    party = e$k23$Party,
    evm_votes = e$k23$`EVM Votes`,
    postal_votes = e$k23$`Postal Votes`,
    total_votes = e$k23$`Total Votes`,
    source_kind = "local_state_rdata",
    source_dataset = "kar23.RData",
    source_file = "kar23.RData"
  )
}

load_eci_2023_pdf_supplement <- function() {
  supplement_path <- "/tmp/eci_2023_pdf_supplement.parquet"

  if (!file.exists(supplement_path)) {
    return(tibble())
  }

  read_parquet(supplement_path) %>%
    as_tibble()
}

load_eci_2024_2025_official_reports <- function() {
  official_reports <- tribble(
    ~election_id, ~election_year, ~election_month, ~state_name, ~source_url,
    "andhra_pradesh_2024", 2024, 6L, "Andhra Pradesh", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-AP/10-Detailed-Results.xlsx",
    "arunachal_pradesh_2024", 2024, 6L, "Arunachal Pradesh", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-AR/10-Detailed-Results.xlsx",
    "odisha_2024", 2024, 6L, "Odisha", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-OR/10-Detailed-Results.xlsx",
    "sikkim_2024", 2024, 6L, "Sikkim", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-SK/10-Detailed-Results.xlsx",
    "haryana_2024", 2024, 10L, "Haryana", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-HR/10-Detailed-Results.xlsx",
    "jammu_kashmir_2024", 2024, 10L, "Jammu & Kashmir", "https://www.eci.gov.in/eci-backend/public/all_files/AE-2024-statistical-report-JK/10-Detailed-Results.xlsx",
    "jharkhand_2024", 2024, 11L, "Jharkhand", "https://www.eci.gov.in/eci-backend/public//all_files/election_report/Jharkhand_Legislative_Assembly_Election__2024_2024/10-Detailed_Results_1744892172.xlsx",
    "maharashtra_2024", 2024, 11L, "Maharashtra", "https://www.eci.gov.in/eci-backend/public//all_files/election_report/Maharashtra_Legislative_Assembly_Election__2024_2024/10-Detailed_Results_1744893339.xlsx",
    "delhi_2025", 2025, 2L, "NCT of Delhi", "https://www.eci.gov.in/eci-backend/public//all_files/election_report/NCT_of_Delhi_Legislative_Assembly_Election_2025_2025/10-Detailed_Results_1744913508.xlsx"
  )

  map_dfr(seq_len(nrow(official_reports)), function(idx) {
    meta <- official_reports[idx, ]
    tmp <- tempfile(fileext = ".xlsx")
    status <- system2(
      "curl",
      c("-L", "-s", "-o", tmp, meta$source_url),
      stdout = FALSE,
      stderr = FALSE
    )

    if (!identical(status, 0L) || !file.exists(tmp) || file.size(tmp) == 0) {
      return(tibble())
    }

    df <- read_excel(tmp, skip = 3, .name_repair = "unique") %>%
      as_tibble()

    build_result_frame(
      df = df,
      election_id = meta$election_id,
      election_year = meta$election_year,
      election_month = meta$election_month,
      state_name = df$`STATE/UT NAME`,
      constituency_no = df$`AC NO.`,
      constituency_name = df$`AC NAME`,
      candidate = df$`CANDIDATE NAME`,
      party = df$PARTY,
      evm_votes = df$GENERAL,
      postal_votes = df$POSTAL,
      total_votes = df$TOTAL,
      vote_pct = df$`OVER VALID VOTES + NOTA`,
      source_kind = "eci_official_statistical_report",
      source_dataset = "eci_backend_public_api_election_result",
      source_file = basename(meta$source_url),
      source_url = meta$source_url,
      fetch_method = "curl_xlsx"
    )
  })
}

load_constituency_gap_fixes <- function() {
  tribble(
    ~election_id, ~election_year, ~election_month, ~election_month_label, ~state_name, ~constituency_no, ~constituency_name, ~candidate, ~party, ~evm_votes, ~postal_votes, ~total_votes, ~vote_pct, ~position, ~winner, ~source_kind, ~source_dataset, ~source_file, ~source_url, ~fetch_method,
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 3L, "Mukto", "PEMA KHANDU", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 7L, "Bomdila", "DONGRU SIONGJU", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 13L, "Itanagar", "TECHI KASO", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 15L, "Sagalee", "RATU TECHI", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 17L, "Ziro-Hapoli", "HAGE APPA", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 20L, "Tali", "JIKKE TAKO", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 23L, "Taliha", "NYATO DUKAM", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 43L, "Roing", "MUTCHU MITHI", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 45L, "Hayuliang", "DASANGLU PUL", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "arunachal_pradesh_2024", 2024L, 6L, "Jun", "Arunachal Pradesh", 46L, "Chowkham", "CHOWNA MEIN", "Bharatiya Janata Party", 0, NA_real_, 0, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ar2024_report8.xlsx", NA_character_, "manual_gap_fix",
    "meghalaya_2023", 2023L, 3L, "Mar", "Meghalaya", 23L, "Sohiong", "SYNSHAR KUPAR ROY LYNGDOH THABAH", "United Democratic Party", NA_real_, NA_real_, 16679, 51.86, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "ResultAcGenMay2023/ConstituencywiseS1523.htm?ac=23", "https://results.eci.gov.in/ResultAcGenMay2023/ConstituencywiseS1523.htm?ac=23", "manual_gap_fix",
    "chhattisgarh_2023", 2023L, 12L, "Dec", "Chhattisgarh", 89L, "Bijapur (ST)", "VIKRAM MANDAVI", "Indian National Congress", NA_real_, NA_real_, 35739, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "chhattisgarh2023.pdf", NA_character_, "manual_gap_fix",
    "chhattisgarh_2023", 2023L, 12L, "Dec", "Chhattisgarh", 90L, "Konta (ST)", "KAWASI LAKHMA", "Indian National Congress", NA_real_, NA_real_, 32776, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "chhattisgarh2023.pdf", NA_character_, "manual_gap_fix",
    "madhya_pradesh_2023", 2023L, 12L, "Dec", "Madhya Pradesh", 65L, "Maihar", "Shrikant Chaturvedi", "Bharatiya Janata Party", NA_real_, NA_real_, 76870, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "mp2023.pdf", NA_character_, "manual_gap_fix",
    "madhya_pradesh_2023", 2023L, 12L, "Dec", "Madhya Pradesh", 75L, "Gurh", "NAGENDRA SINGH", "Bharatiya Janata Party", NA_real_, NA_real_, 68715, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "mp2023.pdf", NA_character_, "manual_gap_fix",
    "madhya_pradesh_2023", 2023L, 12L, "Dec", "Madhya Pradesh", 174L, "Bagali (ST)", "MURLI BHAWARA", "Bharatiya Janata Party", NA_real_, NA_real_, 105320, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "mp2023.pdf", NA_character_, "manual_gap_fix",
    "madhya_pradesh_2023", 2023L, 12L, "Dec", "Madhya Pradesh", 196L, "Sardarpur (ST)", "PRATAP GREWAL", "Indian National Congress", NA_real_, NA_real_, 86114, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "mp2023.pdf", NA_character_, "manual_gap_fix",
    "madhya_pradesh_2023", 2023L, 12L, "Dec", "Madhya Pradesh", 230L, "Jawad", "OMPRAKASH SAKHLECHA", "Bharatiya Janata Party", NA_real_, NA_real_, 60458, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "mp2023.pdf", NA_character_, "manual_gap_fix",
    "rajasthan_2023", 2023L, 12L, "Dec", "Rajasthan", 185L, "Keshoraipatan (SC)", "CHUNNILAL C.L. PREMI BAIRWA", "Indian National Congress", NA_real_, NA_real_, 101541, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "rajasthan2023.pdf", NA_character_, "manual_gap_fix",
    "rajasthan_2023", 2023L, 12L, "Dec", "Rajasthan", 198L, "Jhalrapatan", "VASUNDHARA RAJE", "Bharatiya Janata Party", NA_real_, NA_real_, 138831, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "rajasthan2023.pdf", NA_character_, "manual_gap_fix",
    "rajasthan_2023", 2023L, 12L, "Dec", "Rajasthan", 199L, "Khanpur", "SURESH GURJAR", "Indian National Congress", NA_real_, NA_real_, 101045, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "rajasthan2023.pdf", NA_character_, "manual_gap_fix",
    "rajasthan_2023", 2023L, 12L, "Dec", "Rajasthan", 200L, "Manohar Thana", "GOVIND PRASAD", "Bharatiya Janata Party", NA_real_, NA_real_, 85304, NA_real_, 1L, TRUE, "eci_gap_fix", "eci_gap_fix_manual", "rajasthan2023.pdf", NA_character_, "manual_gap_fix"
  ) %>%
    as_tibble()
}

load_successful_eci_scrapes <- function() {
  manifest <- read_csv(manifest_path, show_col_types = FALSE)

  csv_paths <- list.files(current_results_dir, pattern = "[.]csv$", full.names = TRUE)

  map_dfr(csv_paths, function(path) {
    df <- suppressMessages(read_csv(path, show_col_types = FALSE))

    if (!all(c("candidate", "party", "total_votes") %in% names(df))) {
      return(tibble())
    }

    if (nrow(df) == 0) {
      return(tibble())
    }

    meta <- manifest %>%
      filter(election_id == unique(df$election_id)[1]) %>%
      slice(1)

    build_result_frame(
      df = df,
      election_id = df$election_id,
      election_year = if (nrow(meta) == 1) meta$election_year else NA_integer_,
      election_month = NA_integer_,
      state_name = df$state_name,
      constituency_no = df$constituency_no,
      constituency_name = df$constituency_name,
      candidate = df$candidate,
      party = df$party,
      evm_votes = df$evm_votes,
      postal_votes = df$postal_votes,
      total_votes = df$total_votes,
      vote_pct = df$vote_pct,
      source_kind = "eci_live_scrape",
      source_dataset = "eci_assembly_results",
      source_file = basename(path),
      source_url = df$source_url,
      fetch_method = df$fetch_method
    )
  })
}

dedupe_results <- function(df) {
  priority <- c(
    "eci_gap_fix" = 0L,
    "eci_live_scrape" = 1L,
    "local_state_rdata" = 2L,
    "local_state_csv" = 3L,
    "tcpd_candidate_data" = 4L,
    "local_historical_eci" = 5L,
    "local_latest_fallback" = 6L
  )

  df %>%
    mutate(source_priority = unname(priority[source_kind])) %>%
    arrange(source_priority, election_id, constituency_no, position, desc(total_votes)) %>%
    distinct(election_id, constituency_no, candidate, party, .keep_all = TRUE) %>%
    select(-source_priority)
}

expected_elections <- tribble(
  ~election_id,
  "andhra_pradesh_2009",
  "arunachal_pradesh_2009",
  "haryana_2009",
  "jharkhand_2009",
  "maharashtra_2009",
  "odisha_2009",
  "sikkim_2009",
  "bihar_2010",
  "assam_2011",
  "kerala_2011",
  "puducherry_2011",
  "tamil_nadu_2011",
  "west_bengal_2011",
  "goa_2012",
  "gujarat_2012",
  "himachal_pradesh_2012",
  "manipur_2012",
  "punjab_2012",
  "uttar_pradesh_2012",
  "uttarakhand_2012",
  "chhattisgarh_2013",
  "karnataka_2013",
  "madhya_pradesh_2013",
  "meghalaya_2013",
  "mizoram_2013",
  "nagaland_2013",
  "nct_of_delhi_2013",
  "rajasthan_2013",
  "tripura_2013",
  "andhra_pradesh_2014",
  "arunachal_pradesh_2014",
  "haryana_2014",
  "jammu_kashmir_2014",
  "jharkhand_2014",
  "maharashtra_2014",
  "odisha_2014",
  "sikkim_2014",
  "bihar_2015",
  "nct_of_delhi_2015",
  "assam_2016",
  "kerala_2016",
  "puducherry_2016",
  "tamil_nadu_2016",
  "west_bengal_2016",
  "goa_2017",
  "gujarat_2017",
  "manipur_2017",
  "punjab_2017",
  "uttar_pradesh_2017",
  "uttarakhand_2017",
  "karnataka_2018",
  "chhattisgarh_2018",
  "madhya_pradesh_2018",
  "mizoram_2018",
  "rajasthan_2018",
  "telangana_2018",
  "meghalaya_2018",
  "nagaland_2018",
  "tripura_2018",
  "andhra_pradesh_2019",
  "arunachal_pradesh_2019",
  "haryana_2019",
  "jharkhand_2019",
  "maharashtra_2019",
  "odisha_2019",
  "sikkim_2019",
  "bihar_2020",
  "nct_of_delhi_2020",
  "assam_2021",
  "kerala_2021",
  "puducherry_2021",
  "tamil_nadu_2021",
  "west_bengal_2021",
  "goa_2022",
  "gujarat_2022",
  "himachal_pradesh_2022",
  "manipur_2022",
  "punjab_2022",
  "uttar_pradesh_2022",
  "uttarakhand_2022",
  "chhattisgarh_2023",
  "karnataka_2023",
  "madhya_pradesh_2023",
  "meghalaya_2023",
  "mizoram_2023",
  "nagaland_2023",
  "rajasthan_2023",
  "telangana_2023",
  "tripura_2023",
  "andhra_pradesh_2024",
  "arunachal_pradesh_2024",
  "haryana_2024",
  "jammu_kashmir_2024",
  "jharkhand_2024",
  "maharashtra_2024",
  "odisha_2024",
  "sikkim_2024",
  "delhi_2025",
  "assam_2026",
  "kerala_2026",
  "puducherry_2026",
  "tamil_nadu_2026",
  "west_bengal_2026"
)

all_results <- bind_rows(
  load_historical_2009_2017(),
  load_gujarat_2017(),
  load_karnataka_2018(),
  load_mprjcgmzts_2018(),
  load_northeast_2018(),
  load_local_2019_2020(),
  load_latest_fallback_2019(),
  load_tcpd_2021_2023(),
  load_karnataka_2023(),
  load_eci_2023_pdf_supplement(),
  load_eci_2024_2025_official_reports(),
  load_constituency_gap_fixes(),
  load_successful_eci_scrapes()
) %>%
  dedupe_results() %>%
  arrange(election_year, state_name, constituency_no, position, desc(total_votes))

assembly_candidate_results <- all_results

write_parquet(
  assembly_candidate_results,
  sink = file.path(data_dir, "assembly_candidate_results_since_2009.parquet")
)

save(
  assembly_candidate_results,
  file = file.path(data_dir, "assembly_candidate_results_since_2009.RData")
)

file.copy("download_eci_assembly_results.R", file.path(scripts_dir, "download_eci_assembly_results.R"), overwrite = TRUE)
file.copy("build_eci_assembly_bundle.R", file.path(scripts_dir, "build_eci_assembly_bundle.R"), overwrite = TRUE)
file.copy(manifest_path, file.path(scripts_dir, "eci_assembly_manifest_2021_2026.csv"), overwrite = TRUE)

covered_elections <- assembly_candidate_results %>%
  distinct(election_id) %>%
  arrange(election_id)

missing_elections <- expected_elections %>%
  anti_join(covered_elections, by = "election_id")

cat("Rows:", nrow(assembly_candidate_results), "\n")
cat("Elections covered:", nrow(covered_elections), "\n")
cat("Missing expected elections:", nrow(missing_elections), "\n")

if (nrow(missing_elections) > 0) {
  print(missing_elections)
}
