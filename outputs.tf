output "api_invoke_url" {
  description = "URL base de la API — el frontend (GitHub Pages) debe apuntar acá."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.residentes.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.residentes.id
}

output "cognito_hosted_ui_domain" {
  description = "Dominio del Hosted UI de Cognito — el frontend residente redirige acá para login/signup con Google."
  value       = "${aws_cognito_user_pool_domain.residentes.domain}.auth.${var.aws_region}.amazoncognito.com"
}
