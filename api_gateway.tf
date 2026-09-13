# API Gateway HTTP API con Lambda Authorizer liviano unico (mvp.md v2.2+, RF-T.3/RF-T.4,
# TD-17 cerrado). Reemplaza el diseno viejo (dos JWT Authorizers nativos por issuer + rutas
# compartidas sin ningun authorizer) que vivia antes en este archivo: un unico authorizer
# REQUEST (`jwt-basico`, sin JWKS) valida estructura/expiracion en TODAS las rutas por igual,
# y el bff resuelve identidad completa (firma contra JWKS de Entra ID o Cognito segun `iss`),
# rol y ownership antes de reenviar como reverse proxy a ms-espacios-comunes/ms-gastos-comunes
# (RF-T.7). Ya no hay ruta que llegue directo a un microservicio de dominio via VPC Link.

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.project}-vpc-link"
  security_group_ids = [aws_security_group.microservices.id]
  subnet_ids         = [aws_subnet.microservices.id]
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 50
  }
  # ponytail: límites de ejemplo para MVP de 2 personas. Subir si el curso simula carga real (RNF01: 100 usuarios concurrentes).
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/apigateway/${var.project}"
  retention_in_days = 30
}

# --- Lambda Authorizer liviano (jwt-basico) ---------------------------------------------

data "archive_file" "jwt_basico" {
  type        = "zip"
  source_file = "${path.module}/lambda/jwt-basico/index.py"
  output_path = "${path.module}/lambda/jwt-basico.zip"
}

resource "aws_lambda_function" "jwt_basico" {
  function_name    = "${var.project}-jwt-basico"
  role             = data.aws_iam_role.lab.arn # LabRole: sin iam:CreateRole en Learner Lab (mvp.md §4.12)
  runtime          = "python3.13"
  handler          = "index.handler"
  filename         = data.archive_file.jwt_basico.output_path
  source_code_hash = data.archive_file.jwt_basico.output_base64sha256
  timeout          = 5
  memory_size      = 128
}

resource "aws_lambda_permission" "apigw_invoke_jwt_basico" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jwt_basico.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_apigatewayv2_authorizer" "jwt_basico" {
  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.jwt_basico.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "jwt-basico"
}
# No valida firma/issuer/audience/rol (RF-T.3) — esa resolucion completa vive en el bff
# (RF-T.4), a diferencia del Lambda Authorizer "OR de issuers" descartado antes (mvp.md §5).

# --- Rutas: todas via bff (reverse proxy), mismo authorizer para todas ---------------------

resource "aws_apigatewayv2_integration" "bff" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
  integration_uri    = aws_lb_listener.bff.arn
}

# Ruta proxy comodín para toda la API privada hacia el BFF.
# Permite todas las operaciones CRUD (GET, POST, PUT, PATCH, DELETE) protegidas por JWT.
resource "aws_apigatewayv2_route" "bff_proxy" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /api/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.bff.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt_basico.id
}

# Endpoints públicos sin autenticación:
# 1. Healthcheck (monitoreo externo de API Gateway -> BFF)
# 2. Catálogo público de espacios comunes (Home de productos/espacios accesible sin login)
resource "aws_apigatewayv2_route" "public" {
  for_each = toset([
    "GET /health",
    "GET /api/health",
    "GET /api/v1/espacios-comunes",
    "GET /api/v1/espacios-comunes/espacios",
  ])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.bff.id}"
  authorization_type = "NONE"
}
