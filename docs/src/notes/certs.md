# Certs

## Hardware notes

MS-01, i5-12600H, 96GB DDR5. Dell LSI 9300-e. Lenovo SA120. ZFS Raidz2.

## Caddyfile

```caddyfile
garage-api.jory.dev {
reverse_proxy voyager.internal:3903
tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}

garage.jory.dev {
reverse_proxy voyager.internal:3909
tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}

nas.jory.dev {
reverse_proxy voyager.internal:5000
tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}

portainer.jory.dev {
reverse_proxy voyager.internal:9090
tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}

s3.jory.dev {
reverse_proxy voyager.internal:3900
tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}
```

## Cert sync

The `caddy-cert-sync` CronJob (`kubernetes/apps/main/network/cert-sync.yaml`)
copies the `jory-dev-tls` wildcard cert to voyager daily and restarts CaddyV2.
Trigger it manually:

```sh
kubectl --context main -n network create job --from=cronjob/caddy-cert-sync caddy-cert-sync-manual
```

Fallback from a workstation:

```sh
./hack/cert-extract.sh main caddy && ssh root@voyager docker restart CaddyV2
```
