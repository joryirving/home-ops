# NAS

## Hardware notes
MS-01, i5-12500H, 96GB DDR5. Dell LSI 9300-e. Lenovo SA120. ZFS Raidz2.

## Caddyfile

```yaml
minio.jory.dev {
        reverse_proxy voyager.internal:9001
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
        reverse_proxy voyager.internal:9000
        tls /data/certificates/wildcard.crt /data/certificates/wildcard.key
}
```

## Script to copy certs:
```sh
./home-ops/hack/cert-extract.sh main caddy
```
