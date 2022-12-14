################################################################################
# ECS
################################################################################

resource "aws_ecs_task_definition" "task_definition" {
  family                    = var.name
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  cpu                       = var.cpu
  memory                    = var.memory
  container_definitions     = local.container_definitions
  execution_role_arn        = var.execution_role_arn
  task_role_arn             = var.task_role_arn
  tags                      = var.tags

  dynamic "volume" {
    for_each = var.efs_volumes

    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.fs_id
        transit_encryption      = "ENABLED"

        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }
}

resource "aws_ecs_service" "service" {
  name                = var.name
  cluster             = var.cluster_id
  task_definition     = aws_ecs_task_definition.task_definition.arn
  launch_type         = "FARGATE"
  desired_count       = var.desired_count
  tags                = var.tags

  dynamic "load_balancer" {
    for_each = local.assign_domain_name ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.target_group[0].arn
      container_name   = var.name
      container_port   = var.port
    }
  }

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = var.security_groups
    assign_public_ip  = var.assign_public_ip
  }
  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
    ignore_changes        = [desired_count]
  }
  deployment_controller {
    type = "ECS"
  }
}


################################################################################
# Load balancer
################################################################################

resource "aws_lb_target_group" "target_group" {
  count       = local.assign_domain_name ? 1 : 0

  name        = "${var.name}-lb-tg"
  port        = var.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    interval              = 300
    healthy_threshold     = 5
    unhealthy_threshold   = 2
    path                  = var.health_check_path
    port                  = var.health_check_port
    matcher               = var.health_check_matcher
  }
}

resource "aws_lb_listener_rule" "lb_rule" {
  count         = local.assign_domain_name ? 1 : 0

  listener_arn  = var.lb_listener_arn
  priority      = var.lb_listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group[0].arn
  }

  condition {
    host_header {
      values = concat([var.domain_name], var.additional_domain_names)
    }
  }
}


################################################################################
# CloudWatch
################################################################################

resource "aws_cloudwatch_log_group" "log_group" {
  name              = var.name
  retention_in_days = var.cloudwatch_logs_retention_period

  tags = var.tags
}