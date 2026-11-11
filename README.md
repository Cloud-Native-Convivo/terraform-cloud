# Infraestructura en AWS con Terraform - Convivo

## Descripción

Módulo de Infraestructura como Código (IaC) desarrollado en Terraform para el aprovisionamiento de la arquitectura cloud de Convivo en Amazon Web Services (AWS), región `us-east-1`. Diseñado para ejecutarse sobre una cuenta de AWS Academy Learner Lab utilizando el rol preexistente `LabRole`.

Recursos aprovisionados:

- Red y Conectividad: VPC CIDR `10.0.0.0/16`, Internet Gateway, NAT Gateway en subnet pública (`10.0.1.0/24`), subnets privadas para microservicios (`10.0.2.0/24`) y bases de datos (`10.0.3.0/24`), junto con sus tablas de ruteo asociadas.
- Seguridad Perimetral: Security Groups con reglas de ingress acotadas a la subnet de microservicios y puertos específicos de servicios.
- Balanceo Interno: Network Load Balancer (NLB) interno con VPC Link integrado a API Gateway y Target Groups para BFF (puerto 3000), RabbitMQ (puerto 5672) y microservicios de dominio (puertos 8082, 8083, 8084 y 8085).
- API Gateway: HTTP API v2 con VPC Link y Lambda Authorizer (`jwt-basico`) en Python para residentes, y authorizer JWT OIDC para Azure Entra ID orientado al panel administrativo.
- Cómputo (ECS Fargate): Clúster ECS con capacity provider strategy (`FARGATE` y `FARGATE_SPOT`), CloudWatch Log Groups y servicios contenerizados: `config-server`, `discovery-server`, `rabbitmq`, `bff`, y microservicios de dominio (`ms-espacios-comunes`, `ms-gastos-comunes`, `ms-condominios`, `ms-usuario-cloud`) configurados con sidecar local de base de datos Oracle Database Free 23ai (`gvenzl/oracle-free:slim-faststart`).
- Gestión de Identidad: Amazon Cognito User Pool (`residentes`) con Identity Provider federado Google y cliente de aplicación con flujo OAuth2 Authorization Code + PKCE.
- Secretos: AWS Secrets Manager para almacenamiento de credenciales de Docker Hub y contraseñas generadas de Oracle Database.

---

## Sintaxis / Interfaz

### Variables de Entrada (`variables.tf`)

| Variable | Tipo | Valor por Defecto | Descripción |
| --- | --- | --- | --- |
| `aws_region` | `string` | `"us-east-1"` | Región de AWS para el despliegue. |
| `project` | `string` | `"convivo"` | Prefijo aplicado a nombres de recursos. |
| `docker_hub_user` | `string` | *(requerido)* | Usuario de Docker Hub donde residen las imágenes del proyecto. |
| `docker_hub_token` | `string` (sensible) | *(requerido)* | Access token de Docker Hub para pull autenticado sin límites anónimos. |
| `entra_tenant_id` | `string` | *(requerido)* | Tenant ID (GUID) de Azure Entra ID para issuer OIDC. |
| `entra_audience` | `string` | *(requerido)* | Application ID de Azure Entra ID para validación de audience en JWT Authorizer. |
| `cognito_google_client_id` | `string` | *(requerido)* | Client ID OAuth de Google Cloud Console para IdP federado. |
| `cognito_google_client_secret` | `string` (sensible) | *(requerido)* | Client Secret OAuth de Google Cloud Console. |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | Bloque CIDR de la VPC principal. |
| `public_subnet_cidr` | `string` | `"10.0.1.0/24"` | Bloque CIDR de la subnet pública (NAT Gateway). |
| `microservices_subnet_cidr` | `string` | `"10.0.2.0/24"` | Bloque CIDR de la subnet privada de microservicios. |
| `db_subnet_cidr` | `string` | `"10.0.3.0/24"` | Bloque CIDR de la subnet privada de base de datos. |
| `availability_zone_a` | `string` | `"us-east-1a"` | Zona de disponibilidad primaria. |
| `availability_zone_b` | `string` | `"us-east-1b"` | Zona de disponibilidad secundaria. |
| `domain_microservices` | `map(object({ port = number, db_name = string, health_path = string }))` | `{ "ms-espacios-comunes" = { port = 8082, db_name = "espacios_db", health_path = "/api/v1/health" }, "ms-gastos-comunes" = { port = 8083, db_name = "gastos_db", health_path = "/actuator/health" }, "ms-condominios" = { port = 8084, db_name = "condominios_db", health_path = "/docs" }, "ms-usuario-cloud" = { port = 8085, db_name = "usuarios_db", health_path = "/docs" } }` | Configuración de puertos, nombres de base de datos y endpoints de health check por microservicio de dominio. |
| `frontend_admin_origin` | `string` | *(requerido)* | Origin exacto del Frontend Admin en GitHub Pages para configuración CORS. |
| `frontend_residente_origin` | `string` | *(requerido)* | Origin exacto del Frontend Residentes en GitHub Pages para configuración CORS. |
| `service_env_vars` | `map(map(string))` | `{}` | Mapa de variables de entorno adicionales por servicio. |

### Outputs Exportados (`outputs.tf`)

| Output | Tipo (inferido) | Descripción |
| --- | --- | --- |
| `api_invoke_url` | `string` (inferido) | URL base de invocación de la API Gateway HTTP v2. |
| `aws_account_id` | `string` (inferido) | ID de la cuenta AWS autenticada. |
| `ecs_cluster_name` | `string` (inferido) | Nombre del clúster ECS aprovisionado. |
| `cognito_user_pool_id` | `string` (inferido) | ID del User Pool de Cognito para residentes. |
| `cognito_app_client_id` | `string` (inferido) | ID del App Client de Cognito configurado con PKCE. |
| `cognito_hosted_ui_domain` | `string` (inferido) | Dominio FQDN de Cognito Hosted UI para redirección de autenticación. |

---

## Ejemplo de uso

### 1. Instalación de herramientas CLI en Windows (winget)

Instalar Terraform CLI y AWS CLI v2 utilizando el administrador de paquetes de Windows:

```powershell
# Instalar Terraform CLI
winget install -e --id Hashicorp.Terraform
```

```powershell
# Instalar AWS CLI v2
winget install -e --id Amazon.AWSCLI
```

Verificar la correcta instalación en una nueva terminal:

```powershell
terraform version
aws --version
```

### 2. Configurar credenciales de AWS

En AWS Academy Learner Lab, exportar las variables de sesión o configurar el archivo `~/.aws/credentials`:

```powershell
$env:AWS_ACCESS_KEY_ID="<tu-access-key-id>"
$env:AWS_SECRET_ACCESS_KEY="<tu-secret-access-key>"
$env:AWS_SESSION_TOKEN="<tu-session-token>"
$env:AWS_DEFAULT_REGION="us-east-1"
```

### 3. Preparar archivo de variables

Crear `terraform.tfvars` a partir de la plantilla:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Completar los valores obligatorios (`docker_hub_user`, `docker_hub_token`, `entra_tenant_id`, `entra_audience`, `cognito_google_client_id`, `cognito_google_client_secret`, `frontend_admin_origin`, `frontend_residente_origin`).

### 4. Inicializar y Verificación Preventiva Local Pre-push

Antes de abrir un Pull Request o enviar commits al repositorio remoto, ejecutar las validaciones con el runner nativo de Terraform:

```bash
# 1. Validar formato de archivos HCL de manera recursiva
terraform fmt -check -recursive

# 2. Inicializar configuración (sin requerir backend remoto)
terraform init -backend=false

# 3. Validar sintaxis y referencias declarativas
terraform validate
```

> **Nota de CI**: `pr-quality.yml` valida que los títulos de PR y commits respeten la sintaxis Gitmoji + Conventional Commits (`https://gitmoji.dev/`).

### 5. Planificar y aplicar

```bash
# Generar plan de ejecución
terraform plan -var-file=terraform.tfvars -out=tfplan

# Aplicar cambios aprobados
terraform apply tfplan
```

### 5.1 Estado de Terraform y primer apply en una cuenta con estado perdido

El proyecto no declara `backend`: usa el backend **local** (workspace `default`) y el estado es `terraform.tfstate`, que no se versiona. Los estados de cuentas anteriores viven en `state-backups/` y en `terraform.tfstate.backup`; ninguno es el estado activo. Antes de planificar, verificar qué estado y qué cuenta se están usando:

```bash
aws sts get-caller-identity          # cuenta y rol efectivos (credenciales temporales de Learner Lab)
terraform workspace show             # default
terraform state list | wc -l         # 0 = estado vacío: el plan propone crearlo todo
```

El `plan` no detecta recursos que existen en AWS pero no están en el estado, y esos fallan recién en el `apply`. Caso conocido: si el User Pool `convivo-residentes` ya existe en la cuenta (creado por un apply anterior), `aws_cognito_user_pool_domain.residentes` choca con el dominio `convivo-residentes-<account_id>` y el apply falla. Traer esos cuatro recursos al estado **antes** del apply (requiere aprobación explícita: modifica el estado):

```bash
POOL=$(aws cognito-idp list-user-pools --max-results 20 --query "UserPools[?Name=='convivo-residentes'].Id" --output text)
CLIENT=$(aws cognito-idp list-user-pool-clients --user-pool-id "$POOL" --query 'UserPoolClients[0].ClientId' --output text)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
terraform import -var-file=terraform.tfvars aws_cognito_user_pool.residentes "$POOL"
terraform import -var-file=terraform.tfvars aws_cognito_user_pool_client.residentes "$POOL/$CLIENT"
terraform import -var-file=terraform.tfvars aws_cognito_user_pool_domain.residentes "convivo-residentes-$ACCOUNT"
terraform import -var-file=terraform.tfvars aws_cognito_identity_provider.google "$POOL:Google"
terraform plan -var-file=terraform.tfvars   # revisar los cambios de Cognito antes del apply
```

Un `plan` de prueba con esos cuatro `import` declarados (archivo temporal, ya borrado) dio `4 to import, 159 to add, 1 to change, 0 to destroy` y ningún reemplazo. El único cambio es `aws_cognito_identity_provider.google`: Cognito completa los endpoints por defecto de Google (`provider_details`). Sin `lifecycle { ignore_changes = [generate_secret] }` en `aws_cognito_user_pool_client.residentes` (ya incluido en `cognito.tf`), ese mismo plan proponía **reemplazar el cliente**, lo que cambia su Client ID y rompe el login del frontend desplegado.

### 6. Despliegue dirigido (opcional)

Aprovisionar exclusivamente el módulo de Cognito sin levantar servicios de cómputo ECS:

```bash
terraform apply -target=aws_cognito_user_pool.residentes -var-file=terraform.tfvars
```

---

## Errores / Excepciones

- `AccessDenied` / `EntityAlreadyExists` en IAM: Las cuentas de AWS Academy Learner Lab impiden la ejecución de `iam:CreateRole` o asignación arbitraria de políticas. El módulo requiere el uso de `data.aws_iam_role.lab` referenciando el rol preexistente `LabRole`. Si la cuenta no posee `LabRole`, el plan de Terraform fallará.
- `InvalidParameterException` / `Exit Code 137` en ECS Tasks: Las tareas que ejecutan Oracle Database Free como sidecar requieren al menos 3072 MiB de memoria RAM a nivel de task definition. Cantidades menores resultan en terminación abrupta por OOM (Out Of Memory).
- `CannotPullContainerError` en `ms-usuario-cloud`: su repositorio todavía no publica la imagen en Docker Hub (falta un `docker-publish.yml` como el de `ms-condominios`). Hasta que exista `docker.io/<docker_hub_user>/ms-usuario-cloud:latest`, la task no arranca.
- Config-server y Eureka desde el BFF y los servicios Python en AWS: no se les inyectan `CONFIG_SERVER_URL` ni `EUREKA_URL`. Ambos responden por HTTPS con el keystore autofirmado compartido (y Basic Auth); los clientes Python y Node no tienen ese certificado en su almacén de confianza, y el BFF consulta Eureka por `http://`. En AWS esos servicios usan las variables de entorno de la task (`task_definitions.tf`) y el BFF llega a los microservicios por las URL del NLB; config-server y Eureka solo los consumen los servicios Spring. Resolverlo exige cambiar los clientes (confiar en la CA) o servir ambos por HTTP interno: decisión del equipo.
- `HTTP 429 Too Many Requests` al descargar imágenes Docker: Producido por superar el límite de descargas anónimas en Docker Hub. Se soluciona suministrando un `docker_hub_token` válido en `terraform.tfvars`.
- `DependencyViolation` al ejecutar `terraform destroy`: Ocurre si la VPC o subnets se destruyen mientras subsisten Elastic Network Interfaces (ENIs) asociadas a ECS Tasks o VPC Links aún no desasociadas.
- `ValidationException` en configuración CORS de API Gateway: Ocurre si los valores de `frontend_admin_origin` o `frontend_residente_origin` no corresponden a URIs absolutas válidas (ejemplo: omitir `https://`).
