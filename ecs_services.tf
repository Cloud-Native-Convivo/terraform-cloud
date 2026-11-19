resource "aws_ecs_service" "config_server" {
  name            = "${var.project}-config-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.config_server.arn
  desired_count   = 1

  # El task monta el EFS del keystore: sin el mount target disponible, la task falla al iniciar.
  depends_on = [aws_efs_mount_target.config_server_keystore]

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

  depends_on = [aws_efs_mount_target.config_server_keystore]

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

  # Mismo caso que Oracle (servicio domain, abajo): el broker es un solo escritor sobre su EFS,
  # y con el rolling default la task nueva arrancaria sobre el mismo data dir que la vieja.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  availability_zone_rebalancing      = "DISABLED"

  # Margen sobre el startPeriod (60s) del healthCheck del contenedor: sin esto (default 0)
  # ECS actua sobre el health check TCP del NLB desde el primer segundo.
  health_check_grace_period_seconds = 120

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
    target_group_arn = aws_lb_target_group.rabbitmq.arn
    container_name   = "rabbitmq"
    container_port   = 5672
  }

  depends_on = [aws_lb_listener.rabbitmq, aws_efs_mount_target.rabbitmq]
}

resource "aws_ecs_service" "mailpit" {
  name            = "${var.project}-mailpit"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mailpit.arn
  desired_count   = 1

  health_check_grace_period_seconds = 60

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

  # Dos target groups: 1025 (SMTP, el que realmente usa ms-espacios-comunes
  # para enviar correo) y 8025 (bandeja web, acceso humano).
  load_balancer {
    target_group_arn = aws_lb_target_group.mailpit_smtp.arn
    container_name   = "mailpit"
    container_port   = 1025
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mailpit.arn
    container_name   = "mailpit"
    container_port   = 8025
  }

  depends_on = [aws_lb_listener.mailpit_smtp, aws_lb_listener.mailpit]
}

resource "aws_ecs_service" "bff" {
  name            = "${var.project}-bff"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bff.arn
  desired_count   = 1

  # Doble del startPeriod (90s) del healthCheck del contenedor.
  health_check_grace_period_seconds = 180

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

  depends_on = [aws_ecs_service.config_server, aws_ecs_service.discovery_server, aws_ecs_service.rabbitmq, aws_lb_listener.bff]
}

resource "aws_ecs_service" "domain" {
  for_each        = var.domain_microservices
  name            = "${var.project}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.domain[each.key].arn
  desired_count   = var.domain_desired_count

  # Oracle del sidecar es un solo escritor sobre su EFS: con el rolling default (100/200)
  # la task nueva arranca mientras la vieja tiene abierta la base y falla con ORA-00205
  # (control file tomado), asi que el deploy nunca termina. Parar la vieja antes de
  # levantar la nueva cuesta un corte breve por deploy, pero el deploy converge.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  # ECS rechaza maximumPercent <= 100 con el rebalanceo de AZ activo (default del provider 6.x).
  # Las tasks corren en una sola subnet, asi que el rebalanceo no tiene a donde mover nada.
  availability_zone_rebalancing = "DISABLED"

  # El contenedor de la app recien arranca con Oracle HEALTHY (dependsOn): primer boot hasta
  # ~450s (startPeriod 300 + 5x30 del sidecar) mas el startPeriod de 120s de la app. Con el
  # default 0, el health check TCP del NLB la marca unhealthy a ~90s y ECS reemplaza la task
  # antes de que Oracle termine, en loop.
  health_check_grace_period_seconds = 600

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

  depends_on = [aws_ecs_service.config_server, aws_ecs_service.discovery_server, aws_ecs_service.rabbitmq, aws_ecs_service.mailpit, aws_lb_listener.domain, aws_efs_mount_target.oracle]
}
