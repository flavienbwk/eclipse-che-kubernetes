#!/bin/bash

kubeadm init --config kubeadm-config.yaml
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.7.0/deploy/static/provider/baremetal/deploy.yaml

kubectl apply -f https://openebs.github.io/charts/openebs-operator.yaml
#kubectl apply -f https://openebs.github.io/charts/cstor-operator.yaml
#kubectl patch storageclass openebs-device -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
#kubectl apply -f - <<EOF
#apiVersion: v1
#kind: PersistentVolume
#metadata:
#  name: openebs-device-pv
#  annotations:
#    openebs.io/block-device: <blockdevice-name>
#spec:
#  capacity:
#    storage: <required-storage-capacity>
#  accessModes:
#    - ReadWriteOnce
#  persistentVolumeReclaimPolicy: Delete
#  storageClassName: openebs-device
#  local:
#    path: /dev
#EOF

systemctl restart containerd
systemctl restart kubelet

kubectl taint nodes "$(hostname)" node-role.kubernetes.io/control-plane:NoSchedule-
