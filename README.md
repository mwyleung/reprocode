# REPROCODE

Version 0.1.0

reprocode is the best!

## Assumptions and expectations on data or (user) input
- Have a data frame in wide format of cohort baseline covariates including start of follow-up time (date), end of follow-up time (date), patient identifier (numeric), gender (1/2 factor), follow-up time in years (double), age group in 10-year strata (character), and stratum of calendar period of index date (character).
- Have a data frame in long format of infections recorded, containing patient identifiers (integer) that links to patient identifiers in the data frame of cohort baseline covariates, event date of the infection (date), type of infection (character), start of follow-up time (date), and end of follow-up time (date).

## Assumptions and expectations on the input of (a) function(s)

### Function to indicate whether infections were part of an ongoing episode of infection or the start of a new episode:
- Have the data frame with all infection recorded (point 2 above)
- Choose the duration of time to consider for the history of infection (time until index date) in years (integer)
- Choose the duration of one episode of infection in days (integer)

## Basic dependency information

### R version 3.6.1

### Packages
- epiR
- PropCIs
- gridExtra
- cowplot
- tableone
- epitools
- viridis
- knitr
- gridExtra
- ggplot2
- ggforce
- ggpubr
- feather
- tidyverse
- reshape2
- fakeR

### Installation instructions
    install.packages(c("epiR", "PropCIs", "gridExtra", "cowplot", "tableone", "epitools", "viridis", "knitr", "gridExtra", "ggplot2", "ggforce", "ggpubr", "feather", "tidyverse", "reshape2", "fakeR"))

## Project organization

```
.
├── .gitignore
├── CITATION.md
├── LICENSE.md
├── README.md
├── requirements.txt
├── bin                <- Compiled and external code, ignored by git (PG)
│   └── external       <- Any external source code, ignored by git (RO)
├── config             <- Configuration files (HW)
├── data               <- All project data, ignored by git
│   ├── processed      <- The final, canonical data sets for modeling. (PG)
│   ├── raw            <- The original, immutable data dump. (RO)
│   └── temp           <- Intermediate data that has been transformed. (PG)
├── docs               <- Documentation notebook for users (HW)
│   ├── manuscript     <- Manuscript source, e.g., LaTeX, Markdown, etc. (HW)
│   └── reports        <- Other project reports and notebooks (e.g. Jupyter, .Rmd) (HW)
├── results
│   ├── figures        <- Figures for the manuscript or reports (PG)
│   └── output         <- Other output for the manuscript or reports (PG)
└── src                <- Source code for this project (HW)

```


## License

This project is licensed under the terms of the [MIT License](/LICENSE.md)

## Citation

Please [cite this project as described here](/CITATION.md).
