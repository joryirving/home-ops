terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "garage/garage.tfstate"
    region = "ca-central-1"

    endpoints = {
      s3 = "https://garage.jory.dev"
    }

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
