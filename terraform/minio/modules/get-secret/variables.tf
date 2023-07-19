variable "bucket_name" {
  type = string
}

variable "user_name" {
  type      = string
  sensitive = true
}

variable "user_secret" {
  type      = string
  sensitive = true
}
