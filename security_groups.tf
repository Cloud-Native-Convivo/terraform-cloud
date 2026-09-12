# Sin SG de frontend: el frontend se queda en GitHub Pages, no en AWS (decisión del equipo).
# La subnet pública/NAT siguen existiendo solo para salida a internet de la subnet privada.

resource "aws_security_group" "microservices" {
  name        = "${var.project}-sg-microservices"
  description = "SG for internal microservices, self-referencing (BFF-MS, Oracle sidecar, VPC Link de API Gateway)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-sg-microservices" }
}

resource "aws_security_group_rule" "microservices_self_ingress" {
  # bff, config-server, discovery-server, rabbitmq (AMQP + management UI) + puertos de los
  # microservicios de dominio (dinámico vía var.domain_microservices) + Oracle sidecar (1521)
  for_each = toset(concat(
    ["3000", "8888", "8761", "5672", "15672", "1521"],
    [for k, v in var.domain_microservices : tostring(v.port)]
  ))

  # Fuente = CIDR de la subnet, no el propio SG: las ENI del NLB interno no
  # pertenecen a ningún security group, así que con una regla self-referencing
  # sus health checks quedan bloqueados y el target nunca pasa a healthy.
  # Esa subnet es privada y solo contiene recursos nuestros (tasks ECS, ENI del
  # NLB, ENI del VPC Link), así que la CIDR no abre nada de más.
  type              = "ingress"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  security_group_id = aws_security_group.microservices.id
  cidr_blocks       = [var.microservices_subnet_cidr]
}