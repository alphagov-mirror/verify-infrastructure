
resource "aws_security_group" "metadata_task" {
  name        = "${var.deployment}-metadata-task"
  description = "${var.deployment}-metadata-task"

  vpc_id = aws_vpc.hub.id

  count = var.manage_metadata
}

data "template_file" "metadata_task_def" {
  template = file("${path.module}/files/tasks/metadata.json")

  vars = {
    deployment       = var.deployment
    region           = data.aws_region.region.id
    image_identifier = "${local.tools_account_ecr_url_prefix}-verify-metadata@${var.hub_metadata_image_digest}"
  }
}

module "metadata_ecs_roles" {
  source = "./modules/ecs_iam_role_pair"

  deployment       = var.deployment
  service_name     = "metadata"
  tools_account_id = var.tools_account_id
  image_name       = "verify-metadata"

  count = var.manage_metadata
}

resource "aws_ecs_task_definition" "metadata_fargate" {
  family                   = "${var.deployment}-metadata-fargate"
  container_definitions    = data.template_file.metadata_task_def.rendered
  network_mode             = "awsvpc"
  execution_role_arn       = module.metadata_ecs_roles.execution_role_arn
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  count = var.manage_metadata
}

resource "aws_ecs_service" "metadata_fargate" {
  name            = "${var.deployment}-metadata"
  cluster         = aws_ecs_cluster.fargate-ecs-cluster.id
  task_definition = aws_ecs_task_definition.metadata_fargate.arn

  desired_count                      = var.number_of_metadata_apps
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 100

  launch_type = "FARGATE"

  count = var.manage_metadata

  load_balancer {
    target_group_arn = aws_lb_target_group.ingress_metadata.arn
    container_name   = "nginx"
    container_port   = "8443"
  }

  network_configuration {
    subnets = aws_subnet.internal.*.id
    security_groups = [
      aws_security_group.metadata_task.id,
      aws_security_group.hub_fargate_microservice.id,
      aws_security_group.can_connect_to_container_vpc_endpoint.id,
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

  count = var.manage_metadata

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.hub_apps.id

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
