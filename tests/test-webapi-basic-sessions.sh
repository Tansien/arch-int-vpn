#!/bin/bash

set -euo pipefail

image="${1:?usage: $0 IMAGE}"
container="qbit-basic-auth-$$"
trap 'docker rm -f "${container}" >/dev/null 2>&1 || true' EXIT

docker run -d --name "${container}" --network none --cap-drop ALL \
    --security-opt no-new-privileges:true --entrypoint /usr/bin/qbittorrent-nox "${image}" \
    --confirm-legal-notice --profile=/tmp/qbt-profile --webui-port=18080 >/dev/null

password=""
for _ in {1..60}; do
    password="$(docker logs "${container}" 2>&1 | sed -n 's/.*temporary password is provided for this session: //p' | tail -1)"
    [[ -n "${password}" ]] && break
    sleep 1
done
test -n "${password}"

login_response="$(docker exec "${container}" curl --silent --show-error --include \
    --data-urlencode 'username=admin' --data-urlencode "password=${password}" \
    http://127.0.0.1:18080/api/v2/auth/login)"
grep -q '^HTTP/1.1 200' <<< "${login_response}"
test "${login_response##*$'\r\n\r\n'}" = "Ok."
session_cookie="$(sed -n 's/^set-cookie: \([^;]*\).*/\1/p' <<< "${login_response}")"
test -n "${session_cookie}"
docker exec "${container}" curl --fail --silent --show-error \
    --cookie "${session_cookie}" http://127.0.0.1:18080/api/v2/app/version >/dev/null

failed_login_status="$(docker exec "${container}" curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --data-urlencode 'username=admin' --data-urlencode 'password=wrong' \
    http://127.0.0.1:18080/api/v2/auth/login)"
test "${failed_login_status}" = 401

logout_status="$(docker exec "${container}" curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --request POST --cookie "${session_cookie}" \
    http://127.0.0.1:18080/api/v2/auth/logout)"
[[ "${logout_status}" == 200 || "${logout_status}" == 204 ]]
expired_cookie_status="$(docker exec "${container}" curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --cookie "${session_cookie}" \
    http://127.0.0.1:18080/api/v2/app/version)"
test "${expired_cookie_status}" = 403

request_sync() {
    docker exec "${container}" curl --fail --silent --show-error \
        --user "admin:${password}" --user-agent "${1}" \
        "http://127.0.0.1:18080/api/v2/sync/maindata?rid=${2}"
}

a1="$(request_sync client-a 0)"
a2="$(request_sync client-a "$(jq -er .rid <<< "${a1}")")"
request_sync client-b 0 | jq -e '.full_update == true' >/dev/null
a3="$(request_sync client-a "$(jq -er .rid <<< "${a2}")")"
reused_basic_headers="$(docker exec "${container}" curl --fail --silent --show-error \
    --dump-header - --output /dev/null --user "admin:${password}" --user-agent client-a \
    "http://127.0.0.1:18080/api/v2/sync/maindata?rid=$(jq -er .rid <<< "${a3}")")"

jq -e '.full_update != true' <<< "${a2}" >/dev/null
jq -e '.full_update != true' <<< "${a3}" >/dev/null
grep -qi '^set-cookie: QBT_SID_' <<< "${reused_basic_headers}"

echo "WebAPI authentication compatibility test passed"
