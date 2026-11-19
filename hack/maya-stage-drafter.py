"""Stage the pinned DFlash2 drafter inside a folder, and verify it.

Runs inside a pod that mounts Maya's data claim, so the file lands where Maya's
setup looks for it and no download is needed later. Prints one line naming the
path, size and sha256; the wrapper compares those against the pins.

Exit codes: 0 verified (already there or downloaded), 1 download failed,
2 the file there is not the pinned file, 3 wrong arguments.

Stdlib only, and it streams: a 700 MB file never sits in memory.
"""

import hashlib
import os
import sys
import urllib.request

CHUNK = 1 << 20


def digest(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            block = f.read(CHUNK)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 7:
        print("usage: maya-stage-drafter.py <folder> <repo> <revision> <file> <bytes> <sha256>",
              file=sys.stderr)
        return 3
    folder, repo, revision, name, want_size, want_sha = sys.argv[1:7]
    want_size = int(want_size)
    dst = os.path.join(folder, name)
    os.makedirs(folder, exist_ok=True)

    if os.path.exists(dst) and os.path.getsize(dst) == want_size:
        got = digest(dst)
        if got == want_sha:
            print("already staged: %s size=%d sha256=%s" % (dst, want_size, got))
            return 0
        print("present but not the pinned file: %s sha256=%s expected=%s" % (dst, got, want_sha),
              file=sys.stderr)
        return 2

    url = "https://huggingface.co/%s/resolve/%s/%s" % (repo, revision, name)
    tmp = dst + ".part"
    print("downloading %.1f GB from %s" % (want_size / 1e9, url), file=sys.stderr, flush=True)
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as out:
        while True:
            block = r.read(CHUNK)
            if not block:
                break
            out.write(block)

    have = os.path.getsize(tmp)
    if have != want_size:
        print("short download: %d of %d bytes" % (have, want_size), file=sys.stderr)
        os.remove(tmp)
        return 1
    got = digest(tmp)
    if got != want_sha:
        print("sha256 mismatch: %s expected %s" % (got, want_sha), file=sys.stderr)
        os.remove(tmp)
        return 1

    os.replace(tmp, dst)
    os.chmod(dst, 0o644)
    try:
        os.chown(dst, 65534, 65534)          # Maya reads its claim as that user
    except OSError:
        pass                                 # not root here: 0644 is enough to read it
    print("staged: %s size=%d sha256=%s" % (dst, want_size, got))
    return 0


if __name__ == "__main__":
    sys.exit(main())
