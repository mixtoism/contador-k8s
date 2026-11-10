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

variable "vpc_id" {
  type = string
}

variable "subredes" {
  description = "Subredes públicas para las instancias y el balanceador"
  type        = list(string)
}

variable "instancias_min" {
  type = number
}

variable "instancias_max" {
  type = number
}

variable "tipo_instancia" {
  type = string
}
