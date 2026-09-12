resource "aws_ecs_service" "config_server" {
  name            = "${var.project}-config-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.config_server.arn
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.microservices.id]
    security_groups = [aws_security_group.microservices.id]
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }
}

resource "aws_ecs_service" "discovery_server" {
  name            = "${var.project}-discovery-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.discovery_server.arn
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.microservices.id]
    security_groups = [aws_security_group.microservices.id]
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }
}

resource "aws_ecs_service" "rabbitmq" {
  name            = "${var.project}-rabbitmq"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.microservices.id]
    security_groups = [aws_security_group.microservices.id]
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }
}

resource "aws_ecs_service" "bff" {
  name            = "${var.project}-bff"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bff.arn
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.microservices.id]
    security_groups = [aws_security_group.microservices.id]
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.bff.arn
    container_name   = "bff"
    container_port   = 3000
  }

  depends_on = [aws_ecs_service.config_server, aws_ecs_service.discovery_server, aws_lb_listener.bff]
}

resource "aws_ecs_service" "domain" {
  for_each        = var.domain_microservices
  name            = "${var.project}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.domain[each.key].arn
  desired_count   = 1

  network_configuration {
    subnets         = [aws_subnet.microservices.id]
    security_groups = [aws_security_group.microservices.id]
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.domain[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  depends_on = [aws_ecs_service.config_server, aws_ecs_service.discovery_server, aws_ecs_service.rabbitmq, aws_lb_listener.domain]
}
