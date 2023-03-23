# LDS home k8s cluster

<div align="center">

[![Discord](https://img.shields.io/discord/673534664354430999?color=7289da&label=DISCORD&style=for-the-badge&logo=discord)](https://discord.gg/k8s-at-home 'k8s at home Discord Community')
[![GitHub stars](https://img.shields.io/github/stars/lildrunkensmurf/k3s-home-cluster?color=green&style=for-the-badge)](https://github.com/Truxnell/home-cluster/stargazers 'This repo star count')
[![GitHub last commit](https://img.shields.io/github/last-commit/lildrunkensmurf/k3s-home-cluster?color=purple&style=for-the-badge)](https://github.comLilDrunkenSmurf/k3s-home-cluster/commits/main 'Commit History')\
[![Release](https://img.shields.io/github/v/release/lildrunkensmurf/k3s-home-cluster?style=for-the-badge)](https://github.com/lildrunkensmurf/k3s-home-cluster/releases 'Repo releases')
  
</div>

## Overview

This repository is for my home K3s cluster, which is a lightweight version of K8s. It's based off of the k8s-at-home [flux template](https://github.com/onedr0p/flux-cluster-template).
It's supported by [k3s](https://k3s.io) cluster with [Ansible](https://www.ansible.com) and [Terraform](https://www.terraform.io) backed by [Flux](https://toolkit.fluxcd.io/) and [SOPS](https://toolkit.fluxcd.io/guides/mozilla-sops/).

The purpose here is to learn k8s, while practicing Gitops.

## 🔧 Hardware

| Device                    | Count | OS Disk Size | Data Disk Size              | Ram   | Operating System     | Purpose             |
|---------------------------|-------|--------------|-----------------------------|-------|----------------------|---------------------|
| HP z820 Workstation.      | 1     | 32GB USB3.0  | ZFS 26TB w/ 2 disk Parity   | 128GB | Unraid               | NAS + NFS + Backup  |
| Virtual Machine (16 Core) | 1     | 100GB vDisk  | -                           | 32GB  | Ubuntu               | Kubernetes Master   |
| Beelink Mini-S            | 1     | 250GB SSD    | 250GB M.2 SSD               | 16GB  | Ubuntu               | Kubernetes Master   |
| Raspberry Pi 4            | 1     | 240GB SSD    | -                           | 8GB   | Raspbian Lite 64-bit | Kubernetes Master   |
| Raspberry Pi 4            | 2     | 240GB SSD    | -                           | 4GB   | Raspbian Lite 64-bit | Kubernetes Worker   |
| APC Smart-UPS 750         | 1     | -            | -                           | -     | -                    | UPS - Unraid        |
| APC Back-UPS 600          | 1     | -            | -                           | -     | -                    | UPS - K8s + Network |
| Unifi UDM Base            | 1     | -            | -                           | -     | Unifi OS             | Router              |

## 🤝 Thanks

Big shout out to original flux template, and the k8s-at-home discord.

[@whazor](https://github.com/whazor) created [this website](https://nanne.dev/k8s-at-home-search/) as a creative way to search Helm Releases across GitHub. You may use it as a means to get ideas on how to configure an applications' Helm values.
