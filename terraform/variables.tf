# ================== Lo que se elige siempre ==================

variable "plataforma" {
  description = "Dónde se despliega: kube (k3s local), beanstalk (PaaS de AWS) o lambda (serverless)"
  type        = string

  validation {
    condition     = contains(["kube", "beanstalk", "lambda"], var.plataforma)
    error_message = "La plataforma debe ser kube, beanstalk o lambda."
  }
}

variable "entorno" {
  description = "dev o prod: cambia el tamaño, no la arquitectura"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "El entorno debe ser dev o prod."
  }
}

variable "version_app" {
  description = "Versión que muestra la página (cambiarla provoca un despliegue gradual)"
  type        = string
  default     = "v1"
}

# ================== kube ==================

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

variable "node_port" {
  description = "Puerto del nodo por el que se expone la aplicación"
  type        = number
  default     = 30080
}

variable "cpu_limite" {
  description = "Límite de CPU por pod"
  type        = string
  default     = "200m"
}

# ================== AWS (beanstalk y lambda) ==================

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "nodos_cache" {
  description = "Nodos de ElastiCache: 1 = sólo primario; 2 o más = réplicas y failover automático"
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

variable "retencion_logs" {
  description = "Días que CloudWatch guarda los logs"
  type        = number
  default     = 7
}

# ---------- beanstalk ----------

variable "instancias_min" {
  description = "Mínimo de instancias EC2 (el equivalente a las réplicas)"
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

# ---------- lambda ----------

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
