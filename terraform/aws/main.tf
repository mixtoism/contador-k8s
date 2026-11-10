# Cada entorno (workspace) es una combinación de entorno y plataforma:
#   dev-lambda, prod-lambda, dev-beanstalk, prod-beanstalk  (ver los .tfvars)
# Todos tienen su red y su ElastiCache; los recursos de Beanstalk sólo se crean si
# plataforma = "beanstalk" y los de Lambda si plataforma = "lambda" (count = 0 o 1).
locals {
  nombre       = "contador-${var.entorno}-${var.plataforma}"
  es_beanstalk = var.plataforma == "beanstalk"
  es_lambda    = var.plataforma == "lambda"
}

# El paquete de app/: el mismo server.js que va en la imagen de Kubernetes.
# Beanstalk lo arranca con "npm start" (package.json) y Lambda con run.sh.
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../../app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["Dockerfile"]
}
