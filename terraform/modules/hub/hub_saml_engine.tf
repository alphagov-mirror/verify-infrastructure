module "saml_engine_ecs_asg" {
  source = "modules/ecs_asg"

  ami_id           = "${data.aws_ami.awslinux2.id}"
  deployment       = "${var.deployment}"
  cluster          = "saml-engine"
  vpc_id           = "${aws_vpc.hub.id}"
  instance_subnets = ["${aws_subnet.internal.*.id}"]

  number_of_instances = "${var.number_of_availability_zones}"
  domain              = "${local.root_domain}"

  additional_instance_security_group_ids = [
    "${aws_security_group.egress_via_proxy.id}",
  ]
}

data "template_file" "saml_engine_task_def" {
  template = "${file("${path.module}/files/tasks/hub-saml-engine.json")}"

  vars {
    account_id    = "${data.aws_caller_identity.account.account_id}"
    deployment    = "${var.deployment}"
    domain        = "${local.root_domain}"
    image_and_tag = "${local.tools_account_ecr_url_prefix}-verify-saml-engine:latest"
    region        = "${data.aws_region.region.id}"
  }
}

module "saml_engine" {
  source = "modules/ecs_app"

  deployment                 = "${var.deployment}"
  cluster                    = "saml-engine"
  domain                     = "${local.root_domain}"
  vpc_id                     = "${aws_vpc.hub.id}"
  lb_subnets                 = ["${aws_subnet.internal.*.id}"]
  task_definition            = "${data.template_file.saml_engine_task_def.rendered}"
  container_name             = "saml-engine"
  container_port             = "8080"
  number_of_tasks            = 1
  health_check_protocol      = "HTTP"
  health_check_path          = "/service-status"
  tools_account_id           = "${var.tools_account_id}"
  image_name                 = "verify-saml-engine"
  instance_security_group_id = "${module.saml_engine_ecs_asg.instance_sg_id}"
  certificate_arn            = "${local.wildcard_cert_arn}"
}

module "saml_engine_can_connect_to_config" {
  source = "modules/microservice_connection"

  source_sg_id      = "${module.saml_engine_ecs_asg.instance_sg_id}"
  destination_sg_id = "${module.config.lb_sg_id}"
}

module "saml_engine_can_connect_to_policy" {
  source = "modules/microservice_connection"

  source_sg_id      = "${module.saml_engine_ecs_asg.instance_sg_id}"
  destination_sg_id = "${module.policy.lb_sg_id}"
}

module "saml_engine_can_connect_to_saml_soap_proxy" {
  source = "modules/microservice_connection"

  source_sg_id      = "${module.saml_engine_ecs_asg.instance_sg_id}"
  destination_sg_id = "${module.saml_soap_proxy.lb_sg_id}"
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
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-hub-signing-private-key",
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-primary-hub-encryption-private-key",
        "arn:aws:ssm:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:parameter/${var.deployment}-secondary-hub-encryption-private-key",
        "arn:aws:kms:${data.aws_region.region.id}:${data.aws_caller_identity.account.account_id}:alias/${var.deployment}-hub-key"
      ]
    }]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "saml_engine_parameter_execution" {
  role       = "${var.deployment}-saml-engine-execution"
  policy_arn = "${aws_iam_policy.saml_engine_parameter_execution.arn}"
}
