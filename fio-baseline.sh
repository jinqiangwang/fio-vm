#!/bin/bash

my_dir="$( cd "$( dirname "$0"  )" && pwd  )"
# put device name here to run fio test for 
# multiple disks in parallel
# example disks=(nvme0n1 nvme1n1 nvme2n1 nvme3n1)
disks=(nvme0n1)

# fio workloads
workloads=( \
    precond_seq.fio \
    seqwrite \
    seqread \
    randwrite \
    randrw73 \
    randrw55 \
    randrw37 \
    randread \
    )

# below numbers controls the fio workload run time.
# they does not affect the time used for pre-condition
# workloads, like precond_seq and precond_rand
export ramp_time=${ramp_time-60}
export runtime=${runtime-1800}

timestamp=`date +%Y%m%d_%H%M%S`
output_dir=${my_dir}/${timestamp}

if [ ! -d "${output_dir}" ]; then mkdir -p ${output_dir}; fi
iostat_dir=${output_dir}/iostat
result_dir=${output_dir}/result
drvinfo_dir=${output_dir}/drvinfo
thermal_dir=${output_dir}/thermal
mkdir -p ${iostat_dir}
mkdir -p ${result_dir}
mkdir -p ${drvinfo_dir}
mkdir -p ${thermal_dir}

source ${my_dir}/functions

collect_sys_info > ${output_dir}/sysinfo.log

for disk in ${disks[@]}
do
    collect_drv_info ${disk} > ${drvinfo_dir}/${disk}_1.info
done

for workload in ${workloads[@]}
do
    iostat_pid_list=""
    thermal_pid_list=""
    fio_pid_list=""
    for disk in ${disks[@]};
    do
        iostat -dxmct 1 ${disk} > ${iostat_dir}/${disk}_${workload}.iostat &
        iostat_pid_list="${iostat_pid_list} $!"
        ${my_dir}/record_thermal.sh /dev/${disk} ${thermal_dir}/${disk}_${workload}.thermal &
        thermal_pid_list="${thermal_pid_list} $!"

        fio --filename=/dev/${disk} \
            --output=${result_dir}/${disk}_${workload}.fio \
            ${my_dir}/jobs/${workload}.fio &
        fio_pid_list="${fio_pid_list} $!"
    done

    wait ${fio_pid_list}
    sync
    kill -9 ${thermal_pid_list}
    kill -9 ${iostat_pid_list}
done

for disk in ${disks[@]}
do
    collect_drv_info ${disk} > ${drvinfo_dir}/${disk}_2.info
done

iostat_to_csv ${iostat_dir} ${disk}
for disk in ${disks[@]}
do
    fio_to_csv ${result_dir} ${disk}
done
consolidate_summary ${result_dir} ${output_dir}