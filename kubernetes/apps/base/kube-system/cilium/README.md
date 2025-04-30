# Cilium

## UniFi BGP

```sh
router bgp 64513
  bgp router-id 192.168.1.1
  no bgp ebgp-requires-policy

  neighbor k8s-main peer-group
  neighbor k8s-main remote-as 64514

  neighbor k8s-utility peer-group
  neighbor k8s-utility remote-as 64515

  neighbor 10.69.1.21 peer-group k8s-main
  neighbor 10.69.1.22 peer-group k8s-main
  neighbor 10.69.1.23 peer-group k8s-main
  neighbor 10.69.1.121 peer-group k8s-utility

  address-family ipv4 unicast
    neighbor k8s-main next-hop-self
    neighbor k8s-main soft-reconfiguration inbound
    neighbor k8s-utility next-hop-self
    neighbor k8s-utility soft-reconfiguration inbound
  exit-address-family
exit
```
