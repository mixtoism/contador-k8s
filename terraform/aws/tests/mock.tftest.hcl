# terraform test con AWS simulado: no hace falta cuenta ni credenciales.
# Los proveedores "mock" devuelven valores inventados para lo que AWS calcularía
# (IDs, ARN, endpoints…); lo que comprobamos es la configuración que se le pediría a AWS.
# Hay un run por entorno, con las mismas variables que su .tfvars.

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

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_md5          = "0123456789abcdef0123456789abcdef"
      output_base64sha256 = "c2ltdWxhZG8="
    }
  }
}

run "dev_lambda" {
  command = plan

  variables {
    entorno             = "dev"
    plataforma          = "lambda"
    nodos_cache         = 1
    memoria_lambda      = 128
    concurrencia_maxima = 2
  }

  assert {
    condition     = length(aws_lambda_function.contador) == 1 && length(aws_elastic_beanstalk_environment.this) == 0
    error_message = "Un entorno lambda debería tener la función y nada de Beanstalk"
  }
  assert {
    condition     = aws_lambda_function.contador[0].function_name == "contador-dev-lambda"
    error_message = "La función debería llamarse contador-dev-lambda"
  }
  assert {
    condition     = aws_lambda_function.contador[0].handler == "run.sh" && aws_lambda_function.contador[0].environment[0].variables.AWS_LAMBDA_EXEC_WRAPPER == "/opt/bootstrap"
    error_message = "La Lambda debería arrancar server.js a través del Lambda Web Adapter"
  }
  assert {
    condition     = aws_lambda_function.contador[0].filename == data.archive_file.app.output_path
    error_message = "La Lambda debería desplegar el zip de app/"
  }
  assert {
    condition     = aws_lambda_function.contador[0].reserved_concurrent_executions == 2
    error_message = "En dev la Lambda debería tener un tope de 2 copias"
  }
  assert {
    condition     = length(aws_apigatewayv2_route.rutas) == 5
    error_message = "Deberían publicarse 5 rutas"
  }
  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 1 && !aws_elasticache_replication_group.this.automatic_failover_enabled
    error_message = "En dev Redis debería ser un único nodo sin failover"
  }
  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled && aws_lambda_function.contador[0].environment[0].variables.REDIS_TLS == "1"
    error_message = "Redis debería exigir TLS (va con contraseña) y la app usarlo"
  }
}

run "dev_beanstalk" {
  command = plan

  variables {
    entorno        = "dev"
    plataforma     = "beanstalk"
    instancias_min = 1
    instancias_max = 2
    nodos_cache    = 1
  }

  assert {
    condition     = length(aws_elastic_beanstalk_environment.this) == 1 && length(aws_lambda_function.contador) == 0 && length(aws_apigatewayv2_route.rutas) == 0
    error_message = "Un entorno beanstalk debería tener Beanstalk y nada de Lambda"
  }
  assert {
    condition     = aws_s3_object.app[0].source == data.archive_file.app.output_path
    error_message = "Beanstalk debería desplegar el zip de app/"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : "${s.name}=${s.value}"], "MinSize=1")
    error_message = "En dev Beanstalk debería tener mínimo 1 instancia"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : "${s.name}=${s.value}"], "HealthCheckPath=/readyz")
    error_message = "El health check del balanceador debería ser /readyz, como la readinessProbe"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : "${s.name}=${s.value}"], "DeploymentPolicy=Rolling")
    error_message = "Beanstalk debería desplegar por lotes (Rolling)"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : "${s.name}=${s.value}"], "REDIS_TLS=1")
    error_message = "La app en Beanstalk debería conectarse a Redis por TLS"
  }
}

run "prod_beanstalk" {
  command = apply

  variables {
    entorno         = "prod"
    plataforma      = "beanstalk"
    instancias_min  = 2
    instancias_max  = 4
    tipo_instancia  = "t4g.small"
    nodos_cache     = 2
    tipo_nodo_cache = "cache.t4g.small"
    retencion_logs  = 30
  }

  assert {
    condition     = output.url == "http://contador.eu-west-1.elasticbeanstalk.com"
    error_message = "La URL debería salir del CNAME del entorno de Beanstalk"
  }
  assert {
    condition     = aws_elastic_beanstalk_environment.this[0].solution_stack_name == "64bit Amazon Linux 2023 v6.6.0 running Node.js 22"
    error_message = "Beanstalk debería usar la plataforma Node.js 22"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : "${s.name}=${s.value}"], "MaxSize=4")
    error_message = "En prod Beanstalk debería poder escalar hasta 4 instancias"
  }
  assert {
    condition     = contains([for s in aws_elastic_beanstalk_environment.this[0].setting : s.value if s.name == "REDIS_HOST"], aws_elasticache_replication_group.this.primary_endpoint_address)
    error_message = "Beanstalk debería apuntar al endpoint primario de ElastiCache"
  }
  assert {
    condition     = aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "En prod Redis debería tener réplica y failover automático"
  }
  assert {
    condition     = tolist(aws_security_group.redis.ingress)[0].security_groups == toset([aws_security_group.beanstalk[0].id])
    error_message = "Redis sólo debería aceptar conexiones de las instancias de Beanstalk"
  }
  assert {
    condition     = length(aws_subnet.publica) == 2 && aws_subnet.publica[0].availability_zone != aws_subnet.publica[1].availability_zone
    error_message = "Debería haber dos subredes públicas en zonas distintas"
  }
}

run "prod_lambda" {
  command = apply

  variables {
    entorno         = "prod"
    plataforma      = "lambda"
    nodos_cache     = 2
    tipo_nodo_cache = "cache.t4g.small"
    memoria_lambda  = 512
    retencion_logs  = 30
  }

  assert {
    condition     = startswith(output.url, "https://")
    error_message = "La URL de API Gateway debería ser https"
  }
  assert {
    condition     = length(aws_lambda_function.contador[0].vpc_config[0].subnet_ids) == 2
    error_message = "La Lambda debería estar en las dos subredes privadas para llegar a Redis"
  }
  assert {
    condition     = aws_lambda_function.contador[0].environment[0].variables.REDIS_HOST == "master.contador.abc123.euw1.cache.amazonaws.com"
    error_message = "La Lambda debería apuntar al endpoint primario de ElastiCache"
  }
  assert {
    condition     = aws_lambda_function.contador[0].reserved_concurrent_executions == -1
    error_message = "En prod la Lambda no debería tener tope de copias"
  }
  assert {
    condition     = length(aws_elastic_beanstalk_environment.this) == 0 && length(aws_s3_bucket.versiones) == 0
    error_message = "Al pasar a lambda no debería quedar nada de Beanstalk"
  }
}

run "entorno_invalido" {
  command = plan

  variables {
    entorno    = "staging"
    plataforma = "lambda"
  }

  expect_failures = [var.entorno]
}

run "plataforma_invalida" {
  command = plan

  variables {
    entorno    = "dev"
    plataforma = "ecs"
  }

  expect_failures = [var.plataforma]
}

run "escalado_imposible" {
  command = plan

  variables {
    entorno        = "dev"
    plataforma     = "beanstalk"
    instancias_min = 3
    instancias_max = 2
  }

  expect_failures = [var.instancias_max]
}
