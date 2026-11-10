variable "kubeconfig" {
  description = "Ruta al kubeconfig del clúster"
  type        = string
  default     = "../kubeconfig"
}

variable "kube_context" {
  description = "Contexto del kubeconfig (null = el actual)"
  type        = string
  default     = null
}

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
  default     = 1
}

variable "imagen" {
  description = "Imagen de la aplicación"
  type        = string
  default     = "localhost/contador:v1"
}

variable "version_app" {
  description = "Versión que muestra la página (cambiarla provoca un rolling update)"
  type        = string
  default     = "v1"
}

variable "node_port" {
  description = "Puerto del nodo por el que se expone la aplicación"
  type        = number
}

variable "cpu_limite" {
  description = "Límite de CPU por pod"
  type        = string
  default     = "200m"
}
