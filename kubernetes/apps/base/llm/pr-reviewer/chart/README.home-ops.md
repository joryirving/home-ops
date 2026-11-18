# Vendored pr-reviewer chart

Vendored verbatim from misospace/pr-reviewer-action `deploy/charts/pr-reviewer`
at commit **1799b9f750a28764b0afc441a7e840acbfe50137** — the same commit the
pinned GHCR controller/worker images were built from, so chart and image
protocol revisions stay coordinated. The bjw-s `common` dependency is vendored
(`charts/common-5.3.0.tgz`) so local renders and home-ops CI (Image Pull /
Konflate) never need a network dependency build.

To upgrade: copy the chart from the upstream commit that matches the images
you are pinning, replace `charts/common-5.3.0.tgz`, update the image
digests in `../helmrelease.yaml`, and bump the pinned worker image in the
instance config together with the controller digest.
