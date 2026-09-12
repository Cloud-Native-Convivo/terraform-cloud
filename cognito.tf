# AWS Cognito: identidad exclusiva de RESIDENTE (mvp.md §1.2/§4.6). Azure Entra ID sigue
# siendo el único issuer para ADMIN — no se mezclan roles en este User Pool, por eso el rol
# se infiere del issuer del JWT (Cognito = RESIDENTE, Entra ID = ADMIN) sin necesitar grupo
# ni atributo custom de rol acá.
#
# Unidad/torre/piso viven como atributos custom del propio usuario (mvp.md TD-13: sin
# microservicio ni BD de perfil) — torre/piso opcionales (Ley 21.442, condominios Tipo B
# sin torre/piso), la obligatoriedad de "unidad" se valida en el formulario, no en el schema.

resource "aws_cognito_user_pool" "residentes" {
  name = "${var.project}-residentes"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  schema {
    name                = "unidad"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 50
    }
  }

  schema {
    name                = "torre"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 50
    }
  }

  schema {
    name                = "piso"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 10
    }
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  tags = { Name = "${var.project}-residentes-user-pool" }
}

resource "aws_cognito_user_pool_domain" "residentes" {
  domain       = "${var.project}-residentes-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.residentes.id
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.residentes.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.cognito_google_client_id
    client_secret    = var.cognito_google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    username       = "sub"
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    given_name     = "given_name"
    family_name    = "family_name"
    picture        = "picture"
    locale         = "locale"
  }
}

resource "aws_cognito_user_pool_client" "residentes" {
  name         = "${var.project}-residentes-client"
  user_pool_id = aws_cognito_user_pool.residentes.id

  generate_secret = false # SPA pública (GitHub Pages) — Authorization Code + PKCE, sin client secret

  supported_identity_providers = ["COGNITO", aws_cognito_identity_provider.google.provider_name]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  # localhost incluido para poder probar el flujo en dev sin depender del deploy a GitHub Pages.
  callback_urls = ["${var.frontend_residente_origin}/auth/callback", "http://localhost:5173/auth/callback"]
  logout_urls   = [var.frontend_residente_origin, "http://localhost:5173"]

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}
