terraform {
  backend "kubernetes" {
    secret_suffix     = "state"
    in_cluster_config = true
    namespace         = "kube-tools"
  }
}
