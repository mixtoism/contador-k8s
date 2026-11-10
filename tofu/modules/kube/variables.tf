variable "entorno" {
  description = "Nombre del entorno: dev o prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "El entorno debe ser dev o prod."
  }
}

variable "replicas" {
  description = "Número de pods de la aplicación"
  type        = number
}

variable "imagen" {
  description = "Imagen de la aplicación"
  type        = string
}

variable "version_app" {
  description = "Versión que muestra la página (cambiarla provoca un rolling update)"
  type        = string
}

variable "tipo_servicio" {
  description = "NodePort (clúster local) o LoadBalancer (nube)"
  type        = string
  default     = "NodePort"
}

variable "node_port" {
  description = "Puerto del nodo (sólo con NodePort)"
  type        = number
  default     = null
}

variable "cpu_limite" {
  description = "Límite de CPU por pod"
  type        = string
  default     = "200m"
}
