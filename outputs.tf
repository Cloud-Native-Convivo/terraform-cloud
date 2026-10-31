output "api_invoke_url" {
  description = "URL base de la API — el frontend (GitHub Pages) debe apuntar acá."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "aws_account_id" {
  description = "ID de la cuenta AWS (Learner Lab) donde se desplegó la infraestructura."
  value       = data.aws_caller_identity.current.account_id
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS de Convivo."
  value       = aws_ecs_cluster.main.name
}

output "rabbitmq_ui_url" {
  description = "Consola web de RabbitMQ (HTTP). Usuario: rabbitmq_ui_user; password en Secrets Manager convivo/rabbitmq/observador."
  value       = "http://${aws_lb.rabbitmq_ui.dns_name}"
}

output "rabbitmq_ui_user" {
  description = "Usuario de solo monitoreo para la consola web de RabbitMQ."
  value       = local.rabbitmq_observador_user
}

output "cognito_user_pool_id" {
  description = "ID del User Pool de residentes."
  value       = aws_cognito_user_pool.residentes.id
}

output "cognito_app_client_id" {
  description = "Client ID público del frontend residente (VITE_COGNITO_CLIENT_ID)."
  value       = aws_cognito_user_pool_client.residentes.id
}

output "cognito_hosted_ui_domain" {
  description = "Dominio del Hosted UI de Cognito — el frontend residente redirige acá para login/signup con Google."
  value       = "${aws_cognito_user_pool_domain.residentes.domain}.auth.${var.aws_region}.amazoncognito.com"
}
