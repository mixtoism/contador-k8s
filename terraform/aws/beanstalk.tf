# Elastic Beanstalk, el PaaS de AWS: le damos el zip y él pone las instancias EC2,
# el balanceador (ALB), el autoescalado, los health checks y los despliegues por lotes.
# Sólo en los entornos *-beanstalk: todo lleva count = 1 ahí y 0 en los demás.

data "aws_elastic_beanstalk_solution_stack" "node" {
  count       = local.es_beanstalk ? 1 : 0
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 (.*) running Node.js 22$"
}

# ---------- El paquete de la aplicación, en S3 ----------

resource "aws_s3_bucket" "versiones" {
  count         = local.es_beanstalk ? 1 : 0
  bucket_prefix = "${local.nombre}-versiones-"
  force_destroy = true
}

resource "aws_s3_object" "app" {
  count  = local.es_beanstalk ? 1 : 0
  bucket = aws_s3_bucket.versiones[0].id
  key    = "contador-${var.version_app}-${data.archive_file.app.output_md5}.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5
}

resource "aws_elastic_beanstalk_application" "this" {
  count       = local.es_beanstalk ? 1 : 0
  name        = local.nombre
  description = "Contador de visitas (${var.entorno})"
}

resource "aws_elastic_beanstalk_application_version" "app" {
  count       = local.es_beanstalk ? 1 : 0
  name        = "${var.version_app}-${substr(data.archive_file.app.output_md5, 0, 8)}"
  application = aws_elastic_beanstalk_application.this[0].name
  bucket      = aws_s3_bucket.versiones[0].id
  key         = aws_s3_object.app[0].key
}

# ---------- Permisos ----------

data "aws_iam_policy_document" "asumir_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "asumir_beanstalk" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["elasticbeanstalk.amazonaws.com"]
    }
  }
}

# Lo que pueden hacer las instancias (subir logs, métricas…).
resource "aws_iam_role" "instancias" {
  count              = local.es_beanstalk ? 1 : 0
  name               = "${local.nombre}-ec2"
  assume_role_policy = data.aws_iam_policy_document.asumir_ec2.json
}

resource "aws_iam_role_policy_attachment" "instancias" {
  count      = local.es_beanstalk ? 1 : 0
  role       = aws_iam_role.instancias[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "instancias" {
  count = local.es_beanstalk ? 1 : 0
  name  = "${local.nombre}-ec2"
  role  = aws_iam_role.instancias[0].name
}

# Lo que puede hacer Beanstalk en nuestro nombre (salud, actualizaciones gestionadas).
resource "aws_iam_role" "servicio" {
  count              = local.es_beanstalk ? 1 : 0
  name               = "${local.nombre}-servicio"
  assume_role_policy = data.aws_iam_policy_document.asumir_beanstalk.json
}

resource "aws_iam_role_policy_attachment" "servicio" {
  for_each = local.es_beanstalk ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth",
    "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy",
  ]) : toset([])
  role       = aws_iam_role.servicio[0].name
  policy_arn = each.value
}

# ---------- El entorno ----------

locals {
  ajustes_beanstalk = local.es_beanstalk ? concat(
    [
      # Red
      { ns = "aws:ec2:vpc", nombre = "VPCId", valor = aws_vpc.this.id },
      { ns = "aws:ec2:vpc", nombre = "Subnets", valor = join(",", aws_subnet.publica[*].id) },
      { ns = "aws:ec2:vpc", nombre = "ELBSubnets", valor = join(",", aws_subnet.publica[*].id) },
      { ns = "aws:ec2:vpc", nombre = "AssociatePublicIpAddress", valor = "true" },
      # Instancias y réplicas
      { ns = "aws:ec2:instances", nombre = "InstanceTypes", valor = var.tipo_instancia },
      { ns = "aws:autoscaling:launchconfiguration", nombre = "IamInstanceProfile", valor = aws_iam_instance_profile.instancias[0].name },
      { ns = "aws:autoscaling:launchconfiguration", nombre = "SecurityGroups", valor = aws_security_group.beanstalk[0].id },
      { ns = "aws:autoscaling:asg", nombre = "MinSize", valor = tostring(var.instancias_min) },
      { ns = "aws:autoscaling:asg", nombre = "MaxSize", valor = tostring(var.instancias_max) },
      # Balanceador y health check (la readinessProbe de Kubernetes)
      { ns = "aws:elasticbeanstalk:environment", nombre = "EnvironmentType", valor = "LoadBalanced" },
      { ns = "aws:elasticbeanstalk:environment", nombre = "LoadBalancerType", valor = "application" },
      { ns = "aws:elasticbeanstalk:environment", nombre = "ServiceRole", valor = aws_iam_role.servicio[0].arn },
      { ns = "aws:elasticbeanstalk:environment:process:default", nombre = "HealthCheckPath", valor = "/readyz" },
      { ns = "aws:elasticbeanstalk:healthreporting:system", nombre = "SystemType", valor = "enhanced" },
      # Despliegue por lotes de una instancia: el RollingUpdate de Kubernetes
      { ns = "aws:elasticbeanstalk:command", nombre = "DeploymentPolicy", valor = "Rolling" },
      { ns = "aws:elasticbeanstalk:command", nombre = "BatchSizeType", valor = "Fixed" },
      { ns = "aws:elasticbeanstalk:command", nombre = "BatchSize", valor = "1" },
      # Logs a CloudWatch
      { ns = "aws:elasticbeanstalk:cloudwatch:logs", nombre = "StreamLogs", valor = "true" },
      { ns = "aws:elasticbeanstalk:cloudwatch:logs", nombre = "RetentionInDays", valor = tostring(var.retencion_logs) },
    ],
    # Variables de entorno de la app
    [for k, v in local.entorno_app : { ns = "aws:elasticbeanstalk:application:environment", nombre = k, valor = v }],
  ) : []
}

resource "aws_elastic_beanstalk_environment" "this" {
  count               = local.es_beanstalk ? 1 : 0
  name                = local.nombre
  application         = aws_elastic_beanstalk_application.this[0].name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.node[0].name
  version_label       = aws_elastic_beanstalk_application_version.app[0].name
  tier                = "WebServer"

  dynamic "setting" {
    for_each = local.ajustes_beanstalk
    content {
      namespace = setting.value.ns
      name      = setting.value.nombre
      value     = setting.value.valor
    }
  }

  depends_on = [aws_iam_role_policy_attachment.instancias, aws_iam_role_policy_attachment.servicio]
}
