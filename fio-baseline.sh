#!/bin/bash

fio_cmd=fio
my_dir="$( cd "$( dirname "$0"  )" && pwd  )"
# put device name here to run fio test for 
# multiple disks in parallel
# example disks=(nvme0n1 nvme1n1 nvme2n1 nvme3n1)

# replace actual disk names in blow line to start test 
# this is to avoid wiping out data on nvme0n1 accidentally 
# disks=(nvme0n1 nvme1n1)
disks=($@)

if [ ${#disks[@]} -eq 0 ]
then
    echo -e "usage:\n  单盘测试: $0 nvme0n1\n  多盘测试: $0 nvme0n1 nvme1n1 nvme2n1"
    exit
fi

if [ '${disks[@]}' == 'disk_name' ]
then
    echo "please change this line [disks=(disk_name)] to the disks being tested"
    exit 1
fi

# fio workloads
workloads=( \
    precond_seq \
    seqwrite \
    seqread \
    randwrite \
    randrw73 \
    randrw55 \
    randrw37 \
    randread \
    randread_8job_256qd \
    )

which ${fio_cmd} > /dev/null 2>&1
if [ $? -ne 0 ]; then echo "not able to locate fio command, please define \"fio_cmd\" pointing to fio path in this script"; exit 1; fi

# below numbers controls the fio workload run time.
# they does not affect the time used for pre-condition
# workloads, like precond_seq and precond_rand
export ramp_time=${ramp_time-60}
export ramp_time_randwrite=${ramp_time_randwrite-60}
export runtime=${runtime-600}

timestamp=`date +%Y%m%d_%H%M%S`
output_dir=${my_dir}/${timestamp}

if [ ! -d "${output_dir}" ]; then mkdir -p ${output_dir}; fi
iostat_dir=${output_dir}/iostat
result_dir=${output_dir}/result
drvinfo_dir=${output_dir}/drvinfo
iolog_dir=${output_dir}/io_logs
thermal_dir=${output_dir}/thermal
mkdir -p ${iostat_dir}
mkdir -p ${result_dir}
mkdir -p ${drvinfo_dir}
mkdir -p ${iolog_dir}
mkdir -p ${thermal_dir}

source ${my_dir}/functions

collect_sys_info > ${output_dir}/sysinfo.log

for workload in ${workloads[@]}
do
    iostat_pid_list=""
    thermal_pid_list=""
    fio_pid_list=""
    for disk in ${disks[@]};
    do
        collect_drv_info ${disk} > ${drvinfo_dir}/${disk}_${workload}_1.info
        iostat -dxmct 1 ${disk} > ${iostat_dir}/${disk}_${workload}.iostat &
        iostat_pid_list="${iostat_pid_list} $!"
        ${my_dir}/record_temp.sh /dev/${disk} ${thermal_dir}/${disk}_${workload}.thermal &
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

    for disk in ${disks[@]}
    do
        collect_drv_info ${disk} > ${drvinfo_dir}/${disk}_${workload}_2.info

        if [ ! -f ${drvinfo_dir}/${disk}.wa ]
        then
            echo "disk,workload,host_written,nand_written,WA" > ${drvinfo_dir}/${disk}.wa
        fi

        calculate_wa ${drvinfo_dir} ${disk} ${workload} >> ${drvinfo_dir}/${disk}.wa
    done
done

iostat_to_csv ${iostat_dir}

for disk in ${disks[@]}
do
    fio_to_csv ${result_dir} ${disk}
done

consolidate_summary ${result_dir} ${output_dir}