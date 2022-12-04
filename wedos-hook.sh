#!/usr/bin/env bash

# Derived from Silke Hofstra's PDNS hook 
# https://github.com/silkeh/pdns_api.sh
#
# Daniel Farkas - 2022 
# https://github.com/mrhackcz/wedos-hook
#
# Licensed under the EUPL
#
# You may not use this work except in compliance with the Licence.
# You may obtain a copy of the Licence at:
#
# https://joinup.ec.europa.eu/collection/eupl
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the Licence is distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#

set -f
set -e
set -u
set -o pipefail

#DEBUG=1

# Local directory
DIR="$(dirname "$0")"

# Config directories
CONFIG_DIRS="/etc/dehydrated /usr/local/etc/dehydrated"

# Error handling
error() { echo -e "\033[0;31mError: $*\033[0m" >&2; }
warn() { echo -e "\033[0;33mWarning: $*\033[0m" >&2; }
fatalerror() { error "$*"; exit 1; }

# Debug message
debug() { [[ -z "${DEBUG:-}" ]] || echo -e "\033[0;36m$@\033[0m" >&2; }
debugn() { [[ -z "${DEBUG:-}" ]] || echo -e "\033[0;36m$@\033[0m\n" >&2; }

# Load the configuration and set default values
load_config () {
  # Check for config in various locations
  # From letsencrypt.sh
  if [[ -z "${CONFIG:-}" ]]; then
    for check_config in ${CONFIG_DIRS} "${PWD}" "${DIR}"; do
      if [[ -f "${check_config}/config" ]]; then
        CONFIG="${check_config}/config"
        break
      fi
    done
  fi

  # Check if config was set
  if [[ -z "${CONFIG:-}" ]]; then
    # Warn about missing config
    warn "No config file found, using default config!"
  elif [[ -f "${CONFIG}" ]]; then
    # shellcheck disable=SC1090
    . "${CONFIG}"
  fi

  if [[ -n "${CONFIG_D:-}" ]]; then
    if [[ ! -d "${CONFIG_D}" ]]; then
      fatalerror "The path ${CONFIG_D} specified for CONFIG_D does not point to a directory."
    fi

    # Allow globbing
    if [[ -n "${ZSH_VERSION:-}" ]]
    then
      set +o noglob
    else
      set +f
    fi

    for check_config_d in "${CONFIG_D}"/*.sh; do
      if [[ -f "${check_config_d}" ]] && [[ -r "${check_config_d}" ]]; then
        echo "# INFO: Using additional config file ${check_config_d}"
        # shellcheck disable=SC1090
        . "${check_config_d}"
      else
        fatalerror "Specified additional config ${check_config_d} is not readable or not a file at all."
      fi
    done

    # Disable globbing
    if [[ -n "${ZSH_VERSION:-}" ]]
    then
      set -o noglob
    else
      set -f
    fi
  fi

  # Check required settings
  [[ -n "${WAPI_LOGIN:-}" ]] || fatalerror "WAPI_LOGIN setting is required."
  [[ -n "${WAPI_PASS:-}" ]]  || fatalerror "WAPI_PASS setting is required."

  # Check optional settings
  [[ -n "${WAPI_URL:-}" ]] || WAPI_URL="https://api.wedos.com/wapi/json"
  [[ -n "${WAPI_WAIT:-}" ]] || WAPI_WAIT="600"
}

# Generate hash for every request
build_hash () {
	hour=$(date +"%H")
	wpass_hash=$(echo -n $WAPI_PASS|sha1sum|head -c 40)
	echo -n $WAPI_LOGIN$wpass_hash$hour|sha1sum|head -c 40
}

# Get all dns txt records contains ${2}
get_token_id () {
    jsonout=$(request "dns-rows-list" '{"domain":"'${1}'"}')
    echo ${jsonout} | jq -r ".response.data.row[] | select(.rdtype==\"TXT\") | select (.rdata==\"${2}\") | .ID"
}

# Send request to WAPI
request () {
    error=false

    # Debug output
    debug "# REQUEST"
    debug "command: ${1}"
    debug "data: ${2}"

    if ! res=$(curl -4 -sSfL --stderr - ${WAPI_URL} --data-urlencode 'request={ "request": { "user": "'${WAPI_LOGIN}'", "auth": "'$(build_hash)'", "command": "'${1}'", "data":'${2}'} }'); then
        error=true
    fi

    debugn "response: ${res}"

    # Abort on failed request
    if [[ "${res}" = *"error"* ]] || [[ "${error}" = true ]]; then
        fatalerror "API error: ${res}"
    fi

    # Send data back if command is dns-rows-list
    if [[ "${1}" == "dns-rows-list" ]]; then 
        echo "${res}"
    fi
}

# Add dns record
dns_row_add () {
    request "dns-row-add" '{"domain":"'${1}'","name":"'${2}'","ttl":"300","type":"TXT","rdata":"'${3}'","auth_comment":"Edited_by_dehydrated_WAPI_hook"}'
}

# Delete dns record
dns_row_delete () {
    tokens=($(get_token_id "${1}" "${2}"))

    for row_id in ${tokens[@]}; do
        request "dns-row-delete" '{"domain":"'${1}'","row_id":"'${row_id}'"}'
    done
}

# Commit dns changes
dns_domain_commit () {
    request "dns-domain-commit" '{"name":"'${1}'"}'
}

# Handle additional exit hook
exit_hook () {
  if [[ -n "${WAPI_EXIT_HOOK:-}" ]]; then
    exec ${WAPI_EXIT_HOOK}
  fi
}

# Handle additional deploy_cert hook
deploy_cert () {
  if [[ -n "${WAPI_DEPLOY_CERT_HOOK:-}" ]]; then
    exec ${WAPI_DEPLOY_CERT_HOOK}
  fi
}

main () {
    hook="${1}"

    if [[ ! "${hook}" =~ ^(deploy_challenge|clean_challenge|exit_hook|deploy_cert)$ ]]; then
        exit 0
    fi

    load_config

    # Debug output
    debug "# Main"
    debug "Bash: ${BASH_VERSION}"
    debug "Args: $*"
    debugn "Hook: ${hook}"

    # Interface for exit_hook
    if [[ "${hook}" = "exit_hook" ]]; then
        shift
        exit_hook "$@"
        exit 0
    fi

    # Interface for deploy_cert
    if [[ "${hook}" = "deploy_cert" ]]; then
        deploy_cert "$@"
        exit 0
    fi

    declare -A domains
    # Loop through arguments per 3 
    for ((i=2; i<=$#; i=i+3)); do
        t=$((i + 2))
        _domain="${!i}"
        _token="${!t}"

        if [[ "${_domain}" == "*."* ]]; then
        debug "Domain ${_domain} is a wildcard domain, ACME challenge will be for domain apex (${_domain:2})"
        _domain="${_domain:2}"
        fi

        domains[${_domain}]="${_token} ${domains[${_domain}]:-}"
    done

    unique_domains=($(echo ${!domains[@]} | tr ' ' '\n'| awk -F'.' '{print $(NF-1)"."$NF}' | sort -u | tr '\n' ' '))

    # Debug output
    debug "# Unique domains in certificate: "
    debugn "  ${unique_domains[@]}"

    # Loop through unique domains
    for domain in ${unique_domains[@]}; do

        challenge_list=($(echo ${!domains[@]} | tr ' ' '\n' | grep -E "${domain}$" | tr '\n' ' '))

        # Debug output
        debug "## Processing domain: ${domain}"
        debugn "## With challenges: ${challenge_list[@]}"

        # Loop through individually challenges
        for challenge in ${challenge_list[@]}; do

            # Debug output
            debugn "### Processing challenge: ${challenge}"

            record=$(echo "_acme-challenge."${challenge} | sed "s|\.$domain||g")
            for token in ${domains[${challenge}]}; do
                # Deploy a token(s)
                if [[ "${hook}" = "deploy_challenge" ]]; then dns_row_add ${domain} ${record} ${token}; fi
                # Remove a token(s)
                if [[ "${hook}" = "clean_challenge" ]]; then dns_row_delete ${domain} ${token}; fi
            done
        done
        dns_domain_commit $domain
    done

    # Wedos DNS is slow AF and it lasts up to $TTL (300) than record are on authoritative servers.
    # https://help.wedos.cz/otazka/rychlost-propagace-dns-zaznamu-na-autoritatvni-server/86560/
    if [[ "${hook}" = "deploy_challenge" ]]; then

	# Maybe next time... WDNS just doesnt work as it should
    	# Check if DNS record is available after commit.
        #name_server=$(dig +short +noall +answer -t ns ${domain} | head -n1)
        #debugn "Looking for \"${token}\" in ${record}.${domain} against @${name_server} with timeout ${WAPI_WAIT} seconds"
		#timeout ${WAPI_WAIT} bash -c -- 'until dig +short '${record}'.'${domain}' TXT @'${name_server}' | grep -q -- "'${token}'"; do sleep 5; done'

        # Debug output
        debugn "# Waiting for ${WAPI_WAIT} seconds"
        sleep ${WAPI_WAIT}
    fi
}

main "$@"
