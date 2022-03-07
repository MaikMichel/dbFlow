#!/bin/bash
# echo "Your script args ($#) are: $@"

depth=$1

for d in $(find apex -maxdepth ${depth} -mindepth ${depth} -type d)
do
  #Do something, the directory is accessible with $d:
  echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
done

for d in $(find rest -maxdepth ${depth} -mindepth ${depth} -type d)
do
  #Do something, the directory is accessible with $d:
  echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
done

for d in $(find db -not -path 'db/_setup*/*'  -type d)
do
  #Do something, the directory is accessible with $d:
  if [[ $d != "db/_setup" ]]; then
    echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
  fi
done

for d in $(find .hooks -type d)
do
  #Do something, the directory is accessible with $d:
  echo "Prompt EXECUTING: $d/install.sql" > $d/install.sql
done