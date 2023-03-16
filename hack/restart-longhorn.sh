kubectl rollout restart daemonset engine-image-ei-7fa7c208 -n storage
kubectl rollout restart daemonset longhorn-csi-plugin -n storage
kubectl rollout restart daemonset longhorn-manager -n storage

kubectl rollout restart deploy csi-attacher -n storage
kubectl rollout restart deploy csi-provisioner -n storage
kubectl rollout restart deploy csi-resizer -n storage
kubectl rollout restart deploy csi-snapshotter -n storage
kubectl rollout restart deploy longhorn-driver-deployer -n storage
kubectl rollout restart deploy longhorn-ui -n storage