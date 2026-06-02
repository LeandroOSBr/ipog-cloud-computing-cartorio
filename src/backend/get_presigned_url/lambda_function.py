import json
import os
import uuid
import boto3
from botocore.config import Config

# Configurando o cliente do S3 com a assinatura correta (v4)
s3_client = boto3.client(
    's3',
    region_name=os.environ.get('AWS_REGION', 'us-east-1'),
    config=Config(signature_version='s3v4')
)

BUCKET_NAME = os.environ.get('RAW_BUCKET_NAME')

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    # Tratando CORS manual (caso a integração do API Gateway precise de respostas estruturadas)
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "POST,OPTIONS"
    }
    
    if event.get('httpMethod') == 'OPTIONS' or event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {
            "statusCode": 200,
            "headers": headers,
            "body": ""
        }

    try:
        body = {}
        if event.get('body'):
            body = json.loads(event['body'])
            
        action = body.get('action', 'upload') # 'upload' ou 'download'
        file_name = body.get('file_name')
        file_type = body.get('file_type', 'application/pdf')
        bucket_type = body.get('bucket_type', 'raw') # 'raw' ou 'imutavel'
        
        if not file_name:
            return {
                "statusCode": 400,
                "headers": headers,
                "body": json.dumps({"error": "Nome do arquivo (file_name) é obrigatório."})
            }
            
        target_bucket = BUCKET_NAME if bucket_type == 'raw' else os.environ.get('IMUTAVEL_BUCKET_NAME')
        
        if action == 'upload':
            # Garante que o arquivo de upload é PDF
            if not file_name.lower().endswith('.pdf'):
                return {
                    "statusCode": 400,
                    "headers": headers,
                    "body": json.dumps({"error": "Apenas arquivos PDF são permitidos."})
                }
                
            # Gera uma chave única usando UUID + nome do arquivo para evitar colisões
            unique_id = str(uuid.uuid4())[:8]
            safe_file_name = "".join(c for c in file_name if c.isalnum() or c in '._-').rstrip()
            s3_key = f"{unique_id}_{safe_file_name}"
            
            # Gera a URL Pré-Assinada para upload via PUT
            presigned_url = s3_client.generate_presigned_url(
                'put_object',
                Params={
                    'Bucket': target_bucket,
                    'Key': s3_key,
                    'ContentType': file_type
                },
                ExpiresIn=300 # Válido por 5 minutos
            )
            
            return {
                "statusCode": 200,
                "headers": headers,
                "body": json.dumps({
                    "upload_url": presigned_url,
                    "file_key": s3_key,
                    "bucket": target_bucket
                })
            }
            
        elif action == 'download':
            # Gera a URL Pré-Assinada para download via GET
            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={
                    'Bucket': target_bucket,
                    'Key': file_name
                },
                ExpiresIn=300 # Válido por 5 minutos
            )
            
            return {
                "statusCode": 200,
                "headers": headers,
                "body": json.dumps({
                    "download_url": presigned_url
                })
            }
        else:
            return {
                "statusCode": 400,
                "headers": headers,
                "body": json.dumps({"error": "Ação inválida. Use 'upload' ou 'download'."})
            }
        
    except Exception as e:
        print(f"Erro ao gerar presigned URL: {str(e)}")
        return {
            "statusCode": 500,
            "headers": headers,
            "body": json.dumps({"error": f"Erro interno do servidor: {str(e)}"})
        }
