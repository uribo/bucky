library(rlang)
library(purrr, warn.conflicts = FALSE)
library(glue)
library(rAltmetric)
library(buckyR)
# library(ghql)

reference_style <- "oikos"
path_references_bib <- "references.bib"

qry <- ghql::Query$new()
cli <- ghql::GraphqlClient$new(
  url = "https://api.github.com/graphql",
  headers = httr::add_headers(Authorization = paste0("Bearer ", gh:::gh_token()))
)
cli$load_schema()
event_json <- jsonlite::fromJSON("/github/workflow/event.json")
user <- event_json$repository$owner$login
repo <- event_json$repository$name
current_labels <- 
  event_json$issue$labels$name

# Functions ---------------------------------------------------------------

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

# 1. Create issue template ------------------------------------------------
path_issue_template <- ".github/ISSUE_TEMPLATE/paper_template.md"

queries <- list(issue_template = list("data", "repository", "object"),
                issue_count = list("data", "repository", "issues", "totalCount"),
                exist_bibfile = list("data", "repository", "object"),
                collect_article_issue = list("data", "repository", "issues", "edges", "node"))
qry$query("issue_template",
          glue::glue('
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
  buckyR:::detect_paper_type(issue_title)

if (paper_type %in% c("arxiv", "DOI")) {
  
  qry$query("issue_count",
            glue::glue(
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
            glue::glue(
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
    buckyR:::extract_identifer(issue_title)
  
  if (paper_type == "arxiv") {
    paper_identifer <- gsub("v.+", "", paper_identifer)
  } 
  
  altm_status <- 
    httr::status_code(httr::GET(glue::glue("http://api.altmetric.com/v1/{paper_type}/{paper_identifer}")))
  
  if (paper_type == "arxiv") {
    
    if (rlang::is_true(httr:::http_error(glue::glue("https://arxiv.org/abs/{paper_identifer}")))) {
      
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
      rcrossref::cr_cn(dois = paper_identifer, 
                       format = "bibtex", 
                       style = reference_style)
    
    if (is.null(target_article)) {
      gh::gh("POST /repos/:owner/:repo/issues/:number/comments",
             owner = user,
             repo = repo,
             number = event_json$issue$number,
             body = "DOI Not Found. Please, check identifier.")
      
    } else {
      
      target_article_parsed <- 
        rcrossref:::parse_bibtex(target_article)
      
      authors <- ifelse(is.null(target_article_parsed$author), "", target_article_parsed$author)
      title <- buckyR::abbr_journal_name(target_article_parsed$title)
      url <- target_article_parsed$url
      
      issue_title <- glue::glue("{key}: {title}",
                          key = target_article_parsed$key)
      
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
        glue::glue(
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
        list(paste("Journal:", abbr_journal_name(target_article_parsed$journal)),
             paste("Published year:", target_article_parsed$year),
             paste("Type:", target_article_parsed$entry))
      
      issue_body <- 
        buckyR:::make_issue_info(target_article_parsed)
      
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
      issue_body <- 
        buckyR:::make_issue_metrics(issue_body, paper_type, paper_identifer)
    }
    
    gh::gh("POST /repos/:owner/:repo/issues/:number/comments",
           owner = user,
           repo = repo,
           number = event_json$issue$number,
           body = issue_body)
    
    if (paper_type == "DOI") {
      qry$query("exist_bibfile",
                glue::glue('
query{
  repository(owner: "<user>",name: "<repo>"){
    object(expression: "master:<path_references_bib>") {
      ... on Blob {
        text
      }
    }
  }
}',
                     .open = "<",
                     .close = ">"))
      
      is_bibfile_exist <- 
        purrr::negate(
          ~ jsonlite::fromJSON(.x) %>% 
            pluck(!!! queries %>% 
                    pluck("exist_bibfile")) %>%
            is.null()
        )(cli$exec(qry$queries$exist_bibfile))
      
      if (rlang::is_true(is_bibfile_exist)) {
        
        get_bib <- 
          gh::gh("GET /repos/:owner/:repo/contents/:path",
                 owner = user,
                 repo = repo,
                 path = path_references_bib)
        
        reference_bibtex_base64 <- 
          paste(get_bib$content %>% 
                  openssl::base64_decode(text = .) %>% 
                  rawToChar(), 
                target_article,
                sep = "\n") %>% 
          openssl::base64_encode(bin = .)
        
        gh::gh("PUT /repos/:owner/:repo/contents/:path",
               owner = user,
               repo = repo,
               path = path_references_bib,
               content = reference_bibtex_base64,
               message = glue::glue("Update crossref citations by #{number}",
                              number = event_json$issue$number),
               sha = get_bib$sha)
        
      } else {
        reference_bibtex_base64 <-
          openssl::base64_encode(paste0(target_article, "\n"))
        
        gh::gh("PUT /repos/:owner/:repo/contents/:path",
               owner = user,
               repo = repo,
               path = path_references_bib,
               content = reference_bibtex_base64,
               message = glue::glue("Add crossref citations by #{number}",
                              number = event_json$issue$number))
        
      }  
    }
  }
}
