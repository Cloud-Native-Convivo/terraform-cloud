# Reemplaza Cloud Map (bloqueado en Learner Lab: LabRole sin permiso
# servicediscovery:CreatePrivateDnsNamespace). Único consumidor real era el
# integration_uri de API Gateway hacia bff — nada más resolvía *.convivo.local.
# NLB (no ALB): la subnet de microservicios vive en una sola AZ y ALB exige
# 2+ AZs distintas; NLB no tiene esa restricción.
resource "aws_lb" "internal" {
  name               = "${var.project}-nlb-internal"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.microservices.id]
}

resource "aws_lb_target_group" "bff" {
  name        = "${var.project}-tg-bff"
  port        = 3000
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "3000"
  }
}

resource "aws_lb_listener" "bff" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 3000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bff.arn
  }
}

# Los microservicios de dominio también van por el NLB: es la única forma que
# tiene el BFF de resolverlos ahora que no hay Cloud Map (las IP de las tasks
# Fargate cambian en cada deploy). Un listener por puerto sobre el mismo NLB.
resource "aws_lb_target_group" "domain" {
  for_each    = var.domain_microservices
  name        = "${var.project}-tg-${each.key}"
  port        = each.value.port
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = tostring(each.value.port)
  }
}

resource "aws_lb_listener" "domain" {
  for_each          = var.domain_microservices
  load_balancer_arn = aws_lb.internal.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.domain[each.key].arn
  }
}
