# Rclone to R2

## Install and setup rclone

Install rclone on your NAS

Run the rclone config for the endpoint

```sh
rclone config
```

1. Select n for a new remote.

2. Enter a name (e.g., cloudflare-r2).

3. Choose s3 as the storage type.

4. Set S3 provider to Cloudflare.

5. Enter the Cloudflare R2 Access Key and Secret Key (found in your Cloudflare dashboard under "R2 API Tokens"). Note that you want to scope this to read/write on a specific bucket(s).

6. Set endpoint to your account's R2 endpoint:

```sh
https://<account-id>.r2.cloudflarestorage.com
```

7. Leave region blank.

8. Use default options for remaining settings.

9. Test the connection by running:

```sh
rclone ls cloudflare-r2:<bucketname>
```

## Kopia repository script

Volsync was replaced by kopiur; the `volsync` directory on voyager is now the
Kopia repository behind the kopiur `volsync` ClusterRepository
(`kubernetes/apps/base/storage/kopiur/repository/repository.yaml`).

Create the script and save it somewhere notable (or for unRaid, use User Scripts plugin)

```sh
#!/bin/bash

# Variables
POOL_NAME="daena" ## ZFS Pool name
DATASET_NAME="kubernetes" ## ZFS Dataset name
SNAPSHOT_NAME="rclone-volsync-backup-$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_PATH="/mnt/$POOL_NAME/$DATASET_NAME/.zfs/snapshot/$SNAPSHOT_NAME"
SUBDIR_TO_SYNC="volsync"  # The directory inside the snapshot
RCLONE_REMOTE="cloudflare-r2:volsync"

# Create a ZFS snapshot
echo "Creating ZFS snapshot: $POOL_NAME/$DATASET_NAME@$SNAPSHOT_NAME"
zfs snapshot "$POOL_NAME/$DATASET_NAME@$SNAPSHOT_NAME"

# Ensure the snapshot path exists before proceeding
if [ ! -d "$SNAPSHOT_PATH" ]; then
    echo "Snapshot not found! Exiting..."
    exit 1
fi

# Sync only the `volsync/` subdir from the snapshot
echo "Starting rclone sync for $SUBDIR_TO_SYNC..."
rclone sync "$SNAPSHOT_PATH/$SUBDIR_TO_SYNC" "$RCLONE_REMOTE" \
  --progress \
  --fast-list \
  --transfers=64 \
  --checkers=64 \
  --s3-upload-concurrency=64 \
  --s3-chunk-size=64M \
  --no-traverse \
  --retries=10 \
  --low-level-retries=20 \
  --tpslimit=10 \
  --tpslimit-burst=20

# Cleanup: Remove the snapshot after sync
echo "Deleting snapshot: $POOL_NAME/$DATASET_NAME@$SNAPSHOT_NAME"
zfs destroy "$POOL_NAME/$DATASET_NAME@$SNAPSHOT_NAME"

echo "Backup completed!"
```

This script will grab a ZFS snapshot, rclone sync that to the remote bucket, and then destroy the snapshot. This ensures the data isn't written to mid-flight. It will also delete any removed files in the meantime.

## CNPG backups

CNPG writes base backups and WAL to Garage at `s3://postgresql/<app>`
(`https://s3.jory.dev`, see `kubernetes/components/postgres/cluster.yaml`).
Garage does not store a bucket as a plain directory, so a ZFS snapshot of a
bucket "directory" is not a usable copy. Add a second rclone remote for Garage
(e.g. `garage`, S3 endpoint `https://s3.jory.dev`) and sync bucket-to-bucket:

```sh
rclone sync garage:postgresql cloudflare-r2:postgresql \
  --fast-list \
  --transfers=64 \
  --checkers=64 \
  --retries=10 \
  --low-level-retries=20
```
