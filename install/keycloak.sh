#!/bin/bash

set +x -e

export KEYCLOAK_HOST=keycloak.example.com
export KC_ADMIN_PASS=admin
export PORTAL_HOST=developer.example.com


export KEYCLOAK_URL=http://$KEYCLOAK_HOST:8080
echo "Keycloak URL: $KEYCLOAK_URL"
export APP_URL=http://$PORTAL_HOST

[[ -z "$KC_ADMIN_PASS" ]] && { echo "You must set KC_ADMIN_PASS env var to the password for a Keycloak admin account"; exit 1;}

# Set the Keycloak admin token
export KEYCLOAK_TOKEN=$(curl -k -d "client_id=admin-cli" -d "username=admin" -d "password=$KC_ADMIN_PASS" -d "grant_type=password" "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -r .access_token)

[[ -z "$KEYCLOAK_TOKEN" ]] && { echo "Failed to get Keycloak token - check KEYCLOAK_URL and KC_ADMIN_PASS"; exit 1;}


# Configure the Realm. Configuring CSP to support Front Channel Logout for our applications.
CONFIGURE_REALM_JSON=$(cat <<EOM
{
  "browserSecurityHeaders": {
    "contentSecurityPolicy": "frame-src 'self' http://api.example.com:8080 http://api2.example.com:8080; frame-ancestors 'self'; object-src 'none';"
  }
}
EOM
)
curl -k -X PUT -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -H "Content-Type: application/json" -d "$CONFIGURE_REALM_JSON" $KEYCLOAK_URL/admin/realms/master


# ################################################ WebApp Client: webapp-client ################################################
# Register the webapp-client
export WEBAPP_CLIENT_ID=webapp-client

CREATE_WEBAPP_CLIENT_JSON=$(cat <<EOM
{
  "clientId": "$WEBAPP_CLIENT_ID"
}
EOM
)
read -r regid secret <<<$(curl -k -X POST -H "Authorization: bearer ${KEYCLOAK_TOKEN}" -H "Content-Type:application/json" -d "$CREATE_WEBAPP_CLIENT_JSON"  ${KEYCLOAK_URL}/realms/master/clients-registrations/default|  jq -r '[.id, .secret] | @tsv')

export WEBAPP_CLIENT_SECRET=${secret}
export REG_ID=${regid}

[[ -z "$WEBAPP_CLIENT_SECRET" || $WEBAPP_CLIENT_SECRET == null ]] && { echo "Failed to create client in Keycloak"; exit 1;}

# Create a oauth K8S secret with from the webapp-client's secret. 
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth
  namespace: gloo-system
type: extauth.solo.io/oauth
data:
  client-secret: $(echo -n ${WEBAPP_CLIENT_SECRET} | base64)
EOF

# Configure the WebApp Client we've just created.
CONFIGURE_WEBAPP_CLIENT_JSON=$(cat <<EOM
{
  "publicClient": false, 
  "serviceAccountsEnabled": true, 
  "directAccessGrantsEnabled": true, 
  "authorizationServicesEnabled": true, 
  "redirectUris": [
    "http://api.example.com:8080/callback"
  ],
  "webOrigins": ["*"],
  "frontchannelLogout": true,
  "attributes": {
    "frontchannel.logout.url": "http://api.example.com:8080/fc_logout",
    "post.logout.redirect.uris": "http://api.example.com:8080"
  }
}
EOM
)
curl -k -X PUT -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -H "Content-Type: application/json" -d "$CONFIGURE_WEBAPP_CLIENT_JSON" $KEYCLOAK_URL/admin/realms/master/clients/${REG_ID}

# Add the group attribute in the JWT token returned by Keycloak
CONFIGURE_GROUP_CLAIM_IN_JWT_JSON=$(cat <<EOM
{
  "name": "group", 
  "protocol": "openid-connect", 
  "protocolMapper": "oidc-usermodel-attribute-mapper", 
  "config": {
    "claim.name": "group", 
    "jsonType.label": "String", 
    "user.attribute": "group", 
    "id.token.claim": "true", 
    "access.token.claim": "true"
  }
}
EOM
)
curl -k -X POST -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -H "Content-Type: application/json" -d "$CONFIGURE_GROUP_CLAIM_IN_JWT_JSON" $KEYCLOAK_URL/admin/realms/master/clients/${REG_ID}/protocol-mappers/models

################################################ WebApp Client: webapp-client-2 (TODO move to function/loop) ################################################
# Register the webapp-client
export WEBAPP_CLIENT_ID_2=webapp-client-2

CREATE_WEBAPP_CLIENT_JSON_2=$(cat <<EOM
{
  "clientId": "$WEBAPP_CLIENT_ID_2"
}
EOM
)
read -r regid secret <<<$(curl -k -X POST -H "Authorization: bearer ${KEYCLOAK_TOKEN}" -H "Content-Type:application/json" -d "$CREATE_WEBAPP_CLIENT_JSON_2"  ${KEYCLOAK_URL}/realms/master/clients-registrations/default|  jq -r '[.id, .secret] | @tsv')

export WEBAPP_CLIENT_SECRET_2=${secret}
export REG_ID_2=${regid}

[[ -z "$WEBAPP_CLIENT_SECRET_2" || $WEBAPP_CLIENT_SECRET_2 == null ]] && { echo "Failed to create client in Keycloak"; exit 1;}

# Create a oauth K8S secret with from the webapp-client's secret. 
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: oauth-2
  namespace: gloo-system
type: extauth.solo.io/oauth
data:
  client-secret: $(echo -n ${WEBAPP_CLIENT_SECRET_2} | base64)
EOF

# Configure the WebApp Client we've just created.
CONFIGURE_WEBAPP_CLIENT_JSON_2=$(cat <<EOM
{
  "publicClient": false, 
  "serviceAccountsEnabled": true, 
  "directAccessGrantsEnabled": true, 
  "authorizationServicesEnabled": true, 
  "redirectUris": [
    "http://api2.example.com:8080/callback"
  ], 
  "webOrigins": ["*"],
  "frontchannelLogout": true,
  "attributes": {
    "frontchannel.logout.url": "http://api2.example.com:8080/fc_logout",
    "post.logout.redirect.uris": "http://api2.example.com:8080"
  }
}
EOM
)
curl -k -X PUT -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -H "Content-Type: application/json" -d "$CONFIGURE_WEBAPP_CLIENT_JSON_2" $KEYCLOAK_URL/admin/realms/master/clients/${REG_ID_2}

# Add the group attribute in the JWT token returned by Keycloak
CONFIGURE_GROUP_CLAIM_IN_JWT_JSON=$(cat <<EOM
{
  "name": "group", 
  "protocol": "openid-connect", 
  "protocolMapper": "oidc-usermodel-attribute-mapper", 
  "config": {
    "claim.name": "group", 
    "jsonType.label": "String", 
    "user.attribute": "group", 
    "id.token.claim": "true", 
    "access.token.claim": "true"
  }
}
EOM
)
curl -k -X POST -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -H "Content-Type: application/json" -d "$CONFIGURE_GROUP_CLAIM_IN_JWT_JSON" $KEYCLOAK_URL/admin/realms/master/clients/${REG_ID_2}/protocol-mappers/models



################################################ User One: user1@example.com ################################################

# Create first user        
CREATE_USER_ONE_JSON=$(cat <<EOM
{
  "username": "user1", 
  "email": "user1@example.com", 
  "enabled": true, 
  "attributes": {
    "group": "users"
  },
  "credentials": [
    {
      "type": "password", 
      "value": "password",
      "temporary": false
    }
  ]
}
EOM
)
curl -k -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" -d "$CREATE_USER_ONE_JSON" $KEYCLOAK_URL/admin/realms/master/users


################################################ User Two: user2@solo.io ################################################

# Create second user
CREATE_USER_TWO_JSON=$(cat <<EOM
{
  "username": "user2",
  "email": "user2@solo.io",
  "enabled": true,
  "attributes": {
    "group": "users"
  }, 
  "credentials": [
    {
      "type": "password",
      "value": "password",
      "temporary": false
    }
  ]
}
EOM
)
curl -k -X POST -H "Authorization: Bearer ${KEYCLOAK_TOKEN}"  -H "Content-Type: application/json" -d "$CREATE_USER_TWO_JSON" $KEYCLOAK_URL/admin/realms/master/users