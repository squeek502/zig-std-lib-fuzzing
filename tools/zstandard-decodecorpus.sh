#!/usr/bin/env bash

# Usage:
# ./tools/zstandard-decodecorpus.sh /path/to/decodecorpus /path/to/zstandard-verify

if [[ "$1" == "" || "$2" == "" ]]; then
  echo "First argument should be path to 'decodecorpus' exe, second argument should be path to 'zstandard-verify' exe"
fi

set -eo pipefail

tmpdir_root=$(mktemp -d)
tmpdir_input_zst="${tmpdir_root}/input.zst"
tmpdir_input_orig="${tmpdir_root}/input.orig"
tmpdir_log="${tmpdir_root}/output.log"
results_dir="outputs/zstandard-corpus-test"

echo "${tmpdir_root}"
echo "${tmpdir_input_zst}"
echo "${tmpdir_input_orig}"

iterations=0

while true
do
  printf "seed=%s\r" "${iterations}"

  "$1" -p"${tmpdir_input_zst}" -o"${tmpdir_input_orig}" -s${iterations} >/dev/null 2>&1

  "$2" "${tmpdir_input_zst}" "${tmpdir_input_orig}" >"${tmpdir_log}" 2>&1 &
  pid=$!

  wait $pid || {
    exit_code=$?
    curtime=$(date +%s%3N)
    echo "Found a problem with seed=$iterations (exit code $exit_code), putting results in ${results_dir}/$curtime. To reproduce, use the command:"
    echo "\"$2\" \"${results_dir}/$curtime/input.zst\" \"${results_dir}/$curtime/input.orig\""
    mkdir -p "${results_dir}/$curtime"
    mv "${tmpdir_input_zst}" "${results_dir}/$curtime"
    mv "${tmpdir_input_orig}" "${results_dir}/$curtime"
    mv "${tmpdir_log}" "${results_dir}/$curtime"
  }

  iterations=$((iterations+1))
done
