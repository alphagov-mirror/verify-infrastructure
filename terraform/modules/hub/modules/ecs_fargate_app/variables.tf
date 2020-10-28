variable "app" {}
variable "container_name" {}
variable "container_port" {}
variable "deployment" {}
variable "domain" {}
variable "task_definition" {}
variable "vpc_id" {}
variable "tools_account_id" {}
variable "certificate_arn" {}

variable "image_name" {
  default = ""
}

variable "lb_subnets" {
  type = list
}

locals {
  identifier = "${var.deployment}-${var.app}"
}

variable "number_of_tasks" {
  default = 2
}

variable "deployment_min_healthy_percent" {
  default = 50
}

variable "deployment_max_percent" {
  default = 100
}

variable "health_check_path" {
  default = "/"
}

variable "health_check_protocol" {
  default = "HTTPS"
}

variable "health_check_interval" {
  default = 10
}

variable "health_check_timeout" {
  default = 5
}

variable "health_check_http_codes" {
  default = "200"
}

variable "ecs_cluster_id" {
  type = string
}

variable "cpu" {
  type = number
}

variable "memory" {
  type = number
}

variable "subnets" {
  type = list(string)
}

variable "additional_task_security_group_ids" {
  type = list(string)
}

variable "service_discovery_namespace_id" {
  type = string
}
