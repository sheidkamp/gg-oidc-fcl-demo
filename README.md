# Gloo Gateway - OIDC Front Channel Logout demo


# OIDC Front Channel Logout

Specification: https://openid.net/specs/openid-connect-frontchannel-1_0.html


## Installation

Add Gloo EE Test Helm repo:
```
helm repo add gloo-ee-test https://storage.googleapis.com/gloo-ee-test-helm
```

Export your Gloo Gateway License Key to an environment variable:
```
export GLOO_GATEWAY_LICENSE_KEY={your license key}
```

Install Gloo Gateway:
```
cd install
./install-gloo-gateway-enterprise-with-helm.sh
```

> NOTE
> The Gloo Gateway version that will be installed is set in a variable at the top of the `install/install-gloo-gateway-enterprise-with-helm.sh` installation script.

## Setup the environment

Run the `install/setup.sh` script to setup the environment:
- Deploy Keycloak
- Deploy the OAuth Authorization Code Flow AuthConfig.
- Deploy the VirtualServices
- Deploy the HTTPBin service

```
./setup.sh
```

Run the `install/k8s-coredns-config.sh` script to patch K8S coreDns service to route `keycloak.example.com` to the keycloak service. In this example this is needed to allow the AuthConfig that points to Keycloak to resolve `keycloak.example.com` and to route to Keycloak via the Gateway.

```
./k8s-coredns-config.sh
```

Note that you might need to restart the ExtAuth server if Keycloak was not yet available when the ExtAuth server was starting:
```
kubectl -n gloo-system rollout restart deployment extauth
```

## Expose keycloak and example app
You will need to access the app and keycloak server from outside the Kubernetes cluster, and there are 2 steps that make this possible:
* Add the `127.0.0.1 api.example.com api2.example.com keycloak.example.com` to `/etc/hosts` so that the apps can be accessed by domain name

You will need to make sure that your Gloo gateway-proxy is accessible on the given ip-address, in our example this is localhost (i.e. `127.0.0.1`).
When running on Minikube, this can for example be done by creating a tunnel into the Minikube cluster:

```
minikube -p {profile-name} tunnel
```

## Setup Keycloak

Run the `keycloak.sh` script to create the OAuth clients and user accounts required to run the demo. This script will create OAuth clients for our web-applications at `api.example.com` and `api2.example.com` to perform OAuth Authorization Code Flow and 2 user accounts (`user1@example.com` and `user2@solo.io`). The OAuth clients for our web-applications will be configured to be able to use the OIDC Front Channel Logout functionality. Note that we are also automatically configuring the Keycloak Content Security Policy (CSP) so the IFrame that is used by the Front Channel Logout functionality can be properly loaded in the browser.

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

Next, in a different browser tab, go navigate to http://api2.example.com. Since we're already logged into Keycload, we will be automatically able to access the applicatino using single-sign-on.

In the first browser tab, open the "Developer Tools" of your browser so we can observe the HTTP request that are made during the logout flow. Now, navigate to http://api.example.com/logout. This will initiate the OIDC Front Channel Logout flow, which will redirect the browser to the Keycloak logout endpoint. Next, the logout endpoint will load an IFrame that will redirect the browser to all the logout endpoints of the applications to which we are logged in, effectively logging out of all the applications that we've used in our session.

You will see the following HTTP Request and Response:

```
GET http://keycloak.example.com/realms/master/protocol/openid-connect/logout?id_token_hint=eyJhbGciOiJS....&post_logout_redirect_uri=http%3A%2F%2Fapi.example.com
```

Which will return the following response, which includes the IFrames to logout of our applications:

```
<div id="kc-content">
        <div id="kc-content-wrapper">

        <p>You are logging out from following apps</p>
        <ul>
            <li>
                webapp-client-2
                <iframe src="http://api2.example.com/fc_logout?sid=a3b3ddba-6d8d-456c-b10f-73e82b7dc203&amp;iss=http%3A%2F%2Fkeycloak.example.com%2Frealms%2Fmaster" style="display:none;"></iframe>
            </li>
            <li>
                webapp-client
                <iframe src="http://api.example.com/fc_logout?sid=a3b3ddba-6d8d-456c-b10f-73e82b7dc203&amp;iss=http%3A%2F%2Fkeycloak.example.com%2Frealms%2Fmaster" style="display:none;"></iframe>
            </li>
        </ul>
            <script>
                function readystatechange(event) {
                    if (document.readyState=='complete') {
                        window.location.replace('http://api.example.com');
                    }
                }
                document.addEventListener('readystatechange', readystatechange);
            </script>
            <a id="continue" class="btn btn-primary" href="http://api.example.com">Continue</a>
        </div>
      </div>
```

This will initiate the logout requests to our applications, as can be seen from the HTTP Request/Response flow:

```
GET http://api2.example.com/fc_logout?sid=a3b3ddba-6d8d-456c-b10f-73e82b7dc203&iss=http%3A%2F%2Fkeycloak.example.com%2Frealms%2Fmaster
GET http://api.example.com/fc_logout?sid=a3b3ddba-6d8d-456c-b10f-73e82b7dc203&iss=http%3A%2F%2Fkeycloak.example.com%2Frealms%2Fmaster
```

Finally, the browser is redirected to the logout URL of the application from which the logout was initiated.

## Conclusion
The OIDC Front Channel Logout functionality of Gloo Gateway allows us to automatically logout of a set of applications when the we logout out of a single application or when we logout on the OIDC Provider directly.