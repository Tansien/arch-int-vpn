#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

mkdir -p "${test_dir}/run/local"
cp "${repo_root}/run/local/tools.sh" "${test_dir}/run/local/tools.sh"
patch --batch --forward -p1 -d "${test_dir}" < "${repo_root}/patches/binhex-portcheck.patch"
source "${test_dir}/run/local/tools.sh"

APPLICATION="qbittorrent"
qbittorrent_port="12345"
external_ip="192.0.2.1"
PORT_CLOSED_FILE="${test_dir}/portclosed"

check_incoming_port_webscrape() {
	INCOMING_PORT_OPEN="${WEB_OPEN}"
	INCOMING_PORT_CLOSED="${WEB_CLOSED}"
}

check_incoming_port_json() {
	INCOMING_PORT_OPEN="${JSON_OPEN}"
	INCOMING_PORT_CLOSED="${JSON_CLOSED}"
}

assert_port_state() {
	local expected_marker="${1}"
	WEB_OPEN="${2}"
	WEB_CLOSED="${3}"
	JSON_OPEN="${4}"
	JSON_CLOSED="${5}"
	rm -f "${PORT_CLOSED_FILE}"

	check_incoming_port

	if [[ "${expected_marker}" == "true" ]]; then
		test -f "${PORT_CLOSED_FILE}"
	else
		test ! -e "${PORT_CLOSED_FILE}"
	fi
}

assert_port_state false true false false false
assert_port_state false false true true false
assert_port_state true false true false true
assert_port_state false false false false false
assert_port_state false false true false false

echo "port-check state tests passed"
