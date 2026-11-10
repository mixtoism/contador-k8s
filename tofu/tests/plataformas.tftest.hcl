# tofu test con todo simulado: ni clúster ni cuenta de AWS.
# Los proveedores "mock" devuelven valores inventados para lo que calcularía la nube
# (IDs, ARN, endpoints…); lo que comprobamos es la configuración que se le pediría.
#
# Dos tipos de run:
#   - raíz: se elige la plataforma y se comprueba que sólo se "enciende" su módulo
#   - módulo: se prueba un módulo suelto (module { source = ... }) con más detalle

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
    }
  }
  mock_data "aws_elastic_beanstalk_solution_stack" {
    defaults = {
      name = "64bit Amazon Linux 2023 v6.6.0 running Node.js 22"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/contador"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/contador"
    }
  }
  mock_resource "aws_elasticache_replication_group" {
    defaults = {
      primary_endpoint_address = "master.contador.abc123.euw1.cache.amazonaws.com"
    }
  }
  mock_resource "aws_elastic_beanstalk_environment" {
    defaults = {
      cname = "contador.eu-west-1.elasticbeanstalk.com"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:eu-west-1:123456789012:function:contador"
      invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:contador/invocations"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:abc123"
    }
  }
  mock_resource "aws_apigatewayv2_stage" {
    defaults = {
      invoke_url = "https://abc123.execute-api.eu-west-1.amazonaws.com/"
    }
  }
}

mock_provider "kubernetes" {}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_md5          = "0123456789abcdef0123456789abcdef"
      output_base64sha256 = "c2ltdWxhZG8="
    }
  }
}

# ======================= Raíz: elegir plataforma =======================

run "elegir_kube" {
  command = apply

  variables {
    plataforma = "kube"
    entorno    = "dev"
  }

  assert {
    condition     = length(module.kube) == 1 && length(module.aws_base) == 0 && length(module.beanstalk) == 0 && length(module.lambda) == 0
    error_message = "Con plataforma = kube sólo debería existir el módulo kube"
  }
  assert {
    condition     = output.url == "http://localhost:8080" && output.namespace == "contador-dev"
    error_message = "kube debería publicarse en localhost:8080, namespace contador-dev"
  }
  assert {
    condition     = output.redis == null
    error_message = "En kube no hay ElastiCache"
  }
}

run "elegir_beanstalk" {
  command = apply

  variables {
    plataforma     = "beanstalk"
    entorno        = "prod"
    instancias_min = 2
    instancias_max = 4
    nodos_cache    = 2
  }

  assert {
    condition     = length(module.kube) == 0 && length(module.aws_base) == 1 && length(module.beanstalk) == 1 && length(module.lambda) == 0
    error_message = "Con plataforma = beanstalk deberían existir aws_base y beanstalk"
  }
  assert {
    condition     = output.url == "http://contador.eu-west-1.elasticbeanstalk.com"
    error_message = "La URL debería salir del CNAME del entorno de Beanstalk"
  }
  assert {
    condition     = output.redis == "master.contador.abc123.euw1.cache.amazonaws.com:6379"
    error_message = "Debería mostrarse el endpoint de ElastiCache"
  }
}

run "elegir_lambda" {
  command = apply

  variables {
    plataforma = "lambda"
    entorno    = "dev"
  }

  assert {
    condition     = length(module.kube) == 0 && length(module.aws_base) == 1 && length(module.beanstalk) == 0 && length(module.lambda) == 1
    error_message = "Con plataforma = lambda deberían existir aws_base y lambda"
  }
  assert {
    condition     = output.url == "https://abc123.execute-api.eu-west-1.amazonaws.com/"
    error_message = "La URL debería ser la de API Gateway"
  }
}

run "plataforma_invalida" {
  command = plan

  variables {
    plataforma = "ecs"
    entorno    = "dev"
  }

  expect_failures = [var.plataforma]
}

run "entorno_invalido" {
  command = plan

  variables {
    plataforma = "lambda"
    entorno    = "staging"
  }

  expect_failures = [var.entorno]
}

run "escalado_imposible" {
  command = plan

  variables {
    plataforma     = "beanstalk"
    entorno        = "dev"
    instancias_min = 3
    instancias_max = 2
  }

  expect_failures = [var.instancias_max]
}

# ======================= Módulos sueltos =======================

run "kube_prod" {
  command = plan

  module {
    source = "./modules/kube"
  }

  variables {
    entorno     = "prod"
    replicas    = 3
    imagen      = "localhost/contador:v2"
    version_app = "v2"
    node_port   = 30081
  }

  assert {
    condition     = kubernetes_deployment_v1.app.spec[0].replicas == "3"
    error_message = "En prod debería haber 3 réplicas"
  }
  assert {
    condition     = kubernetes_service_v1.app.spec[0].port[0].node_port == 30081
    error_message = "El Service debería usar el NodePort pedido"
  }
}

run "red_y_redis_dev" {
  command = plan

  module {
    source = "./modules/aws-base"
  }

  variables {
    nombre    = "contador-dev-lambda"
    nodos     = 1
    tipo_nodo = "cache.t4g.micro"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 1 && !aws_elasticache_replication_group.this.automatic_failover_enabled
    error_message = "Con un nodo Redis no debería tener failover"
  }
  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled
    error_message = "Redis debería exigir TLS (va con contraseña)"
  }
}

run "red_y_redis_prod" {
  command = apply

  module {
    source = "./modules/aws-base"
  }

  variables {
    nombre    = "contador-prod-beanstalk"
    nodos     = 2
    tipo_nodo = "cache.t4g.small"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "Con dos nodos Redis debería tener réplica y failover automático"
  }
  assert {
    condition     = tolist(aws_security_group.redis.ingress)[0].security_groups == toset([aws_security_group.app.id])
    error_message = "Redis sólo debería aceptar conexiones de la app"
  }
  assert {
    condition     = length(aws_subnet.publica) == 2 && aws_subnet.publica[0].availability_zone != aws_subnet.publica[1].availability_zone
    error_message = "Debería haber dos subredes públicas en zonas distintas"
  }
}

run "beanstalk" {
  command = plan

  module {
    source = "./modules/beanstalk"
  }

  variables {
    nombre         = "contador-dev-beanstalk"
    dir_app        = "../app"
    variables_app  = { REDIS_HOST = "redis.ejemplo", REDIS_TLS = "1" }
    version_app    = "v1"
    retencion_logs = 7
    vpc_id         = "vpc-1"
    subredes       = ["subnet-a", "subnet-b"]
    sg_app         = "sg-app"
    instancias_min = 1
    instancias_max = 2
    tipo_instancia = "t4g.micro"
  }

  assert {
    condition     = aws_s3_object.app.source == data.archive_file.app.output_path
    error_message = "Beanstalk debería desplegar el zip de app/"
  }
  assert {
    condition = alltrue([for a in ["MinSize=1", "MaxSize=2", "HealthCheckPath=/readyz", "DeploymentPolicy=Rolling", "REDIS_TLS=1", "Subnets=subnet-a,subnet-b"] :
    contains([for s in aws_elastic_beanstalk_environment.this.setting : "${s.name}=${s.value}"], a)])
    error_message = "Faltan ajustes: réplicas, health check /readyz, Rolling, variables de la app o red"
  }
}

run "lambda" {
  command = plan

  module {
    source = "./modules/lambda"
  }

  variables {
    nombre              = "contador-dev-lambda"
    dir_app             = "../app"
    variables_app       = { REDIS_HOST = "redis.ejemplo", REDIS_TLS = "1" }
    version_app         = "v1"
    retencion_logs      = 7
    region              = "eu-west-1"
    subredes            = ["subnet-a", "subnet-b"]
    sg_app              = "sg-app"
    memoria             = 128
    concurrencia_maxima = 2
    version_adaptador   = 25
    limite_peticiones   = 10
  }

  assert {
    condition     = aws_lambda_function.contador.handler == "run.sh" && aws_lambda_function.contador.environment[0].variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/bootstrap"
    error_message = "La Lambda debería arrancar server.js a través del Lambda Web Adapter"
  }
  assert {
    condition     = aws_lambda_function.contador.environment[0].variables.REDIS_HOST == "redis.ejemplo"
    error_message = "La Lambda debería recibir las variables de la app"
  }
  assert {
    condition     = aws_lambda_function.contador.reserved_concurrent_executions == 2
    error_message = "La Lambda debería tener un tope de 2 copias"
  }
  assert {
    condition     = length(aws_apigatewayv2_route.rutas) == 5
    error_message = "Deberían publicarse 5 rutas"
  }
}
