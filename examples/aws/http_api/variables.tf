variable "aws_region" {
  type    = string
  default = "eu-west-1"
}
variable "coppice_issuer_url" {
  type = string
}
variable "contact_lambda_arn" {
  type = string
}
variable "contact_lambda_name" {
  type = string
}
variable "newsletter_lambda_arn" {
  type = string
}
variable "newsletter_lambda_name" {
  type = string
}
variable "custom_domain_name" {
  type    = string
  default = null
}
variable "custom_domain_certificate_arn" {
  type    = string
  default = null
}
variable "route53_zone_id" {
  type    = string
  default = null
}
