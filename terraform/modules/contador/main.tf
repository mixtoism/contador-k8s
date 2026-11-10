locals {
  ns = "contador-${var.entorno}"
  etiquetas = {
    "app.kubernetes.io/part-of"    = "contador"
    "app.kubernetes.io/managed-by" = "terraform"
    entorno                        = var.entorno
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = local.ns
    labels = local.etiquetas
  }
}

# ---------- Redis ----------

resource "random_password" "redis" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  data = {
    password = random_password.redis.result
  }
}

resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = merge(local.etiquetas, { app = "redis" })
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "redis" }
    }

    template {
      metadata {
        labels = merge(local.etiquetas, { app = "redis" })
      }
      spec {
        container {
          name  = "redis"
          image = "docker.io/library/redis:7-alpine"
          args  = ["--requirepass", "$(REDIS_PASSWORD)"]

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis.metadata[0].name
                key  = "password"
              }
            }
          }

          port {
            container_port = 6379
          }

          readiness_probe {
            tcp_socket {
              port = 6379
            }
            period_seconds = 5
          }

          resources {
            requests = { cpu = "50m", memory = "32Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    selector = { app = "redis" }
    port {
      port = 6379
    }
  }
}

# ---------- Aplicación ----------

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "contador"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = merge(local.etiquetas, { app = "contador" })
  }

  # Espera a que los pods estén listos antes de dar el apply por bueno.
  wait_for_rollout = true

  timeouts {
    create = "4m"
    update = "4m"
  }

  spec {
    replicas = var.replicas
    selector {
      match_labels = { app = "contador" }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 0
        max_surge       = 1
      }
    }

    template {
      metadata {
        labels = merge(local.etiquetas, { app = "contador" })
      }
      spec {
        termination_grace_period_seconds = 10

        container {
          name              = "contador"
          image             = var.imagen
          image_pull_policy = "IfNotPresent"

          env {
            name  = "ENTORNO"
            value = var.entorno
          }
          env {
            name  = "APP_VERSION"
            value = var.version_app
          }
          env {
            name  = "REDIS_HOST"
            value = kubernetes_service_v1.redis.metadata[0].name
          }
          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis.metadata[0].name
                key  = "password"
              }
            }
          }

          port {
            container_port = 8080
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            period_seconds = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8080
            }
            period_seconds = 3
          }

          resources {
            requests = { cpu = "50m", memory = "32Mi" }
            limits   = { cpu = var.cpu_limite, memory = "128Mi" }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.redis]
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = "contador"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    type     = var.tipo_servicio
    selector = { app = "contador" }
    port {
      port        = 80
      target_port = 8080
      node_port   = var.tipo_servicio == "NodePort" ? var.node_port : null
    }
  }
}
