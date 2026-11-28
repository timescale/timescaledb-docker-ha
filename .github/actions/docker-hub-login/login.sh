#!/usr/bin/env bash
set -uo pipefail

: "${DOCKER_HUB_TOKEN:?DOCKER_HUB_TOKEN must be set}"
: "${ATTEMPTS:?ATTEMPTS must be set}"

if [[ ! "${ATTEMPTS}" =~ ^[1-9][0-9]*$ ]]; then
    echo >&2 "attempts must be a positive integer, not '${ATTEMPTS}'"
    exit 1
fi

delay=15
for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    if output=$(docker login --username timescale --password-stdin <<<"${DOCKER_HUB_TOKEN}" 2>&1); then
        echo "${output}"
        exit 0
    fi
    echo >&2 "${output}"

    # Another attempt cannot fix a wrong or expired token.
    if grep -qiE 'unauthorized|incorrect username or password' <<<"${output}"; then
        exit 1
    fi

    if ((attempt < ATTEMPTS)); then
        echo >&2 "Docker Hub login attempt ${attempt} of ${ATTEMPTS} failed. Next attempt in ${delay} s."
        sleep "${delay}"
        delay=$((delay * 2 > 120 ? 120 : delay * 2))
    fi
done

exit 1
