# Studies, groups & blinding

A **study** holds the design of an experiment. RodentLimb follows what the ARRIVE 2.0 guidelines ask to be reported: the design and groups, the experimental unit (the animal), the exact n per group, inclusion and exclusion criteria set in advance, randomization and blinding. Sex is recorded for every animal, in line with the NIH policy on sex as a biological variable.

Create a study with **File › New Study…** (⇧⌘N). Edit its design later with ⇧⌘D on the study page.

## Design

- **Factors** (between subjects), each with levels, for example *Genotype: WT, KO* and *Treatment: Vehicle, Drug*. The first level is the reference (control) level.
- **Timepoints** (within subjects), for example *Baseline, Day 7, Day 14*, and trials within a timepoint.
- **Animals** with sex, batch and cage.
- **Inclusion criteria (QC)**, set before scoring. See [Quality control & inclusion](./qc.md).

## Allocation and blinding

- **Randomized allocation** to the factor levels, stratified by sex.
- **Blinding**: while a study is blinded, animals are shown by a code, groups stay hidden, and the group comparison shows only the overall distribution. Blinded exports leave out the animal ID, the group and the original file name (file names often carry the animal ID).

## Completeness

A table of animals × timepoints shows which videos are present, tracked, included and scored, so missing data are visible before you export.

## Group comparison

Choose a task, a measure, the grouping (design cells, one factor, sex, or cells × sex) and a timepoint or the time course. Bars or points show mean ± SEM per group with every animal as a dot; the time course shows a line per group with an SEM band.

- **The animal is the experimental unit**: several trials of one animal at one timepoint are averaged first, so n counts animals.
- Only included videos are used.
- The comparison is **descriptive**. For inference, use the exported long-format table, for example two-way or mixed ANOVA, or a linear mixed model with the animal as a random effect for repeated measures.

## Methods text for the design

The study export includes a design paragraph: factors and levels, n per group, timepoints, allocation, blinding, inclusion criteria and the exclusions with their reasons. See [Export](./export.md).
