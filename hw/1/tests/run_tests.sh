#!/bin/bash

#================================
#title      :run_tests.sh
#author     :covariancemomentum
#date       :26.03.2020 12:22
#version    :1.0
#================================

command_name=$1
declare -i count_of_passed=0
tar -xvzf "$2_tests.tar.gz" 1>/dev/null 2>/dev/null
for file in *.test
do
  if [ -f "$file" ]
  then
    echo "Running test $(basename "$file" .test)"
    ans=$(cat "$(basename "$file" .test).ans")
    if [ "$(./"$command_name" < "$file")" == "$ans" ]
    then
      count_of_passed+=1
    else
      echo "Test $(basename "$file" .test) failed:"
      echo "Expected: " "$ans"
      echo "Got: $("./$command_name" < "$file")"
      exit
    fi
  fi
done

echo "Passed" "$count_of_passed" "tests"
rm ./*.ans
rm ./*.test