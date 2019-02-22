library(rlang)
library(purrr)
library(glue)
library(rAltmetric)
# library(ghql)

qry <- ghql::Query$new()
cli <- ghql::GraphqlClient$new(
  url = "https://api.github.com/graphql",
  headers = httr::add_headers(Authorization = paste0("Bearer ", gh:::gh_token()))
)
cli$load_schema()
event_json <- jsonlite::fromJSON("/github/workflow/event.json")
user <- event_json$sender$login
repo <- event_json$repository$name
current_labels <- 
  event_json$issue$labels$name

# Functions ---------------------------------------------------------------
round_journal_name <- function(x) {
  gsub("\\{\\\\", "", x) %>% 
    gsub("}", "", .) %>% 
    gsub("\\{", "", .) %>% 
    gsub("Journal", "J.", .)
  
}
check_duplicate <- function(issue_title, issue_list, event_json, close = FALSE, user = user, repo = repo) {
  
  duplicate_num <- 
    subset(issue_list, title == issue_title) %>%
    purrr::pluck("number")
  
  if (rlang::is_false(is.null(duplicate_num)) & rlang::is_true(close)) {
    
    gh::gh("PATCH /repos/:owner/:repo/issues/:number",
           owner = user,
           repo = repo,
           number = event_json$issue$number,
           body = glue("Duplicate #{duplicate_num}"),
           labels = list("duplicate"),
           state = "closed")
  } 
  
  duplicate_num
  
}
identific_altmetrics <- 
  function(type = NULL, identifer = NULL) {
    
    args <- 
      list(doi = ifelse(type == "DOI", identifer, NA),
           arxiv = ifelse(type == "arxiv", identifer, NA)) %>% 
      purrr::keep(~ !is.na(.x))
    
    res_altm <-
      rlang::exec("altmetrics", !!!args)
    
    df_res_altm <-
      rAltmetric::altmetric_data(res_altm)
    
    df_res_altm <-
      df_res_altm[, c(
        "cited_by_posts_count",
        "cited_by_tweeters_count",
        "cited_by_accounts_count",
        "score",
        "last_updated"
      )]
    
    df_res_altm$last_updated <-
      as.POSIXct(as.numeric(df_res_altm$last_updated),
                 origin = "1970-01-01 00:00:00",
                 tz = "UTC")
    
    altmetric_score <-
      df_res_altm %>%
      knitr::kable() %>%
      as.character() %>%
      paste(collapse = "\n")
    
    altmetric_url <-
      res_altm$details_url
    
    list(score = altmetric_score, url = altmetric_url)
    
  }

# 1. Create issue template ------------------------------------------------
path_issue_template <- ".github/ISSUE_TEMPLATE/paper_template.md"

queries <- list(issue_template = list("data", "repository", "object"),
                issue_count = list("data", "repository", "issues", "totalCount"),
                collect_article_issue = list("data", "repository", "issues", "edges", "node"))
qry$query("issue_template",
          glue('
query{
  repository(owner: "<user>",name: "<repo>"){
    object(expression: "master:<path_issue_template>") {
      ... on Blob {
        text
      }
    }
  }
}',
               .open = "<",
               .close = ">"))

is_issue_template_exist <- 
  negate(
    ~ jsonlite::fromJSON(.x) %>% 
      ## purrr::map_depth(3, ~ is.null(.x)) ... same 
      pluck(!!! queries %>% 
              pluck("issue_template")) %>%
      is.null()
  )(cli$exec(qry$queries$issue_template))

if (rlang::is_false(is_issue_template_exist)) {
  issue_template_base64 <- 
    openssl::base64_encode("---
name: paper_template
about: Issue for papers.
title: 'DOI / arXiv: <identifier>'
labels: papers
assignees: ''

---

## Summary

## Description

### :flashlight: Highlights

### :game_die: Approach

### :hatching_chick: Results

### :speech_balloon: Comments")
  
  # openssl::base64_decode(issue_template_base64) %>% 
  #   rawToChar() %>% 
  #   cat()
  
  gh::gh("PUT /repos/:owner/:repo/contents/:path",
         owner = user,
         repo = repo,
         path = path_issue_template,
         message = "Added paper template",
         content = issue_template_base64)
}


# 2. Update article information -------------------------------------------
issue_title <- event_json$issue$title

paper_type <-
  ifelse(grepl("arxiv", issue_title, ignore.case = TRUE),
         "arxiv",
         ifelse(grepl("doi", issue_title, ignore.case = TRUE),
                "DOI",
                rlang::warn("Can't detect DOI or arXiv identifer")))

if (paper_type %in% c("arxiv", "DOI")) {
  
  qry$query("issue_count",
            glue(
              'query {
  repository(owner: "<user>", name: "<repo>") {
    issues {
      totalCount
    }
  }
}',
              .open = "<",
              .close = ">"
            ))
  
  issue_count <- 
    cli$exec(qry$queries$issue_count) %>% 
    jsonlite::fromJSON() %>% 
    pluck(!!! queries %>% 
            purrr::pluck("issue_count"))
  
  qry$query("collect_article_issue",
            glue(
              'query {
  repository(owner: "<user>", name: "<repo>") {
    issues (labels: "papers", first: <issue_count>) {
      edges {
        node {
          title,
          number
        }
      }
    }
  }
}
', 
.open = "<",
.close = ">"))
  
  df_issues  <- 
    cli$exec(qry$queries$collect_article_issue) %>% 
    jsonlite::fromJSON() %>% 
    pluck(!!! queries %>% 
            pluck("collect_article_issue"))
  
  # req_issue_list <- 
  #   gh::gh("GET /repos/:owner/:repo/issues",
  #          owner = event_json$sender$login,
  #          repo = event_json$repository$name)
  # df_issues <- 
  #   data.frame(
  #     number = req_issue_list %>% 
  #       purrr::map_chr(c("number")),
  #     title = req_issue_list %>% 
  #       purrr::map_chr(c("title")), stringsAsFactors = FALSE)
  
  paper_identifer <-
    gsub("[[:space:]]", "", gsub(".+:", "", issue_title))
  
  if (paper_type == "arxiv") {
    paper_identifer <- gsub("v.+", "", paper_identifer)
  } 
  
  altm_status <- 
    httr::status_code(httr::GET(glue("http://api.altmetric.com/v1/{paper_type}/{paper_identifer}")))
  
  if (paper_type == "arxiv") {
    
    if (rlang::is_true(httr:::http_error(glue("https://arxiv.org/abs/{paper_identifer}")))) {
      
      gh::gh("POST /repos/:owner/:repo/issues/:number/comments",
             owner = user,
             repo = repo,
             number = event_json$issue$number,
             body = "Article identifier not recognized. Please, check identifier.")
      
    } else {
      
      target_article <-
        aRxiv::arxiv_search(id_list = paper_identifer, sep = ", ", limit = 1)
      
      authors <- target_article$authors
      title <- target_article$title
      url <- target_article$link_abstract
      submited_year <- substr(target_article$submitted, 1, 4)
      abstract <- target_article$abstract
      
      issue_title <-
        paste(
          paste(
            gsub(pattern = "[[:space:]].+", "", authors),
            submited_year,
            sep = "_"
          ),
          title, sep = ": ")
      
      duplicate_num <- 
        check_duplicate(issue_title, df_issues, event_json, close = FALSE, user, repo)
      
    }
  } else if (paper_type == "DOI") {
    
    target_article <-
      rcrossref::cr_cn(dois = paper_identifer, style = "oikos", format = "bibentry")
    
    if (is.null(target_article)) {
      gh::gh("POST /repos/:owner/:repo/issues/:number/comments",
             owner = user,
             repo = repo,
             number = event_json$issue$number,
             body = "DOI Not Found. Please, check identifier.")
      
    } else {
      
      authors <- ifelse(is.null(target_article$author), "", target_article$author)
      title <- round_journal_name(target_article$title)
      url <- target_article$url
      
      issue_title <- glue("{key}: {title}",
                          key = target_article$key)
      
      duplicate_num <- 
        check_duplicate(issue_title, df_issues, event_json, close = FALSE, user, repo)
    }
  }
  
  # Added article information -----------------------------------------------
  if (!is.null(target_article) & is.null(duplicate_num)) {
    
    if (paper_type == "arxiv") {
      issue_labels <-
        list(paste("Journal:", "arXiv"),
             paste("Published year:", submited_year),
             paste("Category:", target_article$primary_category))
      
      res_altm <-
        rAltmetric::altmetrics(arxiv = paper_identifer)
      
      issue_body <- 
        glue(
          "## Information\n
:page_with_curl: Title: **{title}**
:busts_in_silhouette: Authors: {authors}
:link: URL: [{url}]({url})
:date: Submitted: {submit_time} (Update: {update_time})\n

### Abstract\n
```
{abstract}
```",
          submit_time = as.POSIXct(target_article$submitted, tz = "UTC"),
          update_time = as.POSIXct(target_article$updated, tz = "UTC"))
    } else if (paper_type == "DOI") {
      
      issue_labels <-
        list(paste("Journal:", round_journal_name(target_article$journal)),
             paste("Published year:", target_article$year),
             paste("Type:", target_article$entry))
      
      issue_body <- 
        glue(
          "## Information\n
      :page_with_curl: Title: **{title}**
      :busts_in_silhouette: Authors: {authors}
      :link: URL: [{url}]({url})
      :date: {month} {year} (Volume{volume}{number})
      ",
          year = target_article$year,
          month = month.name[which(grepl(target_article$month, month.abb, ignore.case = TRUE))],
          volume = ifelse(is.null(target_article$volume), 
                          "",
                          target_article$volume),
          number = ifelse(is.null(target_article$number), "", 
                          paste0(" #", target_article$number)))
      
    }
    
    # Modified issue title and assigned label ---------------------------------
    issue_labels <- 
      purrr::list_modify(issue_labels, !!!as.list(current_labels) %>% 
                           purrr::set_names(current_labels)) %>% 
      purrr::set_names(NULL) %>% 
      purrr::keep(~ nchar(.x) <= 50)
    
    gh::gh("PATCH /repos/:owner/:repo/issues/:number",
           owner = user,
           repo = repo,
           number = event_json$issue$number,
           title = issue_title,
           labels = issue_labels)
    
    if (identical(altm_status, 200L)) {
      
      res_altm <- 
        identific_altmetrics(type = paper_type, identifer = paper_identifer)
      
      issue_body <- 
        glue(
          issue_body,
          "\n\n",
          glue(
            '### Article metrics\n
    {score}\n
    {url}',
            score = res_altm$score,
            url = res_altm$url),
          .open = "AAA",
          .close = "ZZZ")
      
    }
    
    gh::gh("POST /repos/:owner/:repo/issues/:number/comments",
           owner = user,
           repo = repo,
           number = event_json$issue$number,
           body = issue_body)
  }
}
