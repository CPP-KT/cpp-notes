#!/bin/bash

#================================
#title      :run_tests.sh
#author     :covariancemomentum
#date       :07.03.2020 12:22
#version    :1.1
#================================

echo "<=== Running mandatory tests ===>"
command_name=$1

for file in *.test
do
  if [ -f "$file" ]
  then
    echo "Running test $(basename "$file" .test)"
    if [ "$("./$command_name" < "$file")" == "$(wc -w < "$file")" ]
    then
      count_of_passed+=1
    else
      echo "Test $(basename "$file" .test) failed:"
      echo "Expected: $(wc -w < "$file")"
      echo "Got: $("./$command_name" < "$file")"
      exit
    fi
  fi
done

echo "Mandatory testing finished. Testing time complexity "$(tar -x -v -z -f bigtest.tar.gz)""
if [ "$(chrt -f 98 perf stat ./"$command_name" < benchmarking.bigtest 2> bench.log)" == "$(wc -w < benchmarking.bigtest)" ]
then
  echo "$(grep task-clock bench.log | cut -f1 -d, | sed -e 's/^[[:space:]]*//') ms"
fi
rm benchmarking.bigtest
rm bench.log