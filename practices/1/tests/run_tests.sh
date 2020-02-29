#!/bin/bash

#================================
#title      :run_tests.sh
#author     :covariancemomentum
#date       :29.02.2020 12:54
#version    :1.0
#================================

declare -i count_of_tests
count_of_tests=$(ls -d *.test | wc -w)
declare -i count_of_passed=0
command_name=$1
declare -i start_time
start_time=$(date +%s%N)

for file in *.test
do
  if [ -f "$file" ]
  then
    echo "Running test $(basename "$file" .test)"
    if [ "$("./$command_name" < "$file")" == "$(wc -w < "$file")" ]
    then
      count_of_passed+=1
    else
      echo "Test $(basename "$file" .test) failed"
    fi
  fi
done

start_time=("$(date +%s%N)"-"$start_time")/1000000
echo "Testing finished, $count_of_passed out of $count_of_tests passed. Runtime: $start_time ms"
