#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail
set -x

oc label node worker-0 cluster.ocs.openshift.io/openshift-storage=''
oc label node worker-1 cluster.ocs.openshift.io/openshift-storage=''
oc label node worker-2 cluster.ocs.openshift.io/openshift-storage=''
oc label node worker-3 cluster.ocs.openshift.io/openshift-storage=''

oc apply -f - <<EOF
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-block
  namespace: openshift-local-storage
spec:
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: cluster.ocs.openshift.io/openshift-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: localblock
      volumeMode: Block
      devicePaths:
        - /dev/vda
EOF

oc wait LocalVolume/local-block -n openshift-local-storage --for=condition=Available --timeout=15m

oc apply -f - <<EOF
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
 name: ocs-storagecluster
 namespace: openshift-storage
spec:
 manageNodes: false
 monDataDirHostPath: /var/lib/rook
 storageDeviceSets:
 - count: 3
   dataPVCTemplate:
     spec:
       accessModes:
       - ReadWriteOnce
       resources:
         requests:
           storage: "1"
       storageClassName: localblock
       volumeMode: Block
   name: ocs-deviceset
   placement: {}
   portable: false
   replica: 1
   resources: {}
EOF

oc wait StorageCluster/ocs-storagecluster -n openshift-storage --for=condition=Available --timeout=15m

# Setting ocs-storagecluster-ceph-rbd the default storage class
for item in $(oc get sc --no-headers | awk '{print $1}'); do
	oc annotate --overwrite sc "$item" storageclass.kubernetes.io/is-default-class='false'
done
oc annotate --overwrite sc ocs-storagecluster-ceph-rbd storageclass.kubernetes.io/is-default-class='true'
echo "ocs-storagecluster-ceph-rbd is set as default storage class"