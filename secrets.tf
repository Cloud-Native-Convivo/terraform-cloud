# Sin jwt-secret: el MVP usa Entra ID + Cognito (RS256 + JWKS público) en vez de JWT HS256
# con secreto compartido (mvp.md §3.4). Cada microservicio valida el JWT contra el JWKS
# público del issuer correspondiente, no contra un secreto — no hay nada que guardar acá para eso.

# Oracle passwords para sidecar DB en cada microservicio de dominio (localhost:1521)
resource "random_password" "oracle_pwd" {
  for_each = var.domain_microservices
  length   = 24
  special  = false
}

resource "aws_secretsmanager_secret" "oracle_pwd" {
  for_each = var.domain_microservices
  name     = "${var.project}/oracle/${each.key}"
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
  name = "${var.project}/dockerhub"
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  secret_id = aws_secretsmanager_secret.dockerhub.id
  secret_string = jsonencode({
    username = var.docker_hub_user
    password = var.docker_hub_token
  })
}