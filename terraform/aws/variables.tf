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

variable "plataforma" {
  description = "Dónde corre la app: beanstalk (PaaS) o lambda (serverless)"
  type        = string

  validation {
    condition     = contains(["beanstalk", "lambda"], var.plataforma)
    error_message = "La plataforma debe ser beanstalk o lambda."
  }
}

variable "version_app" {
  type    = string
  default = "v1"
}

# ---------- Elastic Beanstalk ----------

variable "instancias_min" {
  description = "Mínimo de instancias EC2 de Beanstalk (el equivalente a las réplicas)"
  type        = number
  default     = 1
}

variable "instancias_max" {
  description = "Máximo de instancias EC2: Beanstalk escala entre el mínimo y este valor"
  type        = number
  default     = 2

  validation {
    condition     = var.instancias_max >= var.instancias_min
    error_message = "instancias_max no puede ser menor que instancias_min."
  }
}

variable "tipo_instancia" {
  type    = string
  default = "t4g.micro"
}

# ---------- ElastiCache ----------

variable "nodos_cache" {
  description = "Nodos de Redis: 1 = sólo primario; 2 o más = réplicas y failover automático"
  type        = number
  default     = 1

  validation {
    condition     = var.nodos_cache >= 1 && var.nodos_cache <= 6
    error_message = "Entre 1 y 6 nodos."
  }
}

variable "tipo_nodo_cache" {
  type    = string
  default = "cache.t4g.micro"
}

# ---------- Lambda ----------

variable "memoria_lambda" {
  description = "MB de memoria de la Lambda (la CPU escala con ella)"
  type        = number
  default     = 256
}

variable "concurrencia_maxima" {
  description = "Tope de copias simultáneas de la Lambda; null = sin tope"
  type        = number
  default     = null
}

variable "version_adaptador" {
  description = "Versión de la capa Lambda Web Adapter (awslabs/aws-lambda-web-adapter)"
  type        = number
  default     = 25
}

variable "retencion_logs" {
  description = "Días que CloudWatch guarda los logs (Beanstalk y Lambda)"
  type        = number
  default     = 7
}
