variable "aws_region" {
  type    = string
  default = "eu-west-1"
}
variable "jwt_issuer_url" {
  type = string
}
variable "jwt_audience" {
  type = string
}
variable "list_users_lambda_arn" {
  type = string
}
variable "list_users_lambda_name" {
  type = string
}
