while true; do kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller --address 0.0.0.0 443:443; done
