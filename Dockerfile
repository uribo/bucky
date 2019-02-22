FROM uribo/bucky:latest

LABEL "com.github.actions.name"="Update Article Information"
LABEL "com.github.actions.description"="Add reference information as comment and modified a issue title"
LABEL "com.github.actions.icon"="star"
LABEL "com.github.actions.color"="red"

LABEL "repository"="https://github.com/uribo/bucky"
LABEL "homepage"="https://github.com/uribo/bucky"
LABEL "maintainer"="Shinya Uryu <suika1127@gmail.com>"

RUN set -x && \
  echo "GITHUB_PAT=${GITHUB_TOKEN}" >> /usr/local/lib/R/etc/Renviron

ADD article_issue_update.R /article_issue_update.R
CMD ["Rscript", "/article_issue_update.R"]
