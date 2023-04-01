#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CERTS_DIR="$(readlink -f "$SCRIPT_DIR/certs")"

mkdir -p "$CERTS_DIR/"{ca,keycloak}
export CERTS_DN="/C=FR/ST=FR/L=FR/O=ApacheChe/OU=ApacheChe"

# Root CA
openssl genrsa -out "$CERTS_DIR/ca/root-ca.key" 2048
openssl req -new -x509 -sha256 -days 360 -subj "$CERTS_DN/CN=CA" -key "$CERTS_DIR/ca/root-ca.key" -out "$CERTS_DIR/ca/root-ca.pem"

# Keycloak
openssl genrsa -out "$CERTS_DIR/keycloak/keycloak-temp.key" 2048
openssl pkcs8 -inform PEM -outform PEM -in "$CERTS_DIR/keycloak/keycloak-temp.key" -topk8 -nocrypt -v1 PBE-SHA1-3DES -out "$CERTS_DIR/keycloak/keycloak.key"
openssl req -new -subj "$CERTS_DN/CN=keycloak" -key "$CERTS_DIR/keycloak/keycloak.key"  -out "$CERTS_DIR/keycloak/keycloak.csr"
openssl x509 -req -days 360 -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:172.17.0.1,DNS:keycloak") -in "$CERTS_DIR/keycloak/keycloak.csr" -CA "$CERTS_DIR/ca/root-ca.pem" -CAkey "$CERTS_DIR/ca/root-ca.key" -CAcreateserial -sha256 -out "$CERTS_DIR/keycloak/keycloak.pem"
cp "$CERTS_DIR/keycloak/keycloak.key" "$CERTS_DIR/keycloak/tls.key"
openssl x509 -outform der -in "$CERTS_DIR/keycloak/keycloak.pem" -out "$CERTS_DIR/keycloak/tls.crt"

chmod 755 -R "$CERTS_DIR"
