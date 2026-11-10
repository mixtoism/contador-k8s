# Un solo Terraform, tres formas de desplegar la misma app:
#
#   terraform apply -var plataforma=kube      -var entorno=dev   → k3s local
#   terraform apply -var plataforma=beanstalk -var entorno=dev   → Elastic Beanstalk + ElastiCache
#   terraform apply -var plataforma=lambda    -var entorno=dev   → Lambda + API Gateway + ElastiCache
#
# (o con un fichero: terraform apply -var-file=entornos/dev-beanstalk.tfvars)
#
# Cada plataforma es un módulo de modules/. El truco es count: un módulo con count = 0
# no crea nada, así que según var.plataforma sólo "se enciende" el que toca.

locals {
  nombre = "contador-${var.entorno}-${var.plataforma}"
  en_aws = var.plataforma != "kube"
}

# ---------------- kube ----------------

module "kube" {
  source = "./modules/kube"
  count  = var.plataforma == "kube" ? 1 : 0

  entorno     = var.entorno
  replicas    = var.replicas
  imagen      = var.imagen
  version_app = var.version_app
  node_port   = var.node_port
  cpu_limite  = var.cpu_limite
}

# ---------------- AWS ----------------

# Lo que comparten beanstalk y lambda: la red (VPC) y Redis gestionado (ElastiCache).
module "aws_base" {
  source = "./modules/aws-base"
  count  = local.en_aws ? 1 : 0

  nombre    = local.nombre
  nodos     = var.nodos_cache
  tipo_nodo = var.tipo_nodo_cache
}

locals {
  # La app se configura igual en las dos: por variables de entorno (como el Secret en kube).
  variables_app = local.en_aws ? {
    ENTORNO        = var.entorno
    APP_VERSION    = var.version_app
    REDIS_HOST     = module.aws_base[0].redis_host
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = module.aws_base[0].redis_password
    REDIS_TLS      = "1" # ElastiCache con contraseña exige TLS
  } : {}
}

module "beanstalk" {
  source = "./modules/beanstalk"
  count  = var.plataforma == "beanstalk" ? 1 : 0

  nombre         = local.nombre
  dir_app        = "${path.module}/../app"
  variables_app  = local.variables_app
  version_app    = var.version_app
  retencion_logs = var.retencion_logs

  vpc_id         = module.aws_base[0].vpc_id
  subredes       = module.aws_base[0].subredes_publicas
  sg_app         = module.aws_base[0].sg_app
  instancias_min = var.instancias_min
  instancias_max = var.instancias_max
  tipo_instancia = var.tipo_instancia
}

module "lambda" {
  source = "./modules/lambda"
  count  = var.plataforma == "lambda" ? 1 : 0

  nombre         = local.nombre
  dir_app        = "${path.module}/../app"
  variables_app  = local.variables_app
  version_app    = var.version_app
  retencion_logs = var.retencion_logs

  region              = var.region
  subredes            = module.aws_base[0].subredes_privadas
  sg_app              = module.aws_base[0].sg_app
  memoria             = var.memoria_lambda
  concurrencia_maxima = var.concurrencia_maxima
  version_adaptador   = var.version_adaptador
  limite_peticiones   = var.entorno == "prod" ? 100 : 10
}
