#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
cleanup() {
	rm -rf "${test_dir}"
}
trap cleanup EXIT

mkdir -p "${test_dir}/run/local"
if [[ $# -eq 1 ]]; then
	cp "${1}" "${test_dir}/run/local/tools.sh"
else
	cp "${repo_root}/run/local/tools.sh" "${test_dir}/run/local/tools.sh"
	patch --batch --forward --fuzz=0 -p1 -d "${test_dir}" < "${repo_root}/patches/binhex-portcheck.patch"
fi
source "${test_dir}/run/local/tools.sh"

APPLICATION="qbittorrent"
DEBUG="false"
qbittorrent_port="12345"
external_ip="192.0.2.1"
PORT_CLOSED_FILE="${test_dir}/portclosed"
PORT_CLOSED_COUNT_FILE="${test_dir}/portclosed-count"

curl() {
	printf x >> "${test_dir}/curl-count"
	printf 'success on port 12345\n'
}
grep() {
	local arg
	local args=()
	for arg in "$@"; do
		[[ "${arg}" == -P ]] || args+=("${arg}")
	done
	command grep "${args[@]}"
}
check_incoming_port_webscrape test-url test-data 'success.*12345' 'error.*12345'
test "$(wc -c < "${test_dir}/curl-count")" -eq 1
test "${INCOMING_PORT_OPEN}" = true
unset -f curl grep

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
	[[ "${6:-true}" == "false" ]] || rm -f "${PORT_CLOSED_COUNT_FILE}"

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

assert_port_state false false true false false
assert_port_state false false true false false false
assert_port_state true false true false false false

assert_port_state false false true false false
assert_port_state false true false false false false
assert_port_state false false true false false false
grep -q '^192.0.2.1:12345 1$' "${PORT_CLOSED_COUNT_FILE}"

assert_port_state false false true false false
assert_port_state false false false false false false
grep -q '^192.0.2.1:12345 2$' "${PORT_CLOSED_COUNT_FILE}"
assert_port_state true false false false false false
test ! -e "${PORT_CLOSED_COUNT_FILE}"

external_ip="192.0.2.2"
assert_port_state false false true false false false
grep -q '^192.0.2.2:12345 1$' "${PORT_CLOSED_COUNT_FILE}"

qbittorrent_port="12346"
assert_port_state false false true false false false
grep -q '^192.0.2.2:12346 1$' "${PORT_CLOSED_COUNT_FILE}"

echo "port-check state tests passed"
