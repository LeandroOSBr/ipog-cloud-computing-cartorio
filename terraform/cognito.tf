# ==============================================================================
# Amazon Cognito - Gerenciamento de Usuários e Autenticação
# ==============================================================================

resource "aws_cognito_user_pool" "pool" {
  name = "${var.project_name}-user-pool"

  # Permite usar o e-mail diretamente como username
  username_attributes = ["email"]

  # Configuração da política de senhas fortes
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # Configuração de MFA opcional (TOTP - Authenticator App)
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  # Confirmação de e-mail por código numérico
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_message        = "Seu código de verificação para o Cartório Digital é {####}."
    email_subject        = "Código de Verificação - Cartório Digital"
  }

  # E-mail é verificado automaticamente após confirmação do código
  auto_verified_attributes = ["email"]

  # Schema básico de atributos de usuário
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      min_length = 7
      max_length = 256
    }
  }
}

# Client do Cognito para integração do Frontend Javascript
resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.project_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  # Não gera secret (obrigatório para aplicações client-side JS)
  generate_secret = false

  # Fluxos de autenticação permitidos
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
}
