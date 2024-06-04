# Gloo-9574 Reproducer

https://github.com/solo-io/gloo/issues/9574

## Installation

Add Gloo EE Helm repo:
```
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
```

Export your Gloo Edge License Key to an environment variable:
```
export GLOO_EDGE_LICENSE_KEY={your license key}
```

Install Gloo Edge:
```
cd install
./install-gloo-edge-enterprise-with-helm.sh
```

> NOTE
> The Gloo Edge version that will be installed is set in a variable at the top of the `install/install-gloo-edge-enterprise-with-helm.sh` installation script.

## Setup the environment

Run the `install/setup.sh` script to setup the environment:
- Deploy Keycloak
- Deploy the OAuth Authorization Code Flow AuthConfig.
- Deploy the VirtualServices
- Deploy the HTTPBin service

```
./setup.sh
```

Run the `install/k8s-coredns-config.sh` script to patch K8S coreDns service to route `keycloak.example.com` to the Gloo Edge `gateway-proxy`. In this example this is needed to allow the AuthConfig that points to Keycloak to resolve `keycloak.example.com` and to route to Keycloak via the Gateway.

```
./k8s-coredns-config.sh
```

Note that you might need to restart the ExtAuth server if Keycloak was not yet available when the ExtAuth server was starting:
```
kubectl -n gloo-system rollout restart deployment extauth
```

## Setup Keycloak

Run the `keycloak.sh` script to create the OAuth clients and user accounts required to run the demo. This script will create an OAuth client for our web-application to perform OAuth Authorization Code Flow, an OAuth Client (Service Account) for Client Credentials Grant Flow (not used in this example), and 2 user accounts (`user1@example.com` and `user2@solo.io`).

```
./keycloak.sh
```

## Reproducer

Navigate to http://api.example.com/. You will be redirected to Keycloak to login. Login with:

```
Username: user1@example.com
Password: password
```

This will:
- Create get you an authorization code
- Gloo will exchange the authorization code for an id-token, access-token and refresh token.
- Gloo will create a session in Redis in which it will store the tokens.
- Gloo sets a session cookie on the response to the client, pointing at the session in Redis.
- Client is redirected to the form.

Next, in a different browser /  browser profile, go to the Keycloak admin console at http://keycloak.example.com and login as admin: `u:admin/p:admin`. Go the "Sessions" menu and delete the session of `user1` that was just created. This will cause `user1`'s refresh-token to no longer be usable (or to be expired).

Wait a minute until `user1`'s access-token has expired and hit the application again at http://api.example.com.

Instead of the user being redirected to the Keycloak login screen, the user is redirected to http://www.google.com, which we've set as the `afterLogoutUrl`.

## Conclusion
When the there is a session in Redis with expired tokens, and the user accesses the application, the user is redirected to the `afterLogoutUrl` instead of the `issuerUrl`. This IMO is incorrect behaviour, as the user should only be redirecred to the `afterLogoutUrl` when the user does an explicit logout, i.e. by hitting the configured `logout` endpoint.