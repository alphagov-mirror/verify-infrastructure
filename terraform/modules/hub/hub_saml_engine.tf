locals {
  saml_engine_fargate_location_blocks = <<-LOCATIONS
  location = /prometheus/metrics {
    proxy_pass http://localhost:8081;
    proxy_set_header Host saml-engine.${local.root_domain};
  }
  location / {
    proxy_pass http://localhost:8080;
    proxy_set_header Host saml-engine.${local.root_domain};
  }
  LOCATIONS
}

module "saml_engine_fargate" {
  source = "./modules/ecs_fargate_app"

  deployment = var.deployment
  app        = "saml-engine"
  domain     = local.root_domain
  vpc_id     = aws_vpc.hub.id
  lb_subnets = aws_subnet.internal.*.id
  task_definition = templatefile("${path.module}/files/tasks/hub-saml-engine.json",
    {
      account_id                       = data.aws_caller_identity.account.account_id
      deployment                       = var.deployment
      domain                           = local.root_domain
      image_identifier                 = "${local.tools_account_ecr_url_prefix}-verify-saml-engine@${var.hub_saml_engine_image_digest}"
      nginx_image_identifier           = local.nginx_image_identifier
      region                           = data.aws_region.region.id
      location_blocks_base64           = base64encode(local.saml_engine_fargate_location_blocks)
      redis_host                       = "rediss://${aws_elasticache_replication_group.saml_engine_replay_cache.primary_endpoint_address}:6379"
      splunk_url                       = var.splunk_url
      rp_truststore_enabled            = var.rp_truststore_enabled
      certificates_config_cache_expiry = var.certificates_config_cache_expiry
      memory_hard_limit                = var.saml_engine_memory_hard_limit
      jvm_options                      = var.jvm_options
      log_level                        = var.hub_saml_engine_log_level
  })
  container_name    = "nginx"
  container_port    = "8443"
  number_of_tasks   = var.number_of_apps
  health_check_path = "/service-status"
  tools_account_id  = var.tools_account_id
  image_name        = "verify-saml-engine"
  certificate_arn   = var.wildcard_cert_arn
  ecs_cluster_id    = aws_ecs_cluster.fargate-ecs-cluster.id
  cpu               = 2048
  # for a CPU of 2048 we need to set a RAM value between 4096 and 16384 (inclusive) that is a multiple of 1024.
  memory  = ceil(max(var.saml_engine_memory_hard_limit + 250, 4096) / 1024) * 1024
  subnets = aws_subnet.internal.*.id
  additional_task_security_group_ids = [
    aws_security_group.can_connect_to_container_vpc_endpoint.id,
    aws_security_group.hub_fargate_microservice.id,
    aws_security_group.egress_via_proxy.id,
  ]
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.hub_apps.id
}

module "saml_engine_fargate_can_connect_to_config_fargate_v2" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = module.config_fargate_v2.lb_sg_id
}

module "saml_engine_fargate_can_connect_to_policy" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = module.policy.lb_sg_id
}

module "saml_engine_fargate_can_connect_to_policy_fargate" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = module.policy_fargate.lb_sg_id
}

module "saml_engine_fargate_can_connect_to_saml_soap_proxy" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = module.saml_soap_proxy.lb_sg_id
}

module "saml_engine_fargate_can_connect_to_saml_soap_proxy_fargate" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = module.saml_soap_proxy_fargate.lb_sg_id
}

resource "aws_iam_policy" "saml_engine_parameter_execution" {
  name = "${var.deployment}-saml-engine-parameter-execution"

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameters",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-hub-signing-private-key",
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-primary-hub-encryption-private-key",
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-secondary-hub-encryption-private-key",
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}/saml-engine/*",
        "arn:aws:kms:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:alias/${var.deployment}-hub-key"
      ]
    }]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "saml_engine_fargate_parameter_execution" {
  role       = "${var.deployment}-saml-engine-fargate-execution"
  policy_arn = aws_iam_policy.saml_engine_parameter_execution.arn
}

module "saml_engine_fargate_can_connect_to_saml_engine_redis" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = aws_security_group.saml_engine_redis.id
  port              = 6379
}

module "saml_engine_fargate_can_connect_to_ingress_for_metadata" {
  source = "./modules/microservice_connection"

  source_sg_id      = module.saml_engine_fargate.task_sg_id
  destination_sg_id = aws_security_group.ingress.id
}
