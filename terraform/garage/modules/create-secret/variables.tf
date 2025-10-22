variable "name" {
  type        = string
  description = "Secret name"
}

variable "username" {
  type        = string
  description = "Secret username"
}

variable "password" {
  type        = string
  description = "Secret password"
}

variable "onepassword_vault" {
  type        = string
  description = "Name of the 1password vault"
}
