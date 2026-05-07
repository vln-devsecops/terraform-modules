variable "domain_name" {
  type = string
}

variable "subject_alt_names" {
  type    = list(string)
  default = []
}

variable "route53_zone_id" {
  type = string
}
