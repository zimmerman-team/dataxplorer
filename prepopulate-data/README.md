# Prepopulate Data

This folder holds public assets data to be populated for guest users.

## Generate

Export the public (baseline) data from your local DX with `make script name=export-baseline` ([export-baseline.sh](../scripts/export-baseline.sh)). It needs `jq`.

## Populate

Load the data into an environment with `make seed ENV=<env>` ([prepopulate.sh](../scripts/prepopulate.sh)).
