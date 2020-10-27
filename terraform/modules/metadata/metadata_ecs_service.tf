data "aws_region" "region" {}

data "terraform_remote_state" "hub" {
  backend = "s3"

  config {
    bucket = "govukverify-tfstate-${var.deployment}"
    key    = "hub.tfstate"
    region = "eu-west-2"
  }
}

data "template_file" "metadata_task_def" {
  template = file("${path.module}/files/metadata.json")

  vars = {
    deployment       = var.deployment
    region           = data.aws_region.region.id
    image_identifier = "${var.tools_account_id}.dkr.ecr.eu-west-2.amazonaws.com/platform-deployer-verify-metadata@${var.hub_metadata_image_digest}"
  }
}


module "metadata_ecs_roles" {
  source = "../hub/modules/ecs_iam_role_pair"

  deployment       = var.deployment
  service_name     = "metadata"
  tools_account_id = var.tools_account_id
  image_name       = "verify-metadata"
}

resource "aws_security_group" "metadata_task" {
  name        = "${var.deployment}-metadata-task"
  description = "${var.deployment}-metadata-task"

  vpc_id = data.terraform_remote_state.hub.outputs.vpc_id
}

resource "aws_ecs_task_definition" "metadata_fargate" {
  family                   = "${var.deployment}-metadata-fargate"
  container_definitions    = data.template_file.metadata_task_def.rendered
  network_mode             = "awsvpc"
  execution_role_arn       = module.metadata_ecs_roles.execution_role_arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
}

resource "aws_lb_target_group" "ingress_metadata" {
  name                 = "${var.deployment}-ingress-metadata"
  port                 = 8443
  protocol             = "HTTPS"
  vpc_id               = data.terraform_remote_state.hub.outputs.vpc_id
  target_type          = "ip"
  deregistration_delay = 60
  slow_start           = 30

  health_check {
    path     = "/healthcheck"
    protocol = "HTTPS"
    interval = 10
    timeout  = 5
  }
}

resource "aws_lb_listener_rule" "ingress_metadata" {
  listener_arn = data.terraform_remote_state.hub.outputs.ingress_https_lb_listener_arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_metadata.arn
  }

  condition {
    path_pattern {
      values = ["/SAML2/metadata/*"]
    }
  }
}


resource "aws_ecs_service" "metadata_fargate" {
  name            = "${var.deployment}-metadata"
  cluster         = data.terraform_remote_state.hub.outputs.fargate_ecs_cluster_id
  task_definition = aws_ecs_task_definition.metadata_fargate.arn

  desired_count                      = var.number_of_metadata_apps
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 100

  launch_type = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.ingress_metadata.arn
    container_name   = "nginx"
    container_port   = "8443"
  }

  network_configuration {
    subnets =  data.terraform_remote_state.hub.outputs.internal_subnet_ids
    security_groups = [
      aws_security_group.metadata_task.id,
      data.terraform_remote_state.hub.outputs.hub_fargate_microservice_security_group_id,
      data.terraform_remote_state.hub.outputs.can_connect_to_container_vpc_endpoint,
    ]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.metadata_fargate.arn
    port         = 8443
  }
}

resource "aws_service_discovery_service" "metadata_fargate" {
  name = "${var.deployment}-metadata"

  description = "service discovery for ${var.deployment}-metadata-fargate instances"

  dns_config {

      namespace_id = data.terraform_remote_state.hub.outputs.hub_apps_private_dns_namespace_id

    dns_records {
      ttl  = 60
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 2
  }
}
