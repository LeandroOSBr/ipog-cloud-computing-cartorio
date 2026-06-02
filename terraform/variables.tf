variable "aws_region" {
  description = "Região da AWS para provisionamento dos recursos"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto para identificação e prefixo de recursos"
  type        = string
  default     = "cartorio-digital"
}

variable "notification_email" {
  description = "E-mail que receberá as notificações de conformidade do SNS"
  type        = string
  default     = "leandro.os.br@gmail.com" # Substitua no deployment
}

variable "github_repository" {
  description = "Nome do repositório GitHub para permissão do OIDC (formato: usuario/repo)"
  type        = string
  default     = "LeandroOSBr/ipog-cloud-computing-cartorio"
}
