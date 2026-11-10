# Lambda: el mismo server.js, sin tocar una línea. La capa Lambda Web Adapter
# (de AWS, https://github.com/awslabs/aws-lambda-web-adapter) arranca run.sh, espera a
# que el servidor responda en :8080 y convierte cada evento de API Gateway en una
# petición HTTP normal. Cada copia caliente de la función es un "pod" con su color.

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.nombre}"
  retention_in_days = var.retencion_logs
}

data "aws_iam_policy_document" "asumir_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.nombre}-lambda"
  assume_role_policy = data.aws_iam_policy_document.asumir_lambda.json
}

# Logs + crear interfaces de red en la VPC (para llegar a ElastiCache).
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "contador" {
  function_name    = local.nombre
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "run.sh"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  memory_size      = var.memoria_lambda
  timeout          = 15
  layers           = ["arn:aws:lambda:${var.region}:753240598075:layer:LambdaAdapterLayerArm64:${var.version_adaptador}"]

  reserved_concurrent_executions = var.concurrencia_maxima == null ? -1 : var.concurrencia_maxima

  vpc_config {
    subnet_ids         = aws_subnet.privada[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(local.entorno_app, {
      AWS_LAMBDA_EXEC_WRAPPER      = "/opt/bootstrap" # entra el adaptador
      PORT                         = "8080"
      AWS_LWA_READINESS_CHECK_PATH = "/healthz"
    })
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy_attachment.lambda]
}

# ---------- API Gateway (HTTP API): la URL pública de la Lambda ----------

resource "aws_apigatewayv2_api" "this" {
  name          = local.nombre
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contador.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "rutas" {
  for_each  = toset(["GET /", "GET /api", "GET /stats", "GET /healthz", "GET /readyz"])
  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "defecto" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.entorno == "prod" ? 100 : 10
    throttling_burst_limit = var.entorno == "prod" ? 200 : 20
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contador.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
