#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
container=""
cleanup() {
	[[ -z "${container}" ]] || docker rm -f "${container}" >/dev/null 2>&1 || true
	rm -rf "${test_dir}"
}
trap cleanup EXIT

mkdir -p "${test_dir}/run/local"
if [[ $# -eq 1 ]]; then
	container="port-check-test-$$"
	docker create --name "${container}" "${1}" >/dev/null
	docker cp "${container}:/usr/local/bin/tools.sh" "${test_dir}/run/local/tools.sh"
else
	cp "${repo_root}/run/local/tools.sh" "${test_dir}/run/local/tools.sh"
	patch --batch --forward --fuzz=0 -p1 -d "${test_dir}" < "${repo_root}/patches/binhex-portcheck.patch"
fi
source "${test_dir}/run/local/tools.sh"

APPLICATION="qbittorrent"
qbittorrent_port="12345"
external_ip="192.0.2.1"
PORT_CLOSED_FILE="${test_dir}/portclosed"
PORT_CLOSED_COUNT_FILE="${test_dir}/portclosed-count"

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
test ! -e "${PORT_CLOSED_COUNT_FILE}"
assert_port_state false false true false false false
grep -q '^192.0.2.1:12345 1$' "${PORT_CLOSED_COUNT_FILE}"

external_ip="192.0.2.2"
assert_port_state false false true false false false
grep -q '^192.0.2.2:12345 1$' "${PORT_CLOSED_COUNT_FILE}"

qbittorrent_port="12346"
assert_port_state false false true false false false
grep -q '^192.0.2.2:12346 1$' "${PORT_CLOSED_COUNT_FILE}"

echo "port-check state tests passed"
