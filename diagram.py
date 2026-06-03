# ==============================================================================
# Diagram as Code - Cartório Digital AWS
# Requisitos: 
#   1. pip install diagrams
#   2. Graphviz instalado e no PATH (https://graphviz.org/download/)
# ==============================================================================

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.storage import S3
from diagrams.aws.network import CloudFront, APIGateway
from diagrams.aws.compute import Lambda
from diagrams.aws.security import Cognito, WAF
from diagrams.aws.integration import SNS
from diagrams.onprem.client import User

graph_attr = {
    "fontsize": "16",
    "bgcolor": "transparent"
}

with Diagram(
    name="Digital Notary - Serverless Compliance Architecture",
    show=False,
    direction="LR",
    filename="notary_architecture",
    outformat="png",
    graph_attr=graph_attr
):
    user = User("Usuário (Navegador)")
    
    # 1. Borda e CDN
    with Cluster("Borda & Proteção"):
        waf = WAF("AWS WAF (Global)")
        cf_front = CloudFront("CloudFront Frontend")
        cf_api = CloudFront("CloudFront API Link")
        
        # Associação lógica de proteção
        waf - cf_front
        waf - cf_api

    # 2. Hospedagem Estática
    with Cluster("Interface Gráfica"):
        s3_front = S3("S3 Frontend (Privado)")
        cf_front >> s3_front

    # 3. Autenticação e MFA
    with Cluster("Identidade & Acesso"):
        cognito = Cognito("Cognito User Pool (JWT & MFA)")

    # 4. APIs e Lambdas
    with Cluster("API & Backend"):
        api_gw = APIGateway("API Gateway (HTTP)")
        lambda_presigned = Lambda("get_presigned_url")
        lambda_list = Lambda("list_files")
        
        api_gw >> lambda_presigned
        api_gw >> lambda_list

    # 5. Processamento e Logs Imutáveis
    with Cluster("Processamento & Armazenamento"):
        s3_raw = S3("S3 Raw (Uploads)")
        lambda_process = Lambda("process_pdf (Stamp)")
        s3_imutavel = S3("S3 Imutável (Object Lock)")
        sns = SNS("SNS (Notificações)")
        
        s3_raw >> lambda_process
        lambda_process >> s3_imutavel
        lambda_process >> sns

    # Conexões de fluxo de dados
    user >> Edge(label="1. Autentica & MFA") >> cognito
    user >> Edge(label="2. Acessa Painel") >> cf_front
    
    # Chamadas protegidas por Token JWT
    user >> Edge(label="3. Requisições API (JWT)") >> cf_api >> api_gw
    
    # Upload direto via Pre-signed URL
    lambda_presigned >> Edge(label="Gera URL de Upload") >> s3_raw
    user >> Edge(label="4. PUT (PDF)") >> s3_raw
