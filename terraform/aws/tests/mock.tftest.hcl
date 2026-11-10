# terraform test con AWS simulado: no hace falta cuenta ni credenciales.
# Los proveedores "mock" devuelven valores inventados para lo que AWS calcularía
# (ARN, URL…); lo que comprobamos es la configuración que se le pediría a AWS.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/contador-lambda"
    }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:eu-west-1:123456789012:table/contador"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/contador"
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
      api_endpoint  = "https://abc123.execute-api.eu-west-1.amazonaws.com"
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
      output_base64sha256 = "c2ltdWxhZG8="
    }
  }
}

run "plan_dev" {
  command = plan

  variables {
    entorno             = "dev"
    memoria             = 128
    concurrencia_maxima = 2
  }

  assert {
    condition     = aws_lambda_function.contador.function_name == "contador-dev"
    error_message = "La función debería llamarse contador-dev"
  }
  assert {
    condition     = aws_lambda_function.contador.reserved_concurrent_executions == 2
    error_message = "En dev la Lambda debería tener un tope de 2 copias"
  }
  assert {
    condition     = aws_dynamodb_table.contador.billing_mode == "PAY_PER_REQUEST"
    error_message = "La tabla debería pagarse por petición"
  }
  assert {
    condition     = length(aws_apigatewayv2_route.rutas) == 4
    error_message = "Deberían publicarse 4 rutas"
  }
  assert {
    condition     = length(data.aws_iam_policy_document.permisos.statement) == 3
    error_message = "Con Bedrock, la política debería tener logs, DynamoDB y Bedrock"
  }
}

run "despliegue_prod" {
  command = apply

  variables {
    entorno        = "prod"
    memoria        = 512
    retencion_logs = 30
  }

  assert {
    condition     = startswith(output.url, "https://")
    error_message = "La URL de API Gateway debería ser https"
  }
  assert {
    condition     = aws_lambda_function.contador.environment[0].variables.MODELO_BEDROCK == "anthropic.claude-opus-5-5"
    error_message = "La Lambda debería recibir el modelo de Bedrock"
  }
  assert {
    condition     = aws_lambda_function.contador.reserved_concurrent_executions == -1
    error_message = "En prod la Lambda no debería tener tope de copias"
  }
  assert {
    condition     = aws_dynamodb_table.contador.point_in_time_recovery[0].enabled
    error_message = "En prod la tabla debería tener copias continuas (PITR)"
  }
  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 30
    error_message = "En prod los logs deberían guardarse 30 días"
  }
}

run "sin_bedrock" {
  command = plan

  variables {
    entorno        = "dev"
    modelo_bedrock = ""
  }

  assert {
    condition     = length(data.aws_iam_policy_document.permisos.statement) == 2
    error_message = "Sin Bedrock no debería haber permiso bedrock:InvokeModel"
  }
  assert {
    condition     = output.bedrock == "desactivado"
    error_message = "La salida debería indicar que Bedrock está desactivado"
  }
}

run "entorno_invalido" {
  command = plan

  variables {
    entorno = "staging"
  }

  expect_failures = [var.entorno]
}
