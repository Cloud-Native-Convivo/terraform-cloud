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

# Sin access point, la raiz del EFS queda root:root 755 al montarse -- la
# imagen gvenzl/oracle-free corre como uid=54321(oracle) gid=54321(oinstall)
# (verificado con `docker run ... id`) y no puede escribir ahi ("mkdir:
# Permission denied" en /opt/oracle/oradata/dbconfig). El access point fuerza
# que EFS cree/trate la raiz montada con ese owner.
resource "aws_efs_access_point" "oracle" {
  for_each       = var.domain_microservices
  file_system_id = aws_efs_file_system.oracle[each.key].id

  posix_user {
    uid = 54321
    gid = 54321
  }

  root_directory {
    path = "/oradata"
    creation_info {
      owner_uid   = 54321
      owner_gid   = 54321
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.project}-oracle-${each.key}-ap"
  }
}

# EFS para el keystore TLS de Config Server (ver secrets.tf ssl_keystore y
# task_definitions.tf sidecar config-server-tls-init).
resource "aws_efs_file_system" "config_server_keystore" {
  creation_token = "${var.project}-config-server-keystore-efs"
  encrypted      = true
  tags = {
    Name = "${var.project}-config-server-keystore-efs"
  }
}

resource "aws_efs_mount_target" "config_server_keystore" {
  file_system_id  = aws_efs_file_system.config_server_keystore.id
  subnet_id       = aws_subnet.microservices.id
  security_groups = [aws_security_group.efs.id]
}

# uid=100(appuser) gid=101(appgroup) -- verificado con `docker run ...
# marceloriv/config-server-cloud id` (adduser -S de Alpine, estable mientras
# no cambie el orden de creacion de usuarios en el Dockerfile).
resource "aws_efs_access_point" "config_server_keystore" {
  file_system_id = aws_efs_file_system.config_server_keystore.id

  posix_user {
    uid = 100
    gid = 101
  }

  root_directory {
    path = "/keystore"
    creation_info {
      owner_uid   = 100
      owner_gid   = 101
      permissions = "0700"
    }
  }

  tags = {
    Name = "${var.project}-config-server-keystore-ap"
  }
}
