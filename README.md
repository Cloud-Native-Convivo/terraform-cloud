# Infraestructura en AWS con Terraform - Convivo

## Descripción
Módulo de Infraestructura como Código (IaC) en Terraform para el aprovisionamiento de la plataforma Convivo en Amazon Web Services (AWS), región `us-east-1`. Diseñado para ejecutarse sobre una cuenta de **AWS Academy Learner Lab**, utilizando el rol preexistente `LabRole`.

El despliegue provee:
- **Red:** VPC (10.0.0.0/16) con subnets pública, de microservicios y de base de datos, Internet Gateway, NAT Gateway y tablas de ruteo.
- **Seguridad perimetral:** Security Groups con ingress restringido a la subnet privada de microservicios (`10.0.2.0/24`).
- **Balanceo y Tráfico:** Network Load Balancer (NLB) interno para enrutar tráfico hacia los contenedores ECS Fargate.
- **Puerta de Enlace (API Gateway):** HTTP API v2 integrada vía VPC Link al BFF, protegida con Lambda Authorizer liviano (`jwt-basico`).
- **Cómputo (ECS Fargate):** Clúster con capacity providers (`FARGATE` y `FARGATE_SPOT`), CloudWatch Log Groups y 6 servicios contenerizados (`config-server`, `discovery-server`, `rabbitmq`, `bff`, `ms-espacios-comunes`, `ms-gastos-comunes`), estos dos últimos con base de datos Oracle Database Free 23ai como sidecar en `localhost:1521`.
- **Identidad:** Amazon Cognito User Pool (`residentes`) configurado con cliente OAuth2 y proveedor de identidad federado Google.
- **Gestión de Secretos:** AWS Secrets Manager para credenciales de Docker Hub y contraseñas generadas de Oracle PDB.

---

## Sintaxis / Interfaz

### Variables de Entrada Principales (`variables.tf`)

| Variable | Tipo | Valor por Defecto | Descripción |
|---|---|---|---|
| `aws_region` | `string` | `"us-east-1"` | Región AWS de despliegue. |
| `project` | `string` | `"convivo"` | Prefijo para nombres de recursos. |
| `docker_hub_user` | `string` | *(requerido)* | Usuario de Docker Hub donde residen las imágenes. |
| `docker_hub_token` | `string` (sensible) | *(requerido)* | Access token de Docker Hub para pull autenticado. |
| `entra_tenant_id` | `string` | *(requerido)* | Tenant ID GUID de Azure Entra ID. |
| `entra_audience` | `string` | *(requerido)* | Application Client ID del App Registration de Entra ID. |
| `cognito_google_client_id` | `string` | *(requerido)* | Client ID OAuth de Google Cloud Console. |
| `cognito_google_client_secret` | `string` (sensible) | *(requerido)* | Client Secret OAuth de Google Cloud Console. |
| `domain_microservices` | `map(object)` | `{ ms-espacios-comunes: 8082, ms-gastos-comunes: 8083 }` | Configuración de puertos y paths de health check por microservicio de dominio. |

### Outputs Exportados (`outputs.tf`)

| Output | Tipo (inferido) | Descripción |
|---|---|---|
| `api_gateway_endpoint` | `string` | URL pública base de la HTTP API Gateway. |
| `cognito_user_pool_id` | `string` | ID del User Pool de Cognito para residentes. |
| `cognito_client_id` | `string` | ID del App Client de Cognito (flujo PKCE). |
| `nlb_dns_name` | `string` | Nombre DNS privado del Network Load Balancer interno. |

---

## Ejemplo de uso

### 1. Preparar archivo de variables
Copiar la plantilla de ejemplo y completar los valores requeridos:
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Inicializar Terraform
```bash
terraform init
```

### 3. Validar sintaxis y formato
```bash
terraform fmt -check
terraform validate
```

### 4. Planificar y auditar el plan
```bash
terraform plan -var-file=terraform.tfvars -out=tfplan
```

### 5. Aplicar la infraestructura
```bash
terraform apply tfplan
```

### 6. Despliegues dirigidos (opcional)
Para aprovisionar exclusivamente el User Pool de Cognito:
```bash
terraform apply -target=aws_cognito_user_pool.residentes -var-file=terraform.tfvars
```

---

## Errores / Excepciones

- **`EntityAlreadyExists` o `AccessDenied` en IAM:** AWS Academy Learner Lab no permite ejecutar `iam:CreateRole`. El código referencia explícitamente `data.aws_iam_role.lab` (`LabRole`). Si este rol no existe en la cuenta, la inicialización del plan fallará.
- **`InvalidParameterException` en ECS Task Definitions:** Oracle Database Free requiere al menos 3072 MiB de memoria asignada a nivel de task. Valores inferiores provocan terminación inmediata del contenedor por OOM (exit code 137).
- **`HTTP 429 Too Many Requests` en Docker Hub:** Ocurre si `docker_hub_token` no es válido o está ausente, superando la cuota anónima de pulls concurrentes en Fargate.
- **`DependencyViolation` al destruir recursos:** Destruir VPC o subnets antes de que los servicios ECS o VPC Links liberen sus Network Interfaces (ENI) asociadas provocará bloqueo temporal en Terraform.
