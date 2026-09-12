# AGENTS.md — terraform (IaC Convivo)

`AGENTS.md` es un formato abierto: un Markdown en la raíz del componente que los agentes de código leen antes de actuar. Se formalizó como especificación abierta en agosto de 2025 (impulsada por OpenAI con Google, Cursor y Factory) y hoy la mantiene la Agentic AI Foundation, bajo la Linux Foundation. Lo leen de forma nativa Codex, Cursor, Copilot, Gemini CLI, Aider, Windsurf, Zed y otras herramientas.

Guía de referencia integral para agentes de código que operen en este directorio (`terraform/`). Cubre la infraestructura como código (IaC) en AWS para la plataforma **Convivo** (gestión de condominios en Chile).

**Para el agente que trabaje en esta infraestructura:**

Plantilla adaptable. Al adaptarla o extenderla, sigue estas reglas — no borres por iniciativa propia solo porque algo "no se usa todavía":

- Placeholders `[texto]`: resolver con el dato real. Si de verdad no aplica, reemplazar por una nota corta `(no aplica: <razón>)` — nunca borrar la línea sin dejar rastro de que se consideró.
- Secciones marcadas **(opcional)**: conservar íntegras salvo que no apliquen en absoluto al proyecto.
- Detalle DENTRO de una sección que sí aplica (subsecciones, tablas, reglas de seguridad, checklist OWASP/IaC, marco normativo §17): conservar íntegro por defecto. No resumir ni podar por iniciativa propia.
- Comentarios explicativos del PORQUÉ de una regla son contenido, se conservan.
- Ante la duda entre conservar o borrar: conservar, y marcar `(sin uso actual en este componente)` en vez de eliminar.
- Sin emojis en código HCL, PR, docs generadas ni output. En commits rige Gitmoji (§11.2) por convención del proyecto.
- Nada de solución genérica de tutorial. Cada recurso HCL responde a la arquitectura real de Convivo (ERS.md, mvp.md y despliegue-ecs-fargate.md) en AWS Academy Learner Lab (`us-east-1`).

## 0. Jerarquía de reglas

Cuando dos reglas de este archivo entran en conflicto, se resuelven en este orden:

1. Seguridad y corrección — nunca se sacrifican por ninguna otra regla (sin secretos expuestos, sin `0.0.0.0/0` innecesario).
2. Convenciones del proyecto fijadas en `ERS.md`, `mvp.md` y `despliegue-ecs-fargate.md`.
3. Minimalismo (sección 6, disciplina Ponytail) — se aplica solo después de satisfacer 1 y 2.

## 1. Resumen del proyecto

Infraestructura como Código (IaC) para la plataforma **Convivo** en Amazon Web Services (AWS), región `us-east-1`. Provee la red (VPC, subnets públicas/privadas, Security Groups), balanceo interno (NLB), API Gateway HTTP API con VPC Link y Lambda Authorizer liviano (`jwt-basico`), clúster ECS Fargate con 6 servicios contenerizados (BFF, Espacios Comunes con sidecar Oracle Free, Gastos Comunes con sidecar Oracle Free, Config Server, Discovery Server y RabbitMQ), Secrets Manager y User Pool en Amazon Cognito (residentes, federado con Google).

Entorno de ejecución objetivo: **AWS Academy Learner Lab** (cuenta sin permisos `iam:CreateRole`, reusando `LabRole` preexistente, y con credenciales temporales con sesión de 4 horas).

## 2. Stack técnico

- Herramienta IaC: Terraform >= 1.5.0 (usando provider AWS ~> 5.0)
- Proveedor cloud: Amazon Web Services (AWS), región `us-east-1`
- Cómputo: AWS ECS (Fargate y Fargate Spot con capacity provider strategy)
- Puerta de enlace: Amazon API Gateway HTTP API (v2) con Lambda Authorizer Python 3.13 (`jwt-basico`) y VPC Link
- Redes y Balanceo: Amazon VPC (10.0.0.0/16), Network Load Balancer (NLB) interno
- Identidad: AWS Cognito User Pool (`residentes`) + Azure Entra ID (validación JWT en BFF)
- Secretos: AWS Secrets Manager (Docker Hub credentials, contraseñas de Oracle PDB)
- Runtime auxiliar: Python 3.13 para función Lambda Authorizer

## 3. Estructura del proyecto

```text
terraform/
  providers.tf          # Configuración de Terraform y provider aws (~> 5.0)
  variables.tf          # Variables de entrada con defaults y tipado estricto
  terraform.tfvars.example # Plantilla de variables para secrets y configuración local
  network.tf            # VPC, subnets (pública, microservicios, db), IGW, route tables
  security_groups.tf    # Security groups para microservicios, db y balanceadores
  nlb.tf                # Network Load Balancer interno, target groups y listeners
  iam.tf                # Data source del LabRole de AWS Academy Learner Lab
  secrets.tf            # Secrets Manager para credenciales Docker Hub y Oracle
  cognito.tf            # User Pool residentes, clientes y proveedor federado Google
  ecs_cluster.tf        # Cluster ECS convivo-cluster y CloudWatch Log Groups
  task_definitions.tf   # Task definitions Fargate (bff, microservicios con Oracle sidecar, etc.)
  ecs_services.tf       # ECS Services (desired_count = 1, capacity providers Fargate/Spot)
  api_gateway.tf        # HTTP API Gateway, VPC Link, stage, Lambda Authorizer y rutas
  outputs.tf            # Outputs exportados (API Gateway endpoint, Cognito IDs, NLB DNS)
  lambda/jwt-basico/    # Código fuente de Lambda Authorizer (index.py)
```

## 4. Comandos

```bash
# Inicializar providers y backend local
terraform init

# Validar sintaxis y coherencia HCL
terraform validate

# Formatear archivos HCL según convención estándar
terraform fmt -check

# Planificar cambios (requiere terraform.tfvars completado)
terraform plan -var-file=terraform.tfvars

# Aplicar infraestructura (requiere confirmación explícita — ver §12)
terraform apply -var-file=terraform.tfvars

# Aplicar solo un componente específico (ej. Cognito)
terraform apply -target=aws_cognito_user_pool.residentes -var-file=terraform.tfvars

# Destruir infraestructura (¡NUNCA sin confirmación humana explícita!)
terraform destroy -var-file=terraform.tfvars
```

## 5. Estilo de código

- **Un archivo por recurso lógico:** Mantener la separación de componentes (`network.tf`, `ecs_services.tf`, `api_gateway.tf`, etc.) sin consolidar en archivos monolíticos.
- **Naming conventions:** `snake_case` para recursos, variables y locals; prefijo `${var.project}-` para recursos en AWS.
- **Etiquetado:** Todo recurso etiquetable debe incluir tags `Project = var.project` y `ManagedBy = "Terraform"`.
- **Variables explícitas:** Cada variable en `variables.tf` debe contar con `type` y `description`. Las variables con información confidencial (`docker_hub_token`, `cognito_google_client_secret`) deben declarar `sensitive = true`.

## 6. Disciplina anti-sobreingeniería (Ponytail)

Escalera de decisión antes de agregar infraestructura nueva:
1. ¿Es estrictamente necesario para el MVP/Rúbrica? (YAGNI). Si no se evaluará, no aprovisionar.
2. ¿Un recurso nativo simple de AWS lo cubre? Úsalo (ej. HTTP API sobre REST API, SQLite/Oracle sidecar sobre RDS Aurora costosa).
3. ¿Se puede parametrizar con `for_each` sobre un map existente? Hazlo en vez de duplicar bloques resource idénticos.
4. Solo entonces: escribe el mínimo HCL funcional y seguro.

## 7. Pruebas y Validación

- **Validación estática:** `terraform fmt -check` y `terraform validate` deben pasar en verde sin errores ni advertencias.
- **Inspección de plan:** Todo cambio requiere `terraform plan` previo para auditar qué recursos se crean, modifican o destruyen (evitar reemplazos destructivos no deseados en ECS Services por `capacity_provider_strategy`).
- **Verificación de Health Checks:** Las task definitions declaran comandos de health check HTTP (`curl -f`) o diagnostics (`rabbitmq-diagnostics`, `healthcheck.sh` de Oracle) que determinan el estado `HEALTHY` antes de recibir tráfico del NLB o permitir que inicie el contenedor dependiente (`dependsOn`).

## 8. Métricas de claridad

| Métrica | Umbral | Cómo medir |
| --- | --- | --- |
| Longitud de bloque resource | <= 60 líneas | revisión manual / modularización |
| Complejidad de expresiones | <= 2 niveles de ternarios en HCL | revisión manual |
| Hardcoding de IDs o IPs | 0 (usar referencias cruzadas de recursos o variables) | `terraform validate` |

## 9. Procedimientos QA

Checklist obligatorio antes de `terraform apply`:
- `terraform validate` limpio.
- `terraform.tfvars` real **NUNCA** se commitea a Git (verificado en `.gitignore`).
- No exponer puertos de base de datos (`1521`) ni administración interna hacia internet (`0.0.0.0/0`).
- Revisar que `LabRole` esté vigente en la sesión actual de AWS Learner Lab.

| Severidad | Acción | Equivalente CVSS v4.0 |
| --- | --- | --- |
| Crítico | Bloquea el apply (secretos en HCL, puertos de BD abiertos a 0.0.0.0/0) | Critical 9.0–10.0 |
| Mayor | Corregir antes de mergear (recurso sin tags requeridos, variables sin descripción) | Medium 4.0–6.9 |
| Menor | Issue de seguimiento (optimización de locals, formateo HCL) | Low 0.1–3.9 |

## 10. Seguridad

- **A01 Control de acceso:** Toda ruta de API Gateway redirige al BFF a través de VPC Link y está protegida por el Lambda Authorizer `jwt-basico`. El BFF valida claims de Entra ID o Cognito.
- **A02 Configuración segura:** Security groups estrictos. Los microservicios solo aceptan tráfico del NLB y de la subnet privada de microservicios.
- **A03 Cadena de suministro:** Version pin de providers (`hashicorp/aws` ~> 5.0) en `.terraform.lock.hcl`. Imágenes de Docker Hub autenticadas con secret token.
- **A04 Fallos criptográficos:** Secretos gestionados en AWS Secrets Manager y referenciados en ECS mediante `valueFrom` (secret injection en container runtime).
- **Learner Lab Constraints:** Reuso estricto de `data.aws_iam_role.lab.arn` (`LabRole`). No intentar crear roles IAM (`iam:CreateRole`) ni políticas administradas.

## 11. Commits y PR

Conventional Commits v1.0.0 con Gitmoji (§11.2).

Formato: `:emoji: <tipo>(<alcance>): <sujeto>`
Ejemplos:
- `:wrench: chore(terraform): ajusta timeout de health check en task definition bff`
- `:sparkles: feat(network): agrega subnet privada para base de datos`
- `:lock: fix(security): restringe ingress en security group de microservicios`

**Regla de no-firma:** Nunca agregar trailers de autoría de agente/IA (`Co-Authored-By: Claude`, etc.) en commits o descripciones de PR.

## 12. Límites del agente

**Siempre (sin pedir permiso):**
- Modificar archivos `.tf`, documentación y scripts auxiliares locales.
- Ejecutar `terraform init`, `terraform validate`, `terraform fmt` y `terraform plan`.

**Preguntar primero / Aprobación explícita obligatoria:**
- **`terraform apply`**: Requiere revisión del plan y aprobación explícita del usuario.
- **`terraform destroy`**: Terminantemente prohibido sin solicitud expresa.
- Modificar `terraform.tfvars` o manipular credenciales AWS reales.

## 13. Despliegue y Operación en AWS

Para desplegar la infraestructura:
```bash
cd terraform
terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Para actualizar los contenedores en ECS sin destruir la infraestructura, usar el script raíz:
```powershell
.\deploy-ecs.ps1 -All
```

## 14. Relación en el Workspace

`terraform/` es el componente de infraestructura del monorepo Convivo. Se vincula contractualmente con:
- `Frontend-CloudNative/`: Consume el endpoint exportado de API Gateway (`api_endpoint`) y User Pool Cognito (`cognito_user_pool_id`, `cognito_app_client_id`).
- `panel-administracion-web/`: Consume el endpoint de API Gateway autenticado mediante Microsoft Entra ID.
- `Microservicios/` (`bff`, `ms-espacios-comunes`, `ms-gastos-comunes`, etc.): Empaquetados en Docker Hub y orquestados en ECS Fargate según los puertos definidos en `variables.tf`.

## 15. Enforcement

El formateo y validación deben comprobarse localmente antes de commitear cambios:
```bash
terraform fmt -check
terraform validate
```

## 16. Mantenimiento

Revisión ante cambios en la topología de red, adición de nuevos microservicios o término del semestre de AWS Academy. Al migrar a cuenta AWS propia fuera de Learner Lab, reemplazar `LabRole` por roles de ejecución acotados en `iam.tf`.

## 17. Normativa y cumplimiento

- **ISO/IEC 25010**: Fiabilidad (reintentos de tareas en ECS, capacidad Fargate Spot, health checks), Seguridad (CORS, Secrets Manager, Lambda Authorizer) y Mantenibilidad (HCL modular y tipado).
- **ISO/IEC 27001**: Confidencialidad de secretos en AWS Secrets Manager, integridad de redes VPC privadas, disponibilidad de servicios mediante ECS restart policies.
