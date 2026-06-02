import json
import os
import boto3
from datetime import datetime

s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

RAW_BUCKET = os.environ.get('RAW_BUCKET_NAME')
IMUTAVEL_BUCKET = os.environ.get('IMUTAVEL_BUCKET_NAME')

def serialize_datetime(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError("Type not serializable")

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "GET,OPTIONS"
    }
    
    if event.get('httpMethod') == 'OPTIONS' or event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {
            "statusCode": 200,
            "headers": headers,
            "body": ""
        }

    try:
        raw_files = []
        imultavel_files = []
        
        # 1. Listar arquivos do bucket RAW
        try:
            raw_response = s3_client.list_objects_v2(Bucket=RAW_BUCKET)
            if 'Contents' in raw_response:
                for obj in raw_response['Contents']:
                    raw_files.append({
                        "key": obj['Key'],
                        "size": obj['Size'],
                        "last_modified": obj['LastModified'].isoformat(),
                        "status": "Aguardando Processamento"
                    })
        except Exception as e:
            print(f"Erro ao listar bucket RAW: {str(e)}")
            
        # 2. Listar arquivos do bucket IMUTÁVEL e obter retenção de cada um
        try:
            imultavel_response = s3_client.list_objects_v2(Bucket=IMUTAVEL_BUCKET)
            if 'Contents' in imultavel_response:
                for obj in imultavel_response['Contents']:
                    file_info = {
                        "key": obj['Key'],
                        "size": obj['Size'],
                        "last_modified": obj['LastModified'].isoformat(),
                        "status": "Arquivado e Imutável",
                        "object_lock": {
                            "active": False,
                            "mode": None,
                            "retain_until": None
                        }
                    }
                    
                    # Tenta buscar informações de retenção do Object Lock
                    try:
                        retention = s3_client.get_object_retention(
                            Bucket=IMUTAVEL_BUCKET,
                            Key=obj['Key']
                        )
                        ret_config = retention.get('Retention', {})
                        file_info['object_lock'] = {
                            "active": True,
                            "mode": ret_config.get('Mode'),
                            "retain_until": ret_config.get('RetainUntilDate').isoformat()
                        }
                    except Exception as s3_err:
                        # Se não encontrar ou não tiver permissão de ler retenção ainda
                        print(f"Não foi possível obter a retenção de {obj['Key']}: {str(s3_err)}")
                        
                    imultavel_files.append(file_info)
        except Exception as e:
            print(f"Erro ao listar bucket IMUTÁVEL: {str(e)}")
            
        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({
                "raw_files": raw_files,
                "imultavel_files": imultavel_files
            })
        }
        
    except Exception as e:
        print(f"Erro geral ao listar arquivos: {str(e)}")
        return {
            "statusCode": 500,
            "headers": headers,
            "body": json.dumps({"error": f"Erro interno do servidor: {str(e)}"})
        }
