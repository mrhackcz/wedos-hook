#!/bin/bash -e

set -f

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Variables
#~~~~~~~~~~~~~~~~~~~
login="EMAIL LOGIN"
wpass="P4SSW0RD"

hour=$(date +"%H")
wpass_hash=$(echo -n $wpass|sha1sum|awk '{print $1}')
wapi_url="https://api.wedos.com/wapi/json"
authHash=$(echo -n $login$wpass_hash$hour|sha1sum|awk '{print $1}')

# Arguments
#~~~~~~~~~~~~~~~~~~~
OPERATION=${1}
FULL_DOMAIN=${2}
CHALLENGE=${4}

# Functions
#~~~~~~~~~~~~~~~~~~

# Args - Not needed
list_domains () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-domains-list" } }' )
    echo ${jsonout} | jq -r "."
}

# Args - 1 - domain
list_resources () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-rows-list", "data": { "domain": "'${1}'" } } }' )
    echo ${jsonout} | jq -r "."
   }

# Args - 1 - domain | 2 - resource_id | 3 - rdata
update_resource_target () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-row-update", "data": { "domain": "'${1}'", "row_id": "'${2}'", "ttl": "300", "rdata": "'${3}'" } } }' )
    echo ${jsonout} | jq -r "."
}

# Args - 1 - domain | 2 - name | 3 - rdata
create_resource_target () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-row-add", "data": { "domain": "'${1}'", "name": "'${2}'", "ttl": "300", "type": "TXT", "rdata": "'${3}'", "auth_comment": "Edited by dehydrated WAPI hook" } } }' )
    echo ${jsonout} | jq -r "."
}

# Args - 1 - domain | 2 - resource_id
delete_resource_target () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-row-delete", "data": { "domain": "'${1}'", "row_id": "'${2}'" } } }' )
    echo ${jsonout} | jq -r "."
}

commit_changes () {
    jsonout=$(curl -ks ${wapi_url} --data-urlencode 'request={ "request": { "user": "'${login}'", "auth": "'${authHash}'", "command": "dns-domain-commit", "data": { "name": "'${1}'" } } }' )
}

process_domain() {
	TLD=${FULL_DOMAIN##*.}
	DOMAIN=${FULL_DOMAIN%%.$TLD*}
	DOMAIN=${DOMAIN##*.}
	DOMAIN=$DOMAIN.$TLD
	SUBDOMAIN=${FULL_DOMAIN%%$DOMAIN*}
	RESOURCE="_acme-challenge.${SUBDOMAIN}"
	RESOURCE=${RESOURCE%.*}
    DOMAIN_ACTIVE=`list_domains | jq -r ".response.data.domain[] | select(.name==\"${DOMAIN}\").status"`
    RESOURCE_ID=`list_resources ${DOMAIN} | jq -r ".response.data.row[] | select(.rdtype==\"TXT\") | select (.name==\"${RESOURCE}\") | .ID"`
}

verify_change() {
	RESULT=""
	until [ ".$RESULT" != "." ]
	do
		RESULT=`dig TXT $1 +noall +answer | grep IN | grep \"$2\"$`
		sleep 60
	done
}

deploy_challenge() {
	process_domain
	if [ "${DOMAIN_ACTIVE}" == "active" ]; then
		if [ ".$RESOURCE_ID" != "." ]; then
            update_resource_target $DOMAIN $RESOURCE_ID $CHALLENGE
            commit_changes $DOMAIN
		else
			create_resource_target $DOMAIN $RESOURCE $CHALLENGE
            commit_changes $DOMAIN
		fi
		verify_change $RESOURCE.$DOMAIN $CHALLENGE
	else
		echo "Domain is not active."
	fi
    commit_changes $DOMAIN
}

generate_csr() {
    local DOMAIN="${1}" CERTDIR="${2}" ALTNAMES="${3}"
}

clean_challenge() {
    process_domain
    delete_resource_target ${DOMAIN} ${RESOURCE_ID}
    commit_changes
}

deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"
    echo "Deploying locally"
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"
	echo "Not yet implemented: invalid_challenge"
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"
	echo "Not yet implemented: request_failure"
}

startup_hook() {
	true
}

exit_hook() {
	true
}

unchanged_cert() {
	local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
}

OPERATION="$1"; shift
if [[ "${OPERATION}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|generate_csr|startup_hook|exit_hook)$ ]]; then
    "$OPERATION" "$@"
fi

exit 0
