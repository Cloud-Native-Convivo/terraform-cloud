# Sin jwt-secret: el MVP usa Entra ID + Cognito (RS256 + JWKS público) en vez de JWT HS256
# con secreto compartido (ERS.md §3.4). Cada microservicio valida el JWT contra el JWKS
# público del issuer correspondiente, no contra un secreto — no hay nada que guardar acá para eso.

# Oracle passwords para sidecar DB en cada microservicio de dominio (localhost:1521)
resource "random_password" "oracle_pwd" {
  for_each = var.domain_microservices
  length   = 24
  special  = false
}

resource "aws_secretsmanager_secret" "oracle_pwd" {
  for_each                = var.domain_microservices
  name                    = "${var.project}/oracle/${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "oracle_pwd" {
  for_each      = var.domain_microservices
  secret_id     = aws_secretsmanager_secret.oracle_pwd[each.key].id
  secret_string = random_password.oracle_pwd[each.key].result
}

# Auth para pulls de Docker Hub (rabbitmq:4-management, gvenzl/oracle-free):
# el límite anónimo se agota rápido con applies/destroys repetidos ("429 Too
# Many Requests"). Autenticado sube el límite bastante.
resource "aws_secretsmanager_secret" "dockerhub" {
  name                    = "${var.project}/dockerhub"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  secret_id = aws_secretsmanager_secret.dockerhub.id
  secret_string = jsonencode({
    username = var.docker_hub_user
    password = var.docker_hub_token
  })
}

# ---------------------------------------------------------
# Credenciales de Discovery Server (Eureka) en Producción
# ---------------------------------------------------------
resource "random_password" "discovery_pwd" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "discovery" {
  name                    = "${var.project}/discovery/password"
  description             = "Credenciales de autenticacion basica para Eureka Discovery Server"
  recovery_window_in_days = 0

  tags = {
    Service = "discovery-server"
  }
}

resource "aws_secretsmanager_secret_version" "discovery" {
  secret_id     = aws_secretsmanager_secret.discovery.id
  secret_string = random_password.discovery_pwd.result
}

# ---------------------------------------------------------
# Credenciales de Config Server (Spring Cloud Config) en Producción
# ---------------------------------------------------------
# application.yml del config-server (perfil "native", sin default) exige
# CONFIG_SERVER_USER/CONFIG_SERVER_PASSWORD para basic auth o el arranque
# aborta (PlaceholderResolutionException) -- mismo patron que discovery_pwd.
resource "random_password" "config_server_pwd" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "config_server" {
  name                    = "${var.project}/config-server/password"
  description             = "Credenciales de autenticacion basica para Spring Cloud Config Server"
  recovery_window_in_days = 0

  tags = {
    Service = "config-server"
  }
}

resource "aws_secretsmanager_secret_version" "config_server" {
  secret_id     = aws_secretsmanager_secret.config_server.id
  secret_string = random_password.config_server_pwd.result
}

# application.yml del config-server exige server.ssl.enabled = true (nunca
# desactivar en AWS, segun el comentario del propio app). El keystore PKCS12
# lo genera el sidecar config-server-tls-init (task_definitions.tf) en el
# volumen EFS compartido; esta password protege ese keystore.
resource "random_password" "ssl_keystore_pwd" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "ssl_keystore" {
  name                    = "${var.project}/config-server/ssl-keystore-password"
  description             = "Password del keystore PKCS12 self-signed de Config Server (TLS interno)"
  recovery_window_in_days = 0

  tags = {
    Service = "config-server"
  }
}

resource "aws_secretsmanager_secret_version" "ssl_keystore" {
  secret_id     = aws_secretsmanager_secret.ssl_keystore.id
  secret_string = random_password.ssl_keystore_pwd.result
}

# ---------------------------------------------------------
# RabbitMQ: un usuario por servicio con permisos mínimos
# ---------------------------------------------------------
# Antes todos compartían "convivo" con permisos totales y la password en texto
# plano en la task definition: cualquier servicio comprometido podía publicar
# reserva_espacio_creada falsos y cargar cobros a cualquier unidad. Ahora cada
# servicio solo toca sus colas/exchanges, y topic_write limita las routing keys
# que puede publicar en espacios_events (topic exchange). Los usuarios los crea
# el sidecar rabbitmq-bootstrap (task_definitions.tf) en cada arranque del broker.
# Regex con [.] en vez de \. para no pelear con el escape de HCL/JSON/shell.
locals {
  rabbitmq_usuarios = {
    "ms-espacios-comunes" = {
      env         = "RABBITMQ_PASS_ESPACIOS"
      recursos    = "^(espacios_events|gasto_fallido|reserva_pagada)$"
      topic_write = "^reserva_espacio_creada$"
    }
    "ms-gastos-comunes" = {
      env         = "RABBITMQ_PASS_GASTOS"
      recursos    = "^(espacios_events|gastos[.]dlx|gastos_reserva_creada_queue|gastos_reserva_creada_dlq)$"
      topic_write = "^(gasto_fallido|reserva_pagada)$"
    }
    # El BFF hoy solo declara el exchange (assertExchange) y no publica nada:
    # topic_write "^$" le impide publicar cualquier routing key en espacios_events.
    # Si empieza a publicar, ampliar topic_write con lo que realmente envíe.
    "bff" = {
      env         = "RABBITMQ_PASS_BFF"
      recursos    = "^espacios_events$"
      topic_write = "^$"
    }
  }
  rabbitmq_admin_user = "convivo-admin"
}

resource "random_password" "rabbitmq" {
  for_each = toset(concat(["admin"], keys(local.rabbitmq_usuarios)))
  length   = 32
  special  = false # va dentro de JSON y de la URL amqp:// del BFF sin escapar
}

resource "aws_secretsmanager_secret" "rabbitmq" {
  for_each                = random_password.rabbitmq
  name                    = "${var.project}/rabbitmq/${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  for_each      = random_password.rabbitmq
  secret_id     = aws_secretsmanager_secret.rabbitmq[each.key].id
  secret_string = each.value.result
}

# amqplib (BFF) recibe usuario y password embebidos en RABBITMQ_URLS: la URL
# completa es el secreto, no se puede armar en environment sin exponerla.
resource "aws_secretsmanager_secret" "rabbitmq_bff_url" {
  name                    = "${var.project}/rabbitmq/bff-url"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rabbitmq_bff_url" {
  secret_id     = aws_secretsmanager_secret.rabbitmq_bff_url.id
  secret_string = "amqp://bff:${random_password.rabbitmq["bff"].result}@${aws_lb.internal.dns_name}:5672"
}

# ---------------------------------------------------------
# Relay SMTP (Gmail) para la notificacion por correo de
# ms-gastos-comunes (NotificacionGastosConsumer). A diferencia de los
# secretos de arriba, este no lo genera Terraform (random_password): es
# una credencial externa (App Password de Gmail), viene de var.mail_password
# -- mismo patron que docker_hub_token/cognito_google_client_secret.
resource "aws_secretsmanager_secret" "mail_password" {
  name                    = "${var.project}/mail/password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mail_password" {
  secret_id     = aws_secretsmanager_secret.mail_password.id
  secret_string = var.mail_password
}
