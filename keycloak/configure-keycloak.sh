#!/bin/bash
# Configuring Keycloak 20.x for create an "apacheche" client that will be bound to K8S for OIDC

set -e # Fail on any error

# Colors and styles
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

msg_notice() {
    echo -e "${CYAN}[NOTICE]${RESET} $1"
}
msg_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}
msg_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}
msg_warn() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}
msg_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ENV_PATH="$SCRIPT_DIR/.env"

if [ -f "$ENV_PATH" ]; then
    source "$ENV_PATH"
else
    msg_error "Env file $ENV_PATH does not exist, please follow the documentation."
    exit 1
fi

msg_info "Configuring secret..."
if [ -z "$KEYCLOAK_CHE_CLIENT_SECRET" ]; then
    msg_notice "Generating secret..."
    KEYCLOAK_CHE_CLIENT_SECRET=$(uuidgen | tr -d '-')
    msg_notice "Updating .env..."
    sed -i 's/^KEYCLOAK_CHE_CLIENT_SECRET=.*/KEYCLOAK_CHE_CLIENT_SECRET='"$KEYCLOAK_CHE_CLIENT_SECRET"'/' "$ENV_PATH"
    msg_success "Sucessfuly persisted client secret."
else
    msg_info "Client secret is already defined. Skipping."
fi

msg_info "Getting admin access token..."
ADMIN_TOKEN=$(curl -ks -X POST \
"$KEYCLOAK_INTERNAL_URL/realms/master/protocol/openid-connect/token" \
-H "Content-Type: application/x-www-form-urlencoded" \
-d "username=$KEYCLOAK_ADMIN_USER" \
-d "password=$KEYCLOAK_ADMIN_PASSWORD" \
-d 'grant_type=password' \
-d 'client_id=admin-cli' | jq -r '.access_token')
if [ "$ADMIN_TOKEN" == "null" ]; then
    msg_error "Could not get admin token"
    exit 1
else
    msg_success "\xE2\x9C\x94"
fi

msg_info "Setting access token lifespan to 1 hour..."
response_details=$(curl -iks -X PUT "$KEYCLOAK_INTERNAL_URL/admin/realms/master" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
-d '
{
    "accessTokenLifespan": 3600
}')
response=$( echo "$response_details" | grep HTTP | awk '{print $2}')
if [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Creating $KEYCLOAK_CHE_CLIENT_ID client"
response=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
-d '
{
    "clientId": "'"$KEYCLOAK_CHE_CLIENT_ID"'",
    "redirectUris": ["'"$KEYCLOAK_CHE_REDIRECT_URI"'*", "https://localhost:8443/*", "https://172.17.0.1:8443/*"],
    "authorizationServicesEnabled": false,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "implicitFlowEnabled": false,
    "standardFlowEnabled": true,
    "publicClient": false,
    "secret": "'"$KEYCLOAK_CHE_CLIENT_SECRET"'"
}'| grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already exists)"
elif [ "$response" == "201" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Getting $KEYCLOAK_CHE_CLIENT_ID client details"
response_details=$(curl -kis -X GET "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json")
response=$( echo "$response_details" | grep HTTP | awk '{print $2}')
if [ "$response" == "200" ]; then
    clients=$(echo "$response_details" | tail -1 | jq -r '.[] | @base64')
    CLIENT_FOUND=false
    for client in $clients; do
        client_name=$(echo "$client" | base64 --decode | jq -r '.clientId')
        client_id=$(echo "$client" | base64 --decode | jq -r '.id')
        if [ "$client_name" == "$KEYCLOAK_CHE_CLIENT_ID" ]; then
            CLIENT_FOUND=true
            KEYCLOAK_CHE_CLIENT_ID_NUM="$client_id"
            break
        fi
    done
    if [ $CLIENT_FOUND == false ]; then
        msg_error "\u2717 (client $KEYCLOAK_CHE_CLIENT_ID not found)"
        exit 1
    else
        msg_success "\u2713"
    fi
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Adding realm roles mapper to $KEYCLOAK_CHE_CLIENT_ID client"
response=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/protocol-mappers/add-models" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--data-raw '[{"name":"realm roles","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","consentRequired":false,"config":{"multivalued":"true","user.attribute":"foo","access.token.claim":"true","claim.name":"realm_access.roles","jsonType.label":"String"}}]' \
| grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Listing role mappers for $KEYCLOAK_CHE_CLIENT_ID client"
response_details=$(curl -kis -X GET "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json")
response=$(echo "$response_details"| grep HTTP | awk '{print $2}')
if [ "$response" == "200" ]; then
    protocol_mapper_name="realm roles"
    protoc_mappers=$(echo "$response_details" | tail -1 | jq -r '.protocolMappers' | jq -r '.[] | @base64')
    PM_FOUND=false
    for client in $protoc_mappers; do
        pm_name=$(echo "$client" | base64 --decode | jq -r '.name')
        pm_id=$(echo "$client" | base64 --decode | jq -r '.id')
        if [ "$pm_name" == "$protocol_mapper_name" ]; then
            PM_FOUND=true
            PROTOCOL_MAPPER_ID="$pm_id"
            break
        fi
    done
    if [ $PM_FOUND == false ]; then
        msg_error "\u2717 (protocol mapper $protocol_mapper_name not found)"
        exit 1
    else
        msg_success "\u2713"
    fi
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Patching realm roles mapper for $KEYCLOAK_CHE_CLIENT_ID client"
CLAIM_NAME="roles"
response_details=$(curl -kis -X PUT "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/protocol-mappers/models/$PROTOCOL_MAPPER_ID" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--data-raw '{"id":"'"$PROTOCOL_MAPPER_ID"'","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","name":"realm roles","config":{"usermodel.realmRoleMapping.rolePrefix":"","claim.name":"'"$CLAIM_NAME"'","multivalued":"true","jsonType.label":"String","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}}' \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Adding admin client role..."
response=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/roles" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--compressed \
--insecure \
--data-raw '{"name":"admin"}' \
| grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "201" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi
msg_info "Adding developer client role..."
response=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/roles" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--compressed \
--insecure \
--data-raw '{"name":"developer"}' \
| grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "201" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Adding predefined mapper groups to the dedicated client scope..."
response_details=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/protocol-mappers/add-models" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--data-raw '[{"name":"groups","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","consentRequired":false,"config":{"multivalued":"true","user.attribute":"foo","id.token.claim":"true","access.token.claim":"true","claim.name":"groups","jsonType.label":"String"}}]' \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Retrieve $KEYCLOAK_ADMIN_USER details..."
response_details=$(curl -kis -X GET "$KEYCLOAK_INTERNAL_URL/admin/realms/master/users?username=$KEYCLOAK_ADMIN_USER" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "200" ]; then
    msg_success "\u2713"
    KEYCLOAK_ADMIN_USER_ID=$(echo "$response_details" | tail -1 | jq '.[].id' | tr -d '"')
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Retrieve $KEYCLOAK_CHE_CLIENT_ID:admin role details"
response_details=$(curl -kis -X GET "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM/roles" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "200" ]; then
    msg_success "\u2713"
    KEYCLOAK_CLIENT_ROLE_ADMIN_ID=$(echo "$response_details" | tail -1 | jq '.[] | select(.name == "admin") | .id' | tr -d '"')
    if [ ! -n "$KEYCLOAK_CLIENT_ROLE_ADMIN_ID" ]; then
        msg_error "admin role ID was not found !"
        exit 1
    fi
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Attribute $KEYCLOAK_CHE_CLIENT_ID:admin role to $KEYCLOAK_ADMIN_USER"
response_details=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/users/$KEYCLOAK_ADMIN_USER_ID/role-mappings/clients/$KEYCLOAK_CHE_CLIENT_ID_NUM" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--data-raw '[{"id":"'"$KEYCLOAK_CLIENT_ROLE_ADMIN_ID"'","name":"admin"}]' \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi

msg_info "Add valid email to $KEYCLOAK_ADMIN_USER"
response_details=$(curl -kis -X PUT "$KEYCLOAK_INTERNAL_URL/admin/realms/master/users/$KEYCLOAK_ADMIN_USER_ID" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
--data-raw '{"enabled":true,"username":"'"$KEYCLOAK_ADMIN_USER"'","email":"'"$KEYCLOAK_ADMIN_USER"'@example.local","firstName":"'"$KEYCLOAK_ADMIN_USER"'","lastName":"'"$KEYCLOAK_ADMIN_USER"'","emailVerified":true,"requiredActions":[]}' \
--compressed \
--insecure)
response=$(echo $response_details | grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already added)"
elif [ "$response" == "204" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi


# ---- Web access (nginx-keycloak) configurations ----


msg_info "Configuring web access secret..."
if [ -z "$KEYCLOAK_APP_CLIENT_SECRET" ]; then
    msg_notice "Generating secret..."
    KEYCLOAK_APP_CLIENT_SECRET=$(uuidgen | tr -d '-')
    msg_notice "Updating .env..."
    sed -i 's/^KEYCLOAK_APP_CLIENT_SECRET=.*/KEYCLOAK_APP_CLIENT_SECRET='"$KEYCLOAK_APP_CLIENT_SECRET"'/' "$ENV_PATH"
    msg_success "Sucessfuly persisted client secret."
else
    msg_info "Client secret is already defined. Skipping."
fi

msg_info "Creating $KEYCLOAK_APP_CLIENT_ID client for web access"
response=$(curl -kis -X POST "$KEYCLOAK_INTERNAL_URL/admin/realms/master/clients" \
-H "Authorization: Bearer $ADMIN_TOKEN" \
-H "Content-Type: application/json" \
-d '
{
    "clientId": "'"$KEYCLOAK_APP_CLIENT_ID"'",
    "rootUrl": "'"$KEYCLOAK_APP_URI"'",
    "redirectUris": ["'"$KEYCLOAK_APP_URI"'/*", "http://localhost:8080/*"],
    "authorizationServicesEnabled": false,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "implicitFlowEnabled": false,
    "standardFlowEnabled": true,
    "publicClient": false,
    "secret": "'"$KEYCLOAK_APP_CLIENT_SECRET"'"
}'| grep HTTP | awk '{print $2}')
if [ "$response" == "409" ]; then
    msg_notice "\u2713 (already exists)"
elif [ "$response" == "201" ]; then
    msg_success "\u2713"
else
    msg_error "\u2717"
    exit 1
fi
