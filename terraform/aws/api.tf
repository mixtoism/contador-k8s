# API Gateway (HTTP API): la URL pública. Sustituye al Service NodePort.
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
  for_each  = toset(["GET /", "GET /api", "GET /stats", "GET /healthz"])
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
