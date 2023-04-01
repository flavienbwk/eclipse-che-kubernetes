# Eclipse Che on Kubernetes

All resources to instanciate Eclipse Che on your own Kubernetes cluster.

This is the companion repo for the Medium post "Developing in the Cloud".

## Architecture and pre-requisites

![Eclipse Che architecture with Kubernetes](./images/keycloak-che.jpg)

Eclipse Che [requires an OIDC identity provider](https://github.com/eclipse/che/issues/21160#issuecomment-1038877280) configured in your Kubernetes cluster in order to work. We will use [Keycloak](https://github.com/keycloak/keycloak) in this repo. All external flows will be routed by an [Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/) deployed in our Kubernetes cluster.

Keycloak must be run in an external environment in order to be reachable by our Kubernetes' API server at startup. A dedicated role and rolebinding will be created in our cluster.

It is recommended to setup Che on a dedicated machine (VM or baremetal) due to rigorous pre-requisites for it to work.

## Getting started

At this step, I expect you to have :

- A working Kubernetes cluster up and running with an Ingress Controller installed
- Docker installed on the same machine (or a remote host, as long as you edit the following configurations)

### A. Setup Keycloak

1. **Copy** env variables

    ```bash
    cd ./keycloak
    cp .env.example .env
    ```

    Correctly set `KEYCLOAK_EXTERNAL_URL` in your `.env` file replacing `xxx.xxx.xxx.xxx` with your cluster **IP address**. Then run :

    ```bash
    export $(grep -v '^#' ./keycloak/.env | xargs)
    ```

2. **Generate** certs and start Keycloak

    ```
    bash ./generate-certs.sh
    docker-compose up -d
    ```

3. **Create** and configure the `apacheche` client in Keycloak

    ```
    bash ./configure-keycloak.sh
    cd ..
    ```

### B. Bind Kubernetes to use Keycloak

1. Copy Keycloak's certificate to your system keystore

    ```bash
    sudo cp ./keycloak/certs/ca/root-ca.pem /etc/ca-certificates/keycloak-ca.pem
    ```

    This certificate file must be reachable by your Kubernetes cluster.

2. Add the following configuration to `/etc/kubernetes/manifests/kube-apiserver.yaml`

    ```txt
        - --oidc-issuer-url=https://172.17.0.1:8443/realms/master
        - --oidc-client-id=apacheche
        - --oidc-ca-file=/etc/ca-certificates/keycloak-ca.pem
    ```

    :clock: Please wait at least 30 seconds and test the cluster is still working running `kubectl get po -A`

3. Make Keycloak accessible through your Ingress Controller

    ```bash
    kubectl create secret tls tls-keycloak-ingress --cert ./keycloak/certs/ca/root-ca.pem --key ./keycloak/certs/ca/root-ca.key
    sed "s|\$KEYCLOAK_EXTERNAL_URL|${KEYCLOAK_EXTERNAL_URL#https://}|g" ingress-keycloak-example.yaml > ingress-keycloak.yaml && kubectl apply -f ./ingress-keycloak.yaml
    ```
