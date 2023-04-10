#!/bin/bash

kubeadm reset -f
rm -r /etc/cni/net.d
rm "$HOME/.kube/config"
