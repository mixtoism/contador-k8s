locals {
  nombre     = "contador-${var.entorno}"
  con_ia     = var.modelo_bedrock != ""
  dir_lambda = "${path.module}/../../lambda"
}

# El código (con node_modules: make lambda) se empaqueta en un zip.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = local.dir_lambda
  output_path = "${path.module}/.build/lambda.zip"
  excludes    = ["logica.test.js", "package-lock.json"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.nombre}"
  retention_in_days = var.retencion_logs
}

# ---------- Permisos: qué puede tocar la Lambda ----------

data "aws_iam_policy_document" "asumir" {
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
  assume_role_policy = data.aws_iam_policy_document.asumir.json
}

data "aws_iam_policy_document" "permisos" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "Contador"
    actions   = ["dynamodb:UpdateItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.contador.arn]
  }

  dynamic "statement" {
    for_each = local.con_ia ? [1] : []
    content {
      sid     = "Bedrock"
      actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      # El modelo puede servirse desde otra región (perfiles de inferencia): por eso "*".
      resources = [
        "arn:aws:bedrock:*::foundation-model/${var.modelo_bedrock}",
        "arn:aws:bedrock:*:*:inference-profile/*${var.modelo_bedrock}*",
      ]
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "contador"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.permisos.json
}

# ---------- La función ----------

resource "aws_lambda_function" "contador" {
  function_name    = local.nombre
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = var.memoria
  timeout          = 15
  architectures    = ["arm64"]

  reserved_concurrent_executions = var.concurrencia_maxima == null ? -1 : var.concurrencia_maxima

  environment {
    variables = {
      TABLA          = aws_dynamodb_table.contador.name
      ENTORNO        = var.entorno
      APP_VERSION    = var.version_app
      MODELO_BEDROCK = var.modelo_bedrock
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}
