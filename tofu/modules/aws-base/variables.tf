variable "nombre" {
  type = string
}

variable "nodos" {
  description = "Nodos de Redis: 1 = sólo primario; 2 o más = réplicas y failover automático"
  type        = number
}

variable "tipo_nodo" {
  type = string
}
