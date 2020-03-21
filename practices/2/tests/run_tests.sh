#!/bin/bash

#================================
#title      :run_tests.sh
#author     :covariancemomentum
#date       :21.03.2020 12:22
#version    :1.0
#================================

echo "<=== Running false tests ===>"
command_name=$1
declare -i count_of_passed=0
for file in *.false
do
  if [ -f "$file" ]
  then
    echo "Running test $(basename "$file" .false)"
    word_search_name=$(cat "$(basename "$file" .false).false_query")
    args="$word_search_name $file"
    if [ "$(./"$command_name" $args)" == "false" ]
    then
      count_of_passed+=1
    else
      echo "Test $(basename "$file" .test) failed:"
      echo "Expected: false"
      echo "Got: $("./$command_name" < "$file")"
      exit
    fi
  fi
done
echo "<=== Running true tests ===>"
for file in *.true
do
  if [ -f "$file" ]
  then
    echo "Running test $(basename "$file" .true)"
    word_search_name=$(cat "$(basename "$file" .true).true_query")
    args="$word_search_name $file"
    if [ "$(./"$command_name" $args)" == "true" ]
    then
      count_of_passed+=1
    else
      echo "Test $(basename "$file" .test) failed:"
      echo "Expected: true"
      echo "Got: $(./"$command_name" $args)"
      exit
    fi
  fi
done

echo "Passed:" $count_of_passed

