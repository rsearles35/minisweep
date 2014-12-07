#!/bin/bash -l
#==============================================================================
# Run tests on the code.
#==============================================================================

set -eu

declare g_ntest=0
declare g_ntest_passed=0
declare g_verbose=1

#==============================================================================
# Run the executable once.
#==============================================================================
function perform_run
{
  local exec_config_args="$(echo "$1" | tr '\n' ' ')"
  local application_args="$(echo "$2" | tr '\n' ' ')"

  if [ "${PBS_NP:-}" != "" -a "${CRAY_MPICH2_ROOTDIR:-}" != "" ] ; then
    #---If running on Cray, must cd to Lustre to make the aprun work.
    local wd="$PWD"
    pushd "$MEMBERWORK" >/dev/null
    aprun $exec_config_args "$wd/sweep.x" $application_args
    #assert $? = 0
    popd >/dev/null
  else
    #assert $exec_config_args = "-n1"
    ./sweep.x $application_args
    #assert $? = 0
  fi

}
#==============================================================================

#==============================================================================
# Compare the output of two runs for match.
#==============================================================================
function compare_runs
{
  local exec_config_args1="$(echo "$1" | tr '\n' ' ')"
  local exec_config_args2="$(echo "$3" | tr '\n' ' ')"

  local application_args1="$(echo "$2" | tr '\n' ' ')"
  local application_args2="$(echo "$4" | tr '\n' ' ')"

  local is_pass
  local is_pass1
  local is_pass2
  local normsq1
  local normsq2
  local time1
  local time2

  g_ntest=$(( $g_ntest + 1 ))

  #---Run 1.

  echo -n "$g_ntest // $exec_config_args1 / $application_args1 / "
  local result1="$( perform_run "$exec_config_args1" "$application_args1" )"
  normsq1=$( echo "$result1" | grep '^Normsq result: ' \
                             | sed -e 's/^Normsq result: *//' -e 's/ .*//' )
  time1=$(   echo "$result1" | grep '^Normsq result: ' \
                             | sed -e 's/.* time: *//' -e 's/ .*//' )
  echo -n "$time1 // "
  is_pass1=$([ "$result1" != "${result1/ PASS }" ] && echo 1 || echo 0 )
  [[ g_verbose -ge 2 ]] && echo "$result1"

  #---Run 2.

  echo -n "$exec_config_args2 / $application_args2 / "
  local result2="$( perform_run "$exec_config_args2" "$application_args2" )"
  normsq2=$( echo "$result2" | grep '^Normsq result: ' \
                             | sed -e 's/^Normsq result: *//' -e 's/ .*//' )
  time2=$(   echo "$result2" | grep '^Normsq result: ' \
                             | sed -e 's/.* time: *//' -e 's/ .*//' )
  echo -n "$time2 // "
  is_pass2=$([ "$result2" != "${result2/ PASS }" ] && echo 1 || echo 0 )
  [[ g_verbose -ge 2 ]] && echo "$result2"

  #---Final test of success.

  # Check whether each run passed and whether the results match each other.

  is_pass=$([ "$normsq1" = "$normsq2" ] && echo 1 || echo 0 )

  if [ $is_pass1 = 1 -a $is_pass2 = 1 -a $is_pass = 1 ] ; then
    echo "PASS"
    g_ntest_passed=$(( $g_ntest_passed + 1 ))
  else
    echo "FAIL"
    echo "$result1"
    echo "$result2"
  fi
}
#==============================================================================

#==============================================================================
# Initialize build/execution environment.
#==============================================================================
function initialize
{
  if [ "$PE_ENV" = "PGI" ] ; then
    module swap PrgEnv-pgi PrgEnv-gnu
  fi
  module load cudatoolkit

  if [ "$PE_ENV" != "GNU" ] ; then
    echo "Error: GNU compiler required." 1>&2
    exit 1
  fi
}
#==============================================================================

#==============================================================================
function main
{
  initialize

  #---args to use below:
  #---  nx ny nz ne nm na numiterations nproc_x nproc_y nblock_z 

  #==============================
  # MPI + CUDA.
  #==============================

  if [ "${PBS_NP:-}" != "" -a "$PBS_NP" -ge 4 ] ; then

    echo "--------------------------------------------------------"
    echo "---MPI + CUDA tests---"
    echo "--------------------------------------------------------"

    make CUDA_OPTION=1 NM_VALUE=4

    local ARGS="--nx 3 --ny 5 --nz 6 --ne 2 --na 5 --nblock_z 2"

    for nproc_x in 1 2 ; do
    for nproc_y in 1 2 ; do
    for nthread_octant in 1 2 4 8 ; do
      compare_runs \
        "-n1" \
        "$ARGS" \
        "-n$(( $nproc_x * $nproc_y ))" \
        "$ARGS --is_using_device 1 --nproc_x $nproc_x --nproc_y $nproc_y \
               --nthread_e 3 --nthread_octant $nthread_octant"
    done
    done
    done

  fi #---PBS_NP

  #==============================
  # CUDA.
  #==============================

  if [ "${PBS_NP:-}" != "" ] ; then

    echo "--------------------------------------------------------"
    echo "---CUDA tests---"
    echo "--------------------------------------------------------"

    make CUDA_OPTION=1 NM_VALUE=4

    local ARGS="--nx  2 --ny  3 --nz  4 --ne 20 --na 5 --nblock_z 2"

    for nthread_octant in 1 2 4 8 ; do
      compare_runs \
        "-n1"  "$ARGS " \
        "-n1"  "$ARGS --is_using_device 1 --nthread_e 1 \
                      --nthread_octant $nthread_octant"
    done

    for nthread_e in 2 10 20 ; do
      compare_runs \
        "-n1"  "$ARGS " \
        "-n1"  "$ARGS --is_using_device 1 --nthread_e $nthread_e \
                      --nthread_octant 8"
    done

  fi #---PBS_NP

  #==============================
  # MPI.
  #==============================

  if [ "${PBS_NP:-}" != "" ] ; then

    echo "--------------------------------------------------------"
    echo "---MPI tests---"
    echo "--------------------------------------------------------"

    make NM_VALUE=4

    local ARGS="--nx  5 --ny  4 --nz  5 --ne 7 --na 10"
    compare_runs   "-n1"  "$ARGS --nproc_x 1 --nproc_y 1 --nblock_z 1" \
                   "-n2"  "$ARGS --nproc_x 2 --nproc_y 1 --nblock_z 1"
    compare_runs   "-n1"  "$ARGS --nproc_x 1 --nproc_y 1 --nblock_z 1" \
                   "-n2"  "$ARGS --nproc_x 1 --nproc_y 2 --nblock_z 1"

    local ARGS="--nx  5 --ny  4 --nz  6 --ne 7 --na 10"
    compare_runs   "-n1"  "$ARGS --nproc_x 1 --nproc_y 1 --nblock_z 1" \
                  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 2"
    local ARGS="--nx  5 --ny  4 --nz  6 --ne 7 --na 10 --is_face_comm_async 0"
    compare_runs   "-n1"  "$ARGS --nproc_x 1 --nproc_y 1 --nblock_z 1" \
                  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 2"

    make NM_VALUE=1

    local ARGS="--nx 5 --ny 8 --nz 16 --ne 9 --na 12"
    compare_runs  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 1" \
                  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 2"
    compare_runs  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 2" \
                  "-n16"  "$ARGS --nproc_x 4 --nproc_y 4 --nblock_z 4"

  fi #---PBS_NP

  #==============================
  # OpenMP
  #==============================

  if [ "${PBS_NP:-}" != "" ] ; then

    echo "--------------------------------------------------------"
    echo "---OpenMP tests---"
    echo "--------------------------------------------------------"

    make OPENMP_OPTION=THREADS NM_VALUE=4

    local ARGS="--nx  5 --ny  4 --nz  5 --ne 200 --na 10"
    compare_runs   "-n1 -d1"  "$ARGS --nthread_e 1" \
                   "-n1 -d2"  "$ARGS --nthread_e 2"
    compare_runs   "-n1 -d2"  "$ARGS --nthread_e 2" \
                   "-n1 -d3"  "$ARGS --nthread_e 3"
    compare_runs   "-n1 -d3"  "$ARGS --nthread_e 3" \
                   "-n1 -d4"  "$ARGS --nthread_e 4"

    compare_runs   "-n1 -d1"  "$ARGS --nthread_octant 1" \
                   "-n1 -d2"  "$ARGS --nthread_octant 2"
    compare_runs   "-n1 -d2"  "$ARGS --nthread_octant 2" \
                   "-n1 -d4"  "$ARGS --nthread_octant 4"
    compare_runs   "-n1 -d4"  "$ARGS --nthread_octant 4" \
                   "-n1 -d8"  "$ARGS --nthread_octant 8"

    compare_runs   "-n1 -d1"  "$ARGS --nthread_e 1 --nthread_octant 1" \
                   "-n1 -d2"  "$ARGS --nthread_e 2 --nthread_octant 1"
    compare_runs   "-n1 -d2"  "$ARGS --nthread_e 2 --nthread_octant 1" \
                   "-n1 -d4"  "$ARGS --nthread_e 2 --nthread_octant 2"

  fi #---PBS_NP

  #==============================
  # Variants.
  #==============================

  echo "--------------------------------------------------------"
  echo "---Tests of sweeper variants---"
  echo "--------------------------------------------------------"

  local alg_options

  for alg_options in -DSWEEPER_KBA -DSWEEPER_SIMPLE -DSWEEPER_TILEOCTANTS ; do

    make MPI_OPTION= ALG_OPTIONS="$alg_options" NM_VALUE=16

    if [ $alg_options = "-DSWEEPER_KBA" ] ; then
      local ARG_NBLOCK_Z_1="--nblock_z 1"
      local ARG_NBLOCK_Z_5="--nblock_z 5"
    else
      local ARG_NBLOCK_Z_1=""
      local ARG_NBLOCK_Z_5=""
    fi

    local ARGS="--nx  5 --ny  5 --nz  5 --ne 10 --na 20"
    compare_runs  "-n1" "$ARGS --niterations 1 $ARG_NBLOCK_Z_1" \
                  "-n1" "$ARGS --niterations 2 $ARG_NBLOCK_Z_1"
    compare_runs  "-n1" "$ARGS --niterations 1 $ARG_NBLOCK_Z_1" \
                  "-n1" "$ARGS --niterations 1 $ARG_NBLOCK_Z_5"

  done #---alg_options

  #==============================
  # Finalize.
  #==============================

  echo -n "Total tests $g_ntest"
  echo -n "    "
  echo -n "PASSED $g_ntest_passed"
  echo -n "    "
  echo -n "FAILED $(( $g_ntest - $g_ntest_passed ))"
  echo "."

}
#==============================================================================

time main

#==============================================================================