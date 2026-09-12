resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
}

locals {
  # Fuente única: la misma estrategia va en el cluster Y en cada aws_ecs_service.
  # Si los services no la declaran, ECS igual les graba la default del cluster y
  # Terraform ve un atributo que sobra; capacity_provider_strategy fuerza
  # REEMPLAZO, así que cada apply destruía y recreaba los 6 servicios (downtime
  # completo + re-pull de todas las imágenes en cada corrida).
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE", weight = 1, base = 0 },
    { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 },
  ]
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [for c in local.capacity_provider_strategy : c.capacity_provider]

  dynamic "default_capacity_provider_strategy" {
    for_each = local.capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each          = toset(concat(["config-server", "discovery-server", "bff", "rabbitmq"], keys(var.domain_microservices), [for k in keys(var.domain_microservices) : "oracle-${k}"]))
  name              = "/ecs/${var.project}-${each.key}"
  retention_in_days = 30 # ERS.md §4.12
}
