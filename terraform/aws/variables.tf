variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "zonas" {
  description = "Zonas de disponibilidad (EKS exige al menos dos)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "entorno" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "El entorno debe ser dev o prod."
  }
}

variable "replicas" {
  type    = number
  default = 1
}

variable "nodos" {
  description = "Número de nodos EC2 del clúster"
  type        = number
  default     = 2
}

variable "tipo_instancia" {
  type    = string
  default = "t3.small"
}

variable "version_app" {
  type    = string
  default = "v1"
}
