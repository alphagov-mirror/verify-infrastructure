resource "aws_lb" "app" {
  load_balancer_type = "application"

  name            = var.deployment != "integration" ? "${local.identifier}-fargate" : "${local.identifier}-fg"
  internal        = true
  security_groups = [aws_security_group.lb.id]
  subnets         = var.lb_subnets

  tags = {
    Deployment = var.deployment
  }
}

resource "aws_lb_target_group" "task" {
  name                 = var.deployment != "integration" ? "${local.identifier}-fargate" : "${local.identifier}-fg"
  port                 = "8443"
  protocol             = "HTTPS"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 15
  slow_start           = 30

  health_check {
    path     = var.health_check_path
    protocol = var.health_check_protocol
    interval = var.health_check_interval
    timeout  = var.health_check_timeout
    matcher  = var.health_check_http_codes
  }

  depends_on = [
    aws_lb.app,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-1-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.task.arn
  }
}
