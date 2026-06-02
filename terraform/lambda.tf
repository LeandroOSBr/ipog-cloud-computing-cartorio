# ==============================================================================
# 1. Empacotamento do Código das Lambdas (Zip)
# ==============================================================================
data "archive_file" "get_presigned_url_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/backend/get_presigned_url"
  output_path = "${path.module}/files/get_presigned_url.zip"
}

data "archive_file" "list_files_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/backend/list_files"
  output_path = "${path.module}/files/list_files.zip"
}

data "archive_file" "process_pdf_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/backend/process_pdf"
  output_path = "${path.module}/files/process_pdf.zip"
}

# ==============================================================================
# 2. Recursos de Função Lambda
# ==============================================================================

# Lambda: Get Pre-signed URL (Geração de URL de upload e download)
resource "aws_lambda_function" "get_presigned_url" {
  filename         = data.archive_file.get_presigned_url_zip.output_path
  function_name    = "${var.project_name}-get-presigned-url"
  role             = aws_iam_role.lambda_api_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  source_code_hash = data.archive_file.get_presigned_url_zip.output_base64sha256

  environment {
    variables = {
      RAW_BUCKET_NAME      = aws_s3_bucket.raw.id
      IMUTAVEL_BUCKET_NAME = aws_s3_bucket.imultavel.id
    }
  }
}

# Lambda: List Files (Listagem de arquivos e consulta do Object Lock)
resource "aws_lambda_function" "list_files" {
  filename         = data.archive_file.list_files_zip.output_path
  function_name    = "${var.project_name}-list-files"
  role             = aws_iam_role.lambda_api_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  source_code_hash = data.archive_file.list_files_zip.output_base64sha256

  environment {
    variables = {
      RAW_BUCKET_NAME      = aws_s3_bucket.raw.id
      IMUTAVEL_BUCKET_NAME = aws_s3_bucket.imultavel.id
    }
  }
}

# Lambda: Process PDF (Acessa o PDF, adiciona metadados, grava no imutável e dispara SNS)
resource "aws_lambda_function" "process_pdf" {
  filename         = data.archive_file.process_pdf_zip.output_path
  function_name    = "${var.project_name}-process-pdf"
  role             = aws_iam_role.lambda_processor_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 60
  memory_size      = 256 # Um pouco mais de memória para processamento de PDF
  source_code_hash = data.archive_file.process_pdf_zip.output_base64sha256

  environment {
    variables = {
      IMUTAVEL_BUCKET_NAME = aws_s3_bucket.imultavel.id
      SNS_TOPIC_ARN        = aws_sns_topic.notificacoes_cartorio.arn
    }
  }
}

# ==============================================================================
# 3. Log Groups no CloudWatch (Boas Práticas de Observabilidade)
# ==============================================================================
resource "aws_cloudwatch_log_group" "log_presigned" {
  name              = "/aws/lambda/${aws_lambda_function.get_presigned_url.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "log_list" {
  name              = "/aws/lambda/${aws_lambda_function.list_files.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "log_process" {
  name              = "/aws/lambda/${aws_lambda_function.process_pdf.function_name}"
  retention_in_days = 7
}

# ==============================================================================
# 4. Gatilhos de Integração (S3 Event Notification -> Lambda Process)
# ==============================================================================

# Dá permissão para o Bucket S3 Raw invocar a função Lambda de processamento
resource "aws_lambda_permission" "allow_s3_invoke_processor" {
  statement_id  = "AllowS3ToInvokeProcessPDF"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_pdf.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

# Configura o gatilho de novo objeto criado no S3 (.pdf)
resource "aws_s3_bucket_notification" "raw_s3_notification" {
  bucket = aws_s3_bucket.raw.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_pdf.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_processor]
}
