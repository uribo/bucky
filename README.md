BUCKY: Helpers for literature management as GitHub actions
======

## Example

<p align="center"><b>Based on the title in the issue, bucky will obtain information on the paper that author, title, publisher etc..</b></p>

<p align="center"><img width="620" src="inst/demo.gif?raw=true"></p>

## Usage

- Create an issue that contains **paper ID** which [DOI (Digital object identifier)](https://www.doi.org/) or [ArXiv identifier](https://arxiv.org/help/arxiv_identifier) in the title and added **the `papers` label**.
    - e.g. `DOI: 10.1038/d41586-018-07196-1`, `arXiv: 1802.06350`
    - Once the first issue is created, a [template](https://github.blog/2016-02-17-issue-and-pull-request-templates/) will be created in the repository that will condition the bucky's action to be executed.
- The title of the issue is changed, and the information of the literature is added.

### Using your project

Copy [`.github/workflows/article-information.yaml`](https://github.com/uribo/bucky/blob/master/.github/workflows/article-information.yaml) and [`renv.lock`](https://github.com/uribo/bucky/blob/master/renv.lock) to your repository.

## License

This program is free software and is distributed under an [MIT License](LICENSE.md).
