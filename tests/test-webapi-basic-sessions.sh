#!/bin/bash

set -euo pipefail

image="${1:?usage: $0 IMAGE}"
container="qbit-basic-auth-$$"
trap 'docker rm -f "${container}" >/dev/null 2>&1 || true' EXIT

docker run -d --name "${container}" --entrypoint /usr/bin/qbittorrent-nox "${image}" \
    --confirm-legal-notice --profile=/tmp/qbt-profile --webui-port=18080 >/dev/null

password=""
for _ in {1..60}; do
    password="$(docker logs "${container}" 2>&1 | sed -n 's/.*temporary password is provided for this session: //p' | tail -1)"
    [[ -n "${password}" ]] && break
    sleep 1
done
test -n "${password}"

request_sync() {
    docker exec "${container}" curl --fail --silent --show-error \
        --user "admin:${password}" --user-agent "${1}" \
        "http://127.0.0.1:18080/api/v2/sync/maindata?rid=${2}"
}

a1="$(request_sync client-a 0)"
a2="$(request_sync client-a "$(jq -er .rid <<< "${a1}")")"
request_sync client-b 0 | jq -e '.full_update == true' >/dev/null
a3="$(request_sync client-a "$(jq -er .rid <<< "${a2}")")"

jq -e '.full_update != true' <<< "${a2}" >/dev/null
jq -e '.full_update != true' <<< "${a3}" >/dev/null

echo "WebAPI Basic-auth session isolation test passed"
