#!/bin/bash
mydir="$( cd "$( dirname "$0"  )" && pwd  )"
dev_name=$1
output_file=$2
interval=30

if [ ! -b ${dev_name} ]; then echo "device [${dev_name}] does not exist"; fi
if [ "${output_file}" == "" ]; then output_dir=./${dev_name}.thermal; fi


source ${mydir}/functions
while ((1==1))
do
    collect_temperature ${dev_name} >> ${output_file}
    sleep ${interval}
done