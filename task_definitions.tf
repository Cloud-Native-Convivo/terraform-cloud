locals {
  entra_issuer = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"
  entra_jwks   = "https://login.microsoftonline.com/${var.entra_tenant_id}/discovery/v2.0/keys"

  cognito_issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.residentes.id}"
  cognito_jwks   = "${local.cognito_issuer}/.well-known/jwks.json"

  # Env comunes a todo microservicio de dominio + bff: permiten revalidar el JWT de CUALQUIERA
  # de los dos issuers a nivel de servicio (defensa en profundidad, mvp.md RF-T.4), sin secreto
  # compartido — cada servicio decide según el issuer del token cuál JWKS usar.
  entra_env = [
    { name = "ENTRA_TENANT_ID", value = var.entra_tenant_id },
    { name = "ENTRA_AUDIENCE", value = var.entra_audience },
    { name = "ENTRA_ISSUER", value = local.entra_issuer },
    { name = "ENTRA_JWKS_URI", value = local.entra_jwks },
  ]

  cognito_env = [
    { name = "COGNITO_USER_POOL_ID", value = aws_cognito_user_pool.residentes.id },
    { name = "COGNITO_APP_CLIENT_ID", value = aws_cognito_user_pool_client.residentes.id },
    { name = "COGNITO_ISSUER", value = local.cognito_issuer },
    { name = "COGNITO_JWKS_URI", value = local.cognito_jwks },
  ]

  identity_env = concat(local.entra_env, local.cognito_env)

  # Única PDB que sirve la imagen gvenzl/oracle-free. Vale para los dos
  # microservicios: cada uno corre su propia instancia como sidecar.
  oracle_pdb = "FREEPDB1"

  # Oracle sidecar config por microservicio de dominio
  oracle_env = {
    "ms-espacios-comunes" = {
      db_name = "espacios_db"
      db_user = "espacios_user"
    }
    "ms-gastos-comunes" = {
      db_name = "gastos_db"
      db_user = "gastos_user"
    }
  }
}

# ponytail: healthCheck asume un endpoint HTTP GET /health en cada contenedor (framework-agnostic).

resource "aws_ecs_task_definition" "config_server" {
  family                   = "${var.project}-config-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([
    {
      name  = "config-server"
      image = "docker.io/${var.docker_hub_user}/config-server-cloud:latest"
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      portMappings = [{ containerPort = 8888, protocol = "tcp" }]
      environment  = []
      secrets      = []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service["config-server"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8888/actuator/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])
}

resource "aws_ecs_task_definition" "discovery_server" {
  family                   = "${var.project}-discovery-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([
    {
      name  = "discovery-server"
      image = "docker.io/${var.docker_hub_user}/discovery-server-cloud:latest"
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      portMappings = [{ containerPort = 8761, protocol = "tcp" }]
      environment  = []
      secrets      = []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service["discovery-server"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8761/actuator/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])
}
# config-server y discovery-server son Java/Spring Boot fijo (mvp.md §4.13 — sin equivalente
# servidor en otro lenguaje del stack), por eso su healthCheck usa /actuator/health directo.
# TD-12 (mvp.md) cerrado: separados también en la infraestructura real, ya no unificados.

resource "aws_ecs_task_definition" "rabbitmq" {
  family                   = "${var.project}-rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  # Volumen Docker-managed (no EFS, sigue efímero) montado en /var/lib/rabbitmq:
  # el overlay filesystem por defecto de Fargate da eacces al intentar
  # leer/escribir .erlang.cookie ahí (bug conocido de la imagen oficial en
  # Fargate); un volumen propio evita ese overlay y soluciona el permiso.
  volume {
    name = "rabbitmq-data"
  }

  container_definitions = jsonencode([
    {
      name  = "rabbitmq"
      image = "docker.io/library/rabbitmq:4-management"
      user  = "0" # root: Fargate recorta capabilities que el entrypoint necesita para el privilege-drop a rabbitmq, causando eacces en .erlang.cookie pase lo que pase con volumen/env
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      mountPoints = [
        { sourceVolume = "rabbitmq-data", containerPath = "/var/lib/rabbitmq" },
      ]
      portMappings = [
        { containerPort = 5672, protocol = "tcp" },
        { containerPort = 15672, protocol = "tcp" },
      ]
      environment = [
        # sin esto, el entrypoint falla con "Error when reading
        # /var/lib/rabbitmq/.erlang.cookie: eacces" en el filesystem efímero
        # de Fargate al intentar autogenerarlo (bug conocido de la imagen
        # oficial en Fargate). Nodo único, sin clustering: no es secreto real.
        { name = "RABBITMQ_ERLANG_COOKIE", value = "convivo-rabbitmq-cookie" },
      ]
      secrets = []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service["rabbitmq"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "rabbitmq-diagnostics -q ping || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}
# mvp.md TD-11: self-hosted en Fargate, sin volumen persistente (sin EFS) — un restart/deploy
# vacía la cola por completo. Imagen oficial de Docker Hub, no requiere build propio.

resource "aws_ecs_task_definition" "bff" {
  family                   = "${var.project}-bff"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([
    {
      name  = "bff"
      image = "docker.io/${var.docker_hub_user}/bff-convivo:develop" # ponytail: main sin CI de Docker todavia (12 commits atras), usar :latest cuando se mergee develop->main
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      environment = concat(local.identity_env, [
        { name = "PORT", value = "3000" },
        { name = "NODE_ENV", value = "production" },
        # Sin estos el BFF cae a su default localhost:808x y el reverse proxy
        # no llega a ningún lado. El BFF les agrega el path (/api/v1/... para
        # espacios), así que acá va solo la base.
        { name = "ESPACIOS_COMUNES_URL", value = "http://${aws_lb.internal.dns_name}:${var.domain_microservices["ms-espacios-comunes"].port}" },
        { name = "GASTOS_COMUNES_URL", value = "http://${aws_lb.internal.dns_name}:${var.domain_microservices["ms-gastos-comunes"].port}" },
        # Default del BFF son 2s: arranque en frío de JVM/Oracle lo supera y
        # abre el circuit breaker antes de que el downstream llegue a responder.
        { name = "PROXY_TIMEOUT_MS", value = "10000" },
      ])
      secrets = []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service["bff"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000/api/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 90
      }
    }
  ])
}
# BFF en NestJS 12 / TypeScript (puerto 3000, health en /health). CPU/memory subidos para Node.js.

resource "aws_ecs_task_definition" "domain" {
  for_each                 = var.domain_microservices
  family                   = "${var.project}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024" # JVM + Oracle Free comparten el task; 512/1024 causaba OOM (ORA-01092, exit 137) en el arranque de Oracle
  memory                   = "3072"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = each.key == "ms-gastos-comunes" ? "docker.io/${var.docker_hub_user}/${each.key}:develop" : "docker.io/${var.docker_hub_user}/${each.key}:latest" # ponytail: ms-gastos-comunes main sin CI todavia, usar :latest cuando se mergee develop->main
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
      # ECS arranca los contenedores del task en paralelo. Oracle tarda ~3 min en
      # el primer boot, así que la app intentaba crear el esquema contra una BD
      # que todavía no escuchaba; el error queda atrapado en un try/except que
      # solo loguea warning, y el servicio seguía vivo pero sin tablas
      # (ORA-00942 en cada query). Esperar a que el sidecar esté HEALTHY.
      dependsOn = [
        { containerName = "oracle", condition = "HEALTHY" },
      ]
      environment = concat(
        local.identity_env,
        [
          { name = "RABBITMQ_HOST", value = "rabbitmq.convivo.local" },
          { name = "DB_HOST", value = "localhost" },
          { name = "DB_PORT", value = "1521" },
          # DB_NAME es el service name del DSN, no un nombre lógico: la imagen
          # gvenzl/oracle-free solo sirve la PDB FREEPDB1. Con "espacios_db"
          # (el valor viejo, de cuando se pensaba en RDS separadas) el connect
          # falla con ORA-12514, service name desconocido.
          { name = "DB_NAME", value = local.oracle_pdb },
          # DB_USERNAME, no DB_USER: es el nombre que leen las dos apps
          # (pydantic-settings en espacios, spring.datasource.username en gastos).
          { name = "DB_USERNAME", value = local.oracle_env[each.key].db_user },
          # Solo lo lee ms-gastos (Java/JDBC); el de espacios lo ignora.
          { name = "DB_URL", value = "jdbc:oracle:thin:@//localhost:1521/${local.oracle_pdb}" },
        ],
        [for k, v in lookup(var.service_env_vars, each.key, {}) : { name = k, value = v }]
      )
      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.oracle_pwd[each.key].arn },
        { name = "ORACLE_PWD", valueFrom = aws_secretsmanager_secret.oracle_pwd[each.key].arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}${each.value.health_path} || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    },
    {
      name  = "oracle"
      image = "docker.io/gvenzl/oracle-free:23-slim-faststart"
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      portMappings = [{ containerPort = 1521, protocol = "tcp" }]
      # APP_USER: sin esto la imagen solo crea SYS/SYSTEM, y el usuario con el
      # que se conecta la app (espacios_user / gastos_user) no existe ->
      # ORA-01017 invalid username/password. gvenzl lo crea dentro de la PDB.
      environment = [
        { name = "APP_USER", value = local.oracle_env[each.key].db_user },
      ]
      secrets = [
        { name = "ORACLE_PASSWORD", valueFrom = aws_secretsmanager_secret.oracle_pwd[each.key].arn }, # requerido por la imagen gvenzl/oracle-free para el primer arranque
        # ponytail: misma password para SYS y para el usuario de app. La BD es un
        # sidecar en localhost del mismo task, no accesible desde afuera, así que
        # el blast radius es esa task. Separar en dos secrets si algún día la BD
        # deja de ser sidecar.
        { name = "APP_USER_PASSWORD", valueFrom = aws_secretsmanager_secret.oracle_pwd[each.key].arn },
        { name = "ORACLE_PWD", valueFrom = aws_secretsmanager_secret.oracle_pwd[each.key].arn }, # usado por el healthCheck (sqlplus sys/$ORACLE_PWD@...)
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.service["oracle-${each.key}"].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        # Comprueba que vuelva una fila de verdad, no el exit code de sqlplus:
        # sqlplus devuelve 0 aunque el login falle, así que el check anterior
        # daba HEALTHY a los ~87s (con la BD todavía cerrada) y el dependsOn de
        # la app esperaba sobre un falso positivo. Se conecta con el usuario de
        # aplicación a propósito: se crea al final del init, así que es la señal
        # exacta de "la BD ya sirve para la app".
        # healthcheck.sh es el que trae la propia imagen gvenzl (el que declara en
        # su HEALTHCHECK); sabe distinguir "instancia arriba" de "PDB abierta y
        # usable", cosa que un sqlplus suelto no hace: sqlplus devuelve 0 aunque
        # el login falle, y con ese falso positivo el dependsOn de la app
        # arrancaba contra una BD cerrada. Fallback por si cambia la ruta.
        command     = ["CMD-SHELL", "$ORACLE_BASE/healthcheck.sh || (echo 'SELECT 1 FROM DUAL;' | sqlplus -s -L system/$ORACLE_PASSWORD@localhost:1521/${local.oracle_pdb} | grep -q '^ *1$')"]
        interval    = 30
        timeout     = 15
        retries     = 5 # 300s de startPeriod (máximo que permite ECS) + 5x30s de reintentos = ~450s de margen para el primer boot
        startPeriod = 300
      }
    }
  ])
}