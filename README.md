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

### 1. Setup Keycloak

```bash
cp .env.example .env
cd ./keycloak

bash generate-certs.sh
docker-compose up -d

cd -
```
