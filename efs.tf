resource "aws_security_group" "efs" {
  name        = "${var.project}-sg-efs"
  description = "Permite acceso NFS desde las tasks en Fargate"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS desde subnet de microservicios"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.microservices.id]
  }

  tags = { Name = "${var.project}-sg-efs" }
}

# EFS para RabbitMQ
resource "aws_efs_file_system" "rabbitmq" {
  creation_token = "${var.project}-rabbitmq-efs"
  encrypted      = true
  tags = {
    Name = "${var.project}-rabbitmq-efs"
  }
}

resource "aws_efs_mount_target" "rabbitmq" {
  file_system_id  = aws_efs_file_system.rabbitmq.id
  subnet_id       = aws_subnet.microservices.id
  security_groups = [aws_security_group.efs.id]
}

# EFS para Oracle (cada microservicio)
resource "aws_efs_file_system" "oracle" {
  for_each       = var.domain_microservices
  creation_token = "${var.project}-oracle-${each.key}-efs"
  encrypted      = true
  tags = {
    Name = "${var.project}-oracle-${each.key}-efs"
  }
}

resource "aws_efs_mount_target" "oracle" {
  for_each        = var.domain_microservices
  file_system_id  = aws_efs_file_system.oracle[each.key].id
  subnet_id       = aws_subnet.microservices.id
  security_groups = [aws_security_group.efs.id]
}
