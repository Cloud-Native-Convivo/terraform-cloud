variable "aws_region" {
  description = "Región AWS. ERS.md/despliegue-ecs-fargate.md usan us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres de recursos."
  type        = string
  default     = "convivo"
}

variable "docker_hub_user" {
  description = "Usuario de Docker Hub donde viven las imágenes convivo-*. Las imágenes aún no existen — el ECS service quedará en PENDING hasta que el pipeline las publique."
  type        = string
}

variable "docker_hub_token" {
  description = "Access token de Docker Hub del docker_hub_user, para autenticar pulls de imágenes públicas (rabbitmq, gvenzl/oracle-free) y evitar el rate limit anónimo."
  type        = string
  sensitive   = true
}

variable "entra_tenant_id" {
  description = "Tenant ID de Azure Entra ID (GUID). Usado para construir el issuer OIDC del JWT Authorizer nativo de API Gateway."
  type        = string
}

variable "entra_audience" {
  description = "Client ID (Application ID) del App Registration de Entra ID que representa esta API — audience que valida el JWT Authorizer de administradores."
  type        = string
}

variable "cognito_google_client_id" {
  description = "OAuth Client ID de la app de Google Cloud, usado como Identity Provider federado en el User Pool de Cognito (residentes)."
  type        = string
}

variable "cognito_google_client_secret" {
  description = "OAuth Client Secret de la app de Google Cloud, usado como Identity Provider federado en el User Pool de Cognito (residentes)."
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "microservices_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "db_subnet_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "availability_zone_a" {
  type    = string
  default = "us-east-1a"
}

variable "availability_zone_b" {
  type    = string
  default = "us-east-1b"
}

# ponytail: single-AZ para subnet de microservicios (igual que despliegue-ecs-fargate.md) — sin HA de cómputo entre AZs.
# Subir a multi-AZ (2da subnet privada + ECS service desplegado en ambas) si el curso pide alta disponibilidad real.

# mvp.md v2.0: ms-residentes eliminado (perfil vive en atributos de Cognito/Entra ID, TD-13/TD-14).
# ms-espacios-comunes y ms-gastos-comunes son los dos microservicios de dominio de esta edición,
# cada uno con su propia instancia RDS (database-per-service real, RF-2/RF-3).
variable "domain_microservices" {
  description = "Microservicios de dominio activos en esta edición: puerto, nombre de BD y path del health check."
  type = map(object({
    port        = number
    db_name     = string
    health_path = string
  }))
  # health_path por servicio: no hay convención común. FastAPI monta su router
  # con prefix /api/v1 y Spring Boot expone Actuator en /actuator/health —
  # asumir "/health" para ambos da 404 y deja el task en loop de reinicio.
  default = {
    "ms-espacios-comunes" = {
      port        = 8082
      db_name     = "espacios_db"
      health_path = "/api/v1/health"
    }
    "ms-gastos-comunes" = {
      port        = 8083
      db_name     = "gastos_db"
      health_path = "/actuator/health"
    }
  }
}

variable "frontend_admin_origin" {
  description = "Origin exacto del Frontend Admin Privado en GitHub Pages, para CORS del API Gateway."
  type        = string
}

variable "frontend_residente_origin" {
  description = "Origin exacto del Frontend Usuario Público en GitHub Pages, para CORS del API Gateway."
  type        = string
}

variable "service_env_vars" {
  description = "Variables de entorno adicionales por servicio (no secretas). TD-18: lenguaje por microservicio aún no decidido — dejar vacío hasta confirmar Java/Spring o Python/FastAPI; SPRING_* o equivalente se agrega cuando se decida."
  type        = map(map(string))
  default     = {}
}
