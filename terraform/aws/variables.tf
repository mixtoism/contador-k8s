variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "entorno" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "El entorno debe ser dev o prod."
  }
}

variable "version_app" {
  type    = string
  default = "v1"
}

variable "memoria" {
  description = "MB de memoria de la Lambda (la CPU escala con ella)"
  type        = number
  default     = 256
}

variable "concurrencia_maxima" {
  description = "Tope de copias simultáneas de la Lambda (el equivalente a las réplicas); null = sin tope"
  type        = number
  default     = null
}

variable "modelo_bedrock" {
  description = "Modelo de Claude en Bedrock para la frase de cada visita; \"\" = sin Bedrock"
  type        = string
  default     = "anthropic.claude-opus-5-5"
}

variable "retencion_logs" {
  description = "Días que CloudWatch guarda los logs"
  type        = number
  default     = 7
}
