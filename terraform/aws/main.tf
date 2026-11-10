locals {
  nombre = "contador-${var.entorno}"
}

# Un único paquete con app/: el mismo server.js que va en la imagen de Kubernetes.
# Beanstalk lo arranca con "npm start" (package.json) y Lambda con run.sh.
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../../app"
  output_path = "${path.module}/.build/app.zip"
  excludes    = ["Dockerfile"]
}
