#!/usr/bin/env bash
#
# Helper functions used by ctl scripts
#
set -e # exit immediately if a simple command exits with a non-zero status
set -u # report the usage of uninitialized variables

# Python dlopen does not pay attention to LD_LIBRARY_PATH, so
# ctypes.util.find_library is not able to find dyn libs, the only
# way to do is by defining the folders in ldconfig
function ldconf {
  local path=$1
  echo "$path" | tr ':' '\n' > $TMP_DIR/ld.so.conf
  ldconfig -f $TMP_DIR/ld.so.conf
  rm -f $TMP_DIR/ld.so.conf
}

function get_logfile {
  echo "/var/vcap/sys/log/${NAME}/${COMPONENT:-$NAME}_ctl.log"
}

# Log some info to the Monit Log file
function log {
  local message=${1}
  local timestamp=`date +%y:%m:%d-%H:%M:%S`
  echo "${timestamp} :: ${message}" >> "$(get_logfile)"
}

# Print a message
function echo_log {
  local message=${1}
  local timestamp=`date +%y:%m:%d-%H:%M:%S`
  echo "${timestamp} :: ${message}" | tee -a "$(get_logfile)"
}

# Print a message without \n at the end
function echon_log {
  local message=${1}
  local timestamp=`date +%y:%m:%d-%H:%M:%S`
  echo -n "${timestamp} :: ${message}" | tee -a "$(get_logfile)"
}

# Print a message and exit with error
function die {
  echo_log "$@"
  exit 1
}

# If loaded within monit ctl scripts then pipe output
# If loaded from 'source ../utils.sh' then normal STDOUT
function redirect_output {
  mkdir -p /var/vcap/sys/log/monit
  exec 1>> /var/vcap/sys/log/monit/$NAME.log
  exec 2>> /var/vcap/sys/log/monit/$NAME.err.log
}


function pid_guard {
  local pidfile=$1
  local name=$2

  if [ -f "$pidfile" ]; then
    pid=$(head -1 "$pidfile")
    if [ -n "$pid" ] && [ -e /proc/$pid ]; then
      die "$name is already running, please stop it first"
    fi
    echo_log "Removing stale pidfile ..."
    rm $pidfile
  fi
}


function wait_pid {
  local pid=$1
  local try_kill=$2
  local timeout=${3:-0}
  local force=${4:-0}
  local countdown=$(( $timeout * 10 ))

  if [ -e /proc/$pid ]; then
    if [ "$try_kill" = "1" ]; then
      echon_log "Killing $pidfile: $pid "
      kill $pid
    fi
    while [ -e /proc/$pid ]; do
      sleep 0.1
      [ "$countdown" != '0' -a $(( $countdown % 10 )) = '0' ] && echo -n .
      if [ $timeout -gt 0 ]; then
        if [ $countdown -eq 0 ]; then
          if [ "$force" = "1" ]; then
            echo
            echo_log "Kill timed out, using kill -9 on $pid ..."
            kill -9 $pid
            sleep 0.5
          fi
          break
        else
          countdown=$(( $countdown - 1 ))
        fi
      fi
    done
    if [ -e /proc/$pid ]; then
      echo_log "Timed Out"
    else
      echo_log "Stopped"
    fi
  else
    echo_log "Process $pid is not running"
  fi
}


function wait_pidfile {
  local pidfile=$1
  local try_kill=$2
  local timeout=${3:-0}
  local force=${4:-0}
  local countdown=$(( $timeout * 10 ))

  if [ -f "$pidfile" ]; then
    pid=$(head -1 "$pidfile")
    if [ -z "$pid" ]; then
      die "Unable to get pid from $pidfile"
    fi
    wait_pid $pid $try_kill $timeout $force
    rm -f $pidfile
  else
    echo_log "Pidfile $pidfile doesn't exist"
  fi
}


function kill_and_wait {
  local pidfile=$1
  # Monit default timeout for start/stop is 30s
  # Append 'with timeout {n} seconds' to monit start/stop program configs
  local timeout=${2:-25}
  local force=${3:-1}
  
  if [ -f "${pidfile}" ]; then
    wait_pidfile $pidfile 1 $timeout $force
  else
    # TODO assume $1 is something to grep from 'ps ax'
    pid="$(ps auwwx | grep "$1" | awk '{print $2}')"
    wait_pid $pid 1 $timeout $force
  fi
}

function check_nfs_mounted {
  local mount_point=$1
  grep -qs "${mountpoint}" /proc/mounts | grep -qs "nfs"
}


function mount_nfs {
  local nfsvolune=$1
  local mountpoint=$2
  local nfsversion=${3:-nfs}

  if ! check_nfs_mounted "${mountpoint}" ; then
    echo "Preparing NFS configurations ..."
    cp -f /etc/default/nfs-common /etc/default/nfs-common.orig
    cp -f "${JOB_DIR}/config/nfs-common" /etc/default/nfs-common
    cp -f "${JOB_DIR}/config/idmapd.conf" /etc/idmapd.conf
    service idmapd restart
    unmount_nfs "${mountpoint}"

    echo "Mounting NFS ${nfsvolune} at ${mountpoint} ..."
    mkdir -p "${mountpoint}"
    if ! mount --verbose -o intr,lookupcache=positive,soft -t "${nfsversion}" "${nfsvolune}" "${mountpoint}" ; then
      die "Cannot mount NFS, exiting ..."
    fi

    echo "Checking if it is writable ..."
    chpst -u vcap:vcap mkdir -p "${mountpoint}/shared"
    chpst -u vcap:vcap touch "${mountpoint}/shared/.nfs_test"
    if [ $? != 0 ]; then
      die "Failed to start: cannot write to NFS"
    fi
  fi
  echo "NFS mounted"
}


function unmount_nfs {
  local mount_point=$1

  if check_nfs_mounted "${mountpoint}" ; then
    echo "Found NFS mount, unmounting ..."
    if ! umount "${mountpoint}" ; then
      die "Failed to unmount NFS, exiting ..."
    fi
  fi
  echo "NFS unmounted"
}