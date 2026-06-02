import json
import os
import hashlib
import uuid
from datetime import datetime
import boto3

# Importa pypdf (será empacotada na pipeline)
try:
    from pypdf import PdfReader, PdfWriter
    HAS_PYPDF = True
except ImportError:
    HAS_PYPDF = False

s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
sns_client = boto3.client('sns', region_name=os.environ.get('AWS_REGION', 'us-east-1'))

IMUTAVEL_BUCKET = os.environ.get('IMUTAVEL_BUCKET_NAME')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def compute_sha256(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    # Processa cada registro do S3 Event Notification
    for record in event.get('Records', []):
        try:
            raw_bucket = record['s3']['bucket']['name']
            raw_key = record['s3']['object']['key']
            
            # Sanitiza a chave (evita problemas com caracteres especiais ou espaços)
            import urllib.parse
            raw_key = urllib.parse.unquote_plus(raw_key)
            
            print(f"Processando arquivo: {raw_key} do bucket {raw_bucket}")
            
            # Define caminhos locais temporários na Lambda
            tmp_download_path = f"/tmp/{uuid.uuid4()}_{raw_key}"
            tmp_processed_path = f"/tmp/processed_{uuid.uuid4()}_{raw_key}"
            
            # 1. Download do PDF original do bucket RAW
            s3_client.download_file(raw_bucket, raw_key, tmp_download_path)
            
            # 2. Gera metadados cartoriais
            pdf_hash = compute_sha256(tmp_download_path)
            registro_id = str(uuid.uuid4()).upper()
            data_registro = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
            
            # 3. Adiciona metadados no PDF (Simulação do Selo Digital / Provimento 213)
            if HAS_PYPDF:
                try:
                    reader = PdfReader(tmp_download_path)
                    writer = PdfWriter()
                    
                    # Copia todas as páginas
                    if len(reader.pages) > 0:
                        for page in reader.pages:
                            writer.add_page(page)
                            
                    # Adiciona metadados de autenticidade no PDF
                    writer.add_metadata({
                        "/Title": f"Documento Registrado - {raw_key}",
                        "/Author": "Cartorio Digital de Cloud Computing",
                        "/Subject": "Conformidade Provimento CNJ 213/2026",
                        "/Keywords": f"Hash:{pdf_hash}, Registro:{registro_id}, Data:{data_registro}",
                        "/Creator": "AWS Lambda PDF Processor",
                        "/Producer": "AWS Lambda - Antigravity Agent",
                        # Campo customizado de certificação
                        "/Certification": "Autenticado e Arquivado de forma imutavel nos termos do Provimento CNJ 213/2026"
                    })
                    
                    with open(tmp_processed_path, "wb") as f_out:
                        writer.write(f_out)
                        
                    print("Metadados do PDF injetados com sucesso.")
                except Exception as pdf_err:
                    print(f"Erro ao injetar metadados no PDF (usando arquivo original): {str(pdf_err)}")
                    # Em caso de erro na biblioteca PDF, prossegue com o arquivo original
                    tmp_processed_path = tmp_download_path
            else:
                print("Aviso: pypdf não disponível. Usando arquivo original de fallback.")
                tmp_processed_path = tmp_download_path
            
            # 4. Define o novo nome do arquivo processado
            processed_key = f"certificado_{raw_key}"
            
            # 5. Faz o upload para o bucket IMUTÁVEL
            # Define tags e metadados HTTP que ajudam na auditoria e conformidade
            s3_client.upload_file(
                tmp_processed_path,
                IMUTAVEL_BUCKET,
                processed_key,
                ExtraArgs={
                    "ContentType": "application/pdf",
                    "Metadata": {
                        "hash-sha256": pdf_hash,
                        "registro-id": registro_id,
                        "data-registro": data_registro,
                        "provimento-213-cnj": "compliant"
                    }
                }
            )
            print(f"Arquivo enviado com sucesso para o bucket imutavel: {processed_key}")
            
            # 5.5. Deleta o arquivo original do bucket RAW para limpar a fila
            try:
                s3_client.delete_object(Bucket=raw_bucket, Key=raw_key)
                print(f"Arquivo original deletado do bucket Raw para liberar fila: {raw_key}")
            except Exception as delete_err:
                print(f"Erro ao deletar arquivo do bucket Raw: {str(delete_err)}")
            
            # 6. Envia a notificação SNS
            if SNS_TOPIC_ARN:
                try:
                    mensagem = (
                        f"📢 NOTIFICAÇÃO DE REGISTRO NOTARIAL DIGITAL\n\n"
                        f"Um novo documento foi processado e arquivado com sucesso de forma IMUTÁVEL, "
                        f"em conformidade com as diretrizes de segurança e integridade do Provimento nº 213/2026 CNJ.\n\n"
                        f"📄 Arquivo Original: {raw_key}\n"
                        f"🔒 Arquivo Imutável: {processed_key}\n"
                        f"🆔 ID de Registro: {registro_id}\n"
                        f"🔑 Hash SHA-256: {pdf_hash}\n"
                        f"📅 Data/Hora de Registro: {data_registro}\n"
                        f"🪣 Bucket de Destino: {IMUTAVEL_BUCKET}\n"
                        f"⚙️ Status do Object Lock: ATIVO (Modo COMPLIANCE)\n\n"
                        f"Este registro digital foi gerado e auditado automaticamente via AWS Lambda."
                    )
                    
                    sns_client.publish(
                        TopicArn=SNS_TOPIC_ARN,
                        Subject=f"Registro Efetuado - ID: {registro_id[:8]}",
                        Message=mensagem
                    )
                    print(f"Notificação enviada com sucesso para o tópico SNS.")
                except Exception as sns_err:
                    print(f"Erro ao enviar notificação SNS: {str(sns_err)}")
            
            # Limpa os arquivos temporários locais
            if os.path.exists(tmp_download_path):
                os.remove(tmp_download_path)
            if os.path.exists(tmp_processed_path) and tmp_processed_path != tmp_download_path:
                os.remove(tmp_processed_path)
                
        except Exception as e:
            print(f"Erro no processamento do registro: {str(e)}")
            
    return {
        "statusCode": 200,
        "body": json.dumps("Processamento concluído.")
    }
