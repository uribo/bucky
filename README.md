BUCKY: Helpers for literature management as GitHub actions
======

![Actions Status](https://wdp9fww0r9.execute-api.us-west-2.amazonaws.com/production/badge/uribo/bucky) ![GitHub Release](https://img.shields.io/github/release/uribo/bucky.svg)

## Example

<p align="center"><b>Based on the title in the issue, buckey will obtain information on the paper that author, title, publisher etc..</b></p>

<p align="center"><img width="620" src="inst/demo.gif?raw=true"></p>

## Usage

- Create an issue that contains **paper ID** which [DOI (Digital object identifier)](https://www.doi.org/) or [ArXiv identifier](https://arxiv.org/help/arxiv_identifier) in the title and added **the `papers` label**.
    - ex) `DOI: 10.1038/d41586-018-07196-1`, `arXiv: 1802.06350`
    - Once the first issue is created, a [template](https://github.blog/2016-02-17-issue-and-pull-request-templates/) will be created in the repository that will condition the bucky's action to be executed.
- The title of the issue is changed, and the information of the literature is added.

### Using your project

Copy [sample workflow](inst/main.workflow) to `.github/main.workflow` or add exist workflow file.

![](inst/bucky_workflow.png?raw=true)

```bash
workflow "bucky_main_flow" {
  on = "issues"
  resolves = [
    "Update Article Information",
  ]
}

...

action "Update Article Information" {
  uses = "docker://uribo/bucky"
  needs = ["Has article identifier"]
  secrets = ["GITHUB_TOKEN"]
}
```


## License

This program is free software and is distributed under an [MIT License](LICENSE.md).
