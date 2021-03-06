#!/bin/sh
# This wrapper script is intended to be submitted to SLURM to support
# communicating jobs.
#
# This script uses the following environment variables set by the submit MATLAB code:
# MDCE_CMR            - the value of ClusterMatlabRoot (may be empty)
# MDCE_MATLAB_EXE     - the MATLAB executable to use
# MDCE_MATLAB_ARGS    - the MATLAB args to use
#
# The following environment variables are forwarded through mpiexec:
# MDCE_DECODE_FUNCTION     - the decode function to use
# MDCE_STORAGE_LOCATION    - used by decode function
# MDCE_STORAGE_CONSTRUCTOR - used by decode function
# MDCE_JOB_LOCATION        - used by decode function

# Copyright 2006-2012 The MathWorks, Inc.

# Create full paths to mw_smpd/mw_mpiexec if needed
FULL_SMPD=${MDCE_CMR:+${MDCE_CMR}/bin/}mw_smpd
FULL_MPIEXEC=${MDCE_CMR:+${MDCE_CMR}/bin/}mw_mpiexec
SMPD_LAUNCHED_HOSTS=""
MPIEXEC_CODE=0
###################################
## CUSTOMIZATION MAY BE REQUIRED ##
###################################
# This script assumes that SSH is set up to work without passwords between
# all nodes on the cluster.
# You may wish to modify SSH_COMMAND to include any additional ssh options that
# you require.
SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# manipulateHosts carries out the functions of both chooseSmpdHosts and
# chooseMachineArg - it is convenient to calculate both properties together
# since they both involve parsing the SLURM_JOB_NODELIST and
# SLURM_TASKS_PER_NODE environment variables as set by SLURM.
manipulateHosts() {
    # Make sure we don't execute the body of this function more than once
    if [ "${SMPD_HOSTS:-UNSET}" = "UNSET" ]
        then
        echo "Calculating SMPD_HOSTS and MACHINE_ARG"

        # SLURM_JOB_NODELIST is an ranged string of hostnames, we need to pick
        # out just the names for the SMPD_HOSTS argument, and also count the
        # number of different tasks per host for mpiexec's "-hosts" argument.
        SMPD_HOSTS=""

        HOSTS=$(scontrol show hostnames ${SLURM_JOB_NODELIST})
        TASKPN=$(echo ${SLURM_TASKS_PER_NODE} | tr "," "\n")

        i=0
        for e in ${TASKPN}
          do
          if echo ${e} | grep -q "x" ; then
            TASK=`echo ${e} | sed 's/\([0-9]\)*(.*)/\1/'`
            NODE=`echo ${e} | sed 's/.*(x\([0-9]*\))/\1/'`
            a=0
            while [ $a -lt ${NODE} ]
            do
              NTASK[$i]="${TASK}"
              a=`expr $a + 1`
              i=`expr $i + 1`
            done
          else
            NTASK[$i]="${e}"
          fi
          i=`expr $i + 1`
        done
        i=0
        for x in ${HOSTS}
          do
            SMPD_HOSTS[$i]="${x}"
            HOSTLIST[$i]="${x} ${NTASK[$i]}"
            i=`expr $i + 1`
        done

        SMPD_HOSTS="${SMPD_LAUNCHED_HOSTS[*]}"
        HOSTLIST="${HOSTLIST[*]}"

        MACHINE_ARG="-hosts ${SLURM_JOB_NUM_NODES} ${HOSTLIST}"
    fi
}


# Work out where we need to launch SMPDs given our hosts file - defines
# SMPD_HOSTS
chooseSmpdHosts() {
    manipulateHosts
}

# Work out which port to use for SMPD
chooseSmpdPort() {
    # Use SLURM's SLURM_JOBID to calculate the port
    SMPD_PORT=`expr ${SLURM_JOBID} % 10000 + 20000`
}

# Work out how many processes to launch - set MACHINE_ARG
chooseMachineArg() {
    manipulateHosts
}

# Now that we have launched the SMPDs, we must install a trap to ensure that
# they are closed either in the case of normal exit, or job cancellation:
# Default value of the return code
cleanupAndExit() {
    echo ""
    echo "Stopping SMPD on ${SMPD_LAUNCHED_HOSTS} ..."
    for host in ${SMPD_LAUNCHED_HOSTS}
    do
        echo /usr/bin/srun \"${FULL_SMPD}\" -shutdown -phrase MATLAB -port ${SMPD_PORT}
        /usr/bin/srun \"${FULL_SMPD}\" -shutdown -phrase MATLAB -port ${SMPD_PORT}
    done
    echo "Exiting with code: ${MPIEXEC_CODE}"
    exit ${MPIEXEC_CODE}
}

# Use ssh to launch the SMPD daemons on each processor
launchSmpds() {
    # Launch the SMPD processes on all hosts using SSH
    echo "Starting SMPD on ${SMPD_HOSTS} ..."
    for host in ${SMPD_HOSTS}
      do
      echo /usr/bin/srun \"${FULL_SMPD}\" -s -phrase MATLAB -port ${SMPD_PORT}
      /usr/bin/srun \"${FULL_SMPD}\" -s -phrase MATLAB -port ${SMPD_PORT}
      ssh_return=${?}
      if [ ${ssh_return} -ne 0 ]
          then
          echo "Launching smpd failed for node: ${host}"
          exit 1
      else
          SMPD_LAUNCHED_HOSTS="${SMPD_LAUNCHED_HOSTS} ${host}"
      fi
    done
    echo "All SMPDs launched"
}

runMpiexec() {
    # As a debug stage: echo the command line...
    echo \"${FULL_MPIEXEC}\" -phrase MATLAB -port ${SMPD_PORT} \
        -l ${MACHINE_ARG} -genvlist \
        MDCE_DECODE_FUNCTION,MDCE_STORAGE_LOCATION,MDCE_STORAGE_CONSTRUCTOR,MDCE_JOB_LOCATION,MDCE_DEBUG,MDCE_LICENSE_NUMBER,MLM_WEB_LICENSE,MLM_WEB_USER_CRED,MLM_WEB_ID \
        \"${MDCE_MATLAB_EXE}\" ${MDCE_MATLAB_ARGS}

    # ...and then execute it
    eval \"${FULL_MPIEXEC}\" -phrase MATLAB -port ${SMPD_PORT} \
        -l ${MACHINE_ARG} -genvlist \
        MDCE_DECODE_FUNCTION,MDCE_STORAGE_LOCATION,MDCE_STORAGE_CONSTRUCTOR,MDCE_JOB_LOCATION,MDCE_DEBUG,MDCE_LICENSE_NUMBER,MLM_WEB_LICENSE,MLM_WEB_USER_CRED,MLM_WEB_ID \
        \"${MDCE_MATLAB_EXE}\" ${MDCE_MATLAB_ARGS}
    MPIEXEC_CODE=${?}
}

# Define the order in which we execute the stages defined above
MAIN() {
    trap "cleanupAndExit" 0 1 2 15
    chooseSmpdHosts
    chooseSmpdPort
    launchSmpds
    chooseMachineArg
    runMpiexec
    exit ${MPIEXEC_CODE}
}

# Call the MAIN loop
MAIN
