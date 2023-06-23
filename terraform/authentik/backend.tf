terraform {
  backend "kubernetes" {
    secret_suffix     = "state"
    in_cluster_config = true
    namespace         = "flux-system"
    #config_path   = "~/.kube/config"
  }
}
