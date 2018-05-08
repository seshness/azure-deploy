#!/bin/bash

set -exo pipefail

version="5.0.0"
branch="release/5.0"
directory_id="DIRECTORY_ID"
application_id="APPLICATION_ID"
secret="APPLICATION_SECRET"

tmpdir="/tmp/trifacta-deploy"

scripts="
configure-app.sh
configure-db.sh
install-app.sh
prepare-edge-node.sh
uninstall.sh
util.sh"

function Usage() {
  cat << EOF
Usage: "$0 [options]"

Options:
  -v <version>   Trifacta version [default: $version]
  -b <build>     Trifacta build number [default: $build]
  -B <branch>    Branch for deployment scripts [default: $branch]
  -s <sas>       Shared access signature for artifact download
  -d <dir ID>    Azure Active Directory directory ID for the registered application. Required when HDI default storage is ADLS. [default: $directory_id]
  -a <app ID>    Registered application\'s ID. Required. [default: $application_id]
  -S <secret>    Registered application\'s key. Required. [default: $secret]
  -h             This message
EOF
}

LogInfo()    { echo -e "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $1" ; }
LogWarning() { echo -e "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] $1" ; }
LogError()   { echo -e "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2 && exit 1; }

while getopts "v:b:B:s:d:a:S:h" opt; do
  case $opt in
    v  ) version=$OPTARG ;;
    b  ) build=$OPTARG ;;
    B  ) branch=$OPTARG ;;
    s  ) shared_access_signature=$OPTARG ;;
    d  ) directory_id=$OPTARG ;;
    a  ) application_id=$OPTARG ;;
    S  ) secret=$OPTARG ;;
    h  ) Usage && exit 0 ;;
    \? ) LogError "Invalid option: -$OPTARG" ;;
    :  ) LogError "Option -$OPTARG requires an argument." ;;
  esac
done

# If not specified, pick default build number for corresponding versions
if [[ -z ${build+x} ]]; then
  if [[ "$version" == "5.0.0" ]]; then
    build="81"
  else
    LogError "Version \"$version\" not recognized and build number not specified (via -b option)"
  fi
fi

if [[ -z ${shared_access_signature+x} ]]; then
  LogError "Shared access signature must be specified (via -s option)"
fi

base_uri="https://raw.githubusercontent.com/seshness/azure-deploy/$branch"
bindir_uri="$base_uri/bin"

function RunScript() {
  local script_name="$1"
  local script_path="$tmpdir/$script_name"
  local script_log="$tmpdir/$script_name.log"
  shift
  LogInfo "======================================================================"
  LogInfo "Script    : $script_path"
  LogInfo "Arguments : $*"
  LogInfo "Log file  : $script_log"
  LogInfo "======================================================================"
  bash "$script_path" $* 2>&1 | tee "$script_log"
}

function DeleteExistingDirectory () {
  if [[ -d "$1" ]]; then
    LogWarning "Deleting the existing directory \"$1\""
    rm -rf "$1"
  fi
}

LogInfo "============================================================"
LogInfo "Trifacta version    : $version"
LogInfo "Trifacta build      : $build"
LogInfo "Deployment branch   : $branch"
LogInfo "Tmpdir              : $tmpdir"
LogInfo "Base URI            : $base_uri"
LogInfo "Bindir URI          : $bindir_uri"
LogInfo "AAD directory ID    : $directory_id"
LogInfo "AAD application ID  : $application_id"
LogInfo "============================================================"

DeleteExistingDirectory "$tmpdir"
LogInfo "Creating temp directory \"$tmpdir\""
mkdir -p "$tmpdir"

pushd "$tmpdir" 2>&1 > /dev/null
LogInfo "Downloading scripts"
for script in $scripts; do
  wget -q "$bindir_uri/$script"
done

RunScript prepare-edge-node.sh
RunScript install-app.sh -v "$version" -b "$build" -s "$shared_access_signature"
RunScript configure-db.sh
RunScript configure-app.sh -d "$directory_id" -a "$application_id" -S "$secret"

popd 2>&1 > /dev/null
