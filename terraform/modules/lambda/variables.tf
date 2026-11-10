variable "nombre" {
  type = string
}

variable "dir_app" {
  description = "Directorio de la app (el mismo app/ que va en la imagen de Kubernetes)"
  type        = string
}

variable "variables_app" {
  description = "Variables de entorno de la app: ENTORNO, APP_VERSION, REDIS_*"
  type        = map(string)
}

variable "version_app" {
  type = string
}

variable "sg_app" {
  type = string
}

variable "retencion_logs" {
  type = number
}

variable "subredes" {
  description = "Subredes privadas: la Lambda entra en la VPC para llegar a Redis"
  type        = list(string)
}

variable "region" {
  type = string
}

variable "memoria" {
  type = number
}

variable "concurrencia_maxima" {
  type = number
}

variable "version_adaptador" {
  type = number
}

variable "limite_peticiones" {
  description = "Peticiones por segundo que deja pasar API Gateway"
  type        = number
}
