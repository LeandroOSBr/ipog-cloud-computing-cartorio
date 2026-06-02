# Cartório Digital - Demonstração de Cloud Computing & Compliance AWS

Esta é uma aplicação serverless de demonstração projetada para simular o registro, processamento e arquivamento de documentos cartoriais digitais em conformidade com as diretrizes de segurança, proteção contra ransomware e integridade cibernética do **Provimento nº 213 de 20 de Fevereiro de 2026 da Corregedoria Nacional de Justiça (CNJ)**.

A aplicação utiliza uma arquitetura baseada em microsserviços serverless na AWS, provisionada via **Terraform** através de uma esteira CI/CD automatizada no **GitHub Actions** utilizando conexões seguras **OIDC (OpenID Connect)**.

---

## 🏗️ Arquitetura do Sistema

A infraestrutura é 100% serverless, escalando a zero e minimizando custos:

```
                      +-----------------------------+
                      |      Navegador Web          |
                      |   (Hospedado no S3 Web)     |
                      +--------------+--------------+
                                     |
             1. POST /presigned-url  |  2. PUT (Upload PDF Direto)
             +-----------------------+----------------------+
             |                                              |
             v                                              v
  +----------+----------+                        +----------+----------+
  |  Amazon API Gateway |                        |    S3 Bucket Raw    |
  +----------+----------+                        |  (Fila de Entrada)  |
             |                                   +----------+----------+
             | Proxy HTTP                                   |
             v                                              | 3. Novo PDF Criado
  +----------+----------+                                   | (S3 Event Trigger)
  |   Lambda Backend    |                                   v
  | - GetPresignedUrl   |                        +----------+----------+
  | - ListFiles         |                        |   Lambda Processor  |
  +---------------------+                        | (Python + pypdf)    |
                                                 +----------+----------+
                                                            |
                                      4. Injeta Metadados   | 5. Salva Documento
                                         & Assina PDF       |    Certificado
                                                            v
                                                 +----------+----------+
                                                 | S3 Bucket Imutável  |
                                                 |  (S3 Object Lock    |
                                                 |   Modo Compliance)  |
                                                 +----------+----------+
                                                            |
                                                            | 6. Alerta de Auditoria
                                                            v
                                                 +----------+----------+
                                                 |  Amazon SNS Topic   |
                                                 |  (Alerta por E-mail)|
                                                 +---------------------+
```

### Principais Tecnologias e Serviços

*   **Frontend**: Single Page Application construída com HTML5, CSS3 (design escuro premium com glassmorphism) e Javascript Vanilla, hospedada em um bucket **S3** e distribuída globalmente pelo **Amazon CloudFront** com acesso protegido por **OAC (Origin Access Control)**.
*   **API Backend**: **Amazon API Gateway** (HTTP API) integrada com **AWS Lambda** rodando Python 3.9 para gerar credenciais seguras de upload/download e listar os arquivos.
*   **Controle de Acesso & MFA (Amazon Cognito)**: Controle estrito de acesso via **Cognito User Pools**. Exige e-mail verificado e suporta **MFA via Software Token (TOTP - Google Authenticator/Authy)**. As rotas do API Gateway são protegidas por um **Autorizador JWT**.
*   **Proteção de Borda (AWS WAF)**: Firewall de Aplicação Web integrado ao CloudFront que mitiga ataques comuns de OWASP Top 10 (SQL injection, XSS, etc.) em toda a aplicação.
*   **S3 Object Lock (WORM - Write Once Read Many)**: Utilizado no bucket `s3_cartorio_imultavel` sob o modo de retenção **COMPLIANCE**. Impede fisicamente a exclusão ou modificação de documentos por qualquer agente (inclusive o usuário root) durante o período configurado (1 dia nesta demonstração), atendendo às exigências do Provimento 213/2026.
*   **Processamento e Notificação**: Lambda de processamento que lê o PDF carregado, extrai informações, insere assinaturas digitais e carimbos de auditoria nos metadados internos do PDF utilizando a biblioteca `pypdf`, grava no bucket imutável e notifica o usuário via **Amazon SNS (Simple Notification Service)** por e-mail.
*   **IaC (Infraestrutura como Código)**: Toda a infraestrutura AWS é provisionada utilizando **Terraform**.

---

## ⚙️ Configuração Inicial: AWS OIDC com GitHub Actions

Para que a pipeline do GitHub Actions possa provisionar a infraestrutura e fazer o deploy do código sem expor chaves fixas de acesso da AWS, utilizaremos o protocolo **OpenID Connect (OIDC)**. Siga o passo a passo abaixo no console da AWS:

### Passo 1: Criar o Identity Provider (Provedor de Identidade)
1. Acesse o console do **IAM** na AWS.
2. No menu esquerdo, clique em **Identity providers** (Provedores de identidade) e depois em **Add provider** (Adicionar provedor).
3. Selecione a opção **OpenID Connect**.
4. Insira as seguintes informações:
    *   **Provider URL**: `https://token.actions.githubusercontent.com` (Clique em *Get thumbprint* após digitar).
    *   **Audience**: `sts.amazonaws.com`
5. Clique em **Add provider**.

### Passo 2: Criar a Role IAM de Deploy do GitHub Actions
1. No menu do **IAM**, vá em **Roles** e clique em **Create role** (Criar role).
2. Escolha **Web identity** como tipo de entidade confiável.
3. Preencha os campos com base no provedor OIDC criado:
    *   **Identity provider**: `token.actions.githubusercontent.com`
    *   **Audience**: `sts.amazonaws.com`
4. Na tela de permissões, associe as permissões de implantação. Para fins desta demonstração/trabalho, associe a política **AdministratorAccess** (ou crie uma restrita aos serviços S3, Lambda, API Gateway, SNS, IAM, CloudWatch).
5. Nomeie a role como: `cartorio-digital-github-actions-deploy-role` (Ou nome de sua preferência).
6. Após criar a role, selecione-a, vá na aba **Trust relationships** (Relações de confiança), clique em **Edit trust policy** e certifique-se de que a condição restringe o acesso estritamente ao seu repositório GitHub. O JSON deve ser semelhante a:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<SEU_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:LeandroOSBr/ipog-cloud-computing-cartorio:*"
        }
      }
    }
  ]
}
```

7. Copie o **ARN da Role** gerado (exemplo: `arn:aws:iam::123456789012:role/cartorio-digital-github-actions-deploy-role`).

### Passo 3: Configurar os GitHub Secrets
No seu repositório do GitHub:
1. Vá em **Settings** > **Secrets and variables** > **Actions**.
2. Clique em **New repository secret**.
3. Adicione o seguinte secret:
    *   **Name**: `AWS_ROLE_ARN`
    *   **Value**: O ARN da Role copiado no passo anterior.

---

## 🔐 Segurança: Autenticação, MFA & WAF

Com o objetivo de atender integralmente aos requisitos de controle de acesso e auditoria do Provimento nº 213/2026 CNJ, foram adicionadas as seguintes proteções:

### 1. Autenticação por Tokens JWT
Toda chamada para os endpoints de Backend (`/presigned-url` e `/files`) exige o cabeçalho `Authorization: Bearer <ID_TOKEN>`.
* Se um usuário tentar listar ou enviar arquivos sem um token JWT assinado e válido, a API retornará `401 Unauthorized`.
* O Frontend faz o gerenciamento dessa sessão por meio da biblioteca oficial `amazon-cognito-identity.js` (carregada via CDN).

### 2. Segundo Fator de Autenticação (MFA - TOTP)
O MFA está habilitado como opcional no Cognito, com suporte para aplicativos de token de software (TOTP):
1. **Cadastro & Verificação**: O usuário se cadastra pela aba "Criar Conta" e insere o código de validação enviado para o e-mail.
2. **Ativação do MFA**: Após o login, o usuário clica em **Configurar MFA** no canto superior direito do dashboard.
3. **Associação**: O sistema exibe a chave secreta gerada pelo Cognito. O usuário adiciona essa chave no Google Authenticator/Authy e digita o código temporário gerado para ativar.
4. **Desafio**: No próximo login, o Cognito exigirá o código de 6 dígitos gerado pelo Authenticator antes de liberar as credenciais JWT.

### 3. Proteção Web com AWS WAF
A aplicação está sob a proteção de uma **Web ACL Global do AWS WAF** associada à distribuição do CloudFront. O firewall de aplicação possui:
* **AWSManagedRulesCommonRuleSet**: Proteção contra vulnerabilidades web exploradas com frequência (OWASP Top 10).
* **AWSManagedRulesSQLiRuleSet**: Proteção contra injeções SQL que tentam extrair informações indevidamente.

---

## 🚀 Como Executar e Testar

### Implantação Automatizada (CI/CD)

1. Envie suas alterações ou abra um Pull Request para a branch `main`. A esteira irá rodar a verificação de integridade e o `terraform plan`.
2. Ao realizar o merge com a branch `main`, a pipeline no GitHub Actions executará o `terraform apply` automaticamente, empacotará os códigos-fonte do backend com as dependências necessárias (`pypdf`), criará o arquivo dinâmico `config.json` e enviará os assets do frontend para o bucket do S3.
3. No final da execução da pipeline, as URLs do Frontend e da API Gateway estarão ativas.

### Implantação Manual / Local

Caso queira implantar a infraestrutura diretamente da sua máquina local:

1. Acesse o terminal da sua máquina e navegue até a pasta root do projeto.
2. Instale as dependências da Lambda localmente:
   ```bash
   pip install pypdf -t src/backend/process_pdf
   ```
3. Navegue até a pasta `terraform/`:
   ```bash
   cd terraform
   ```
4. Altere a variável de e-mail de notificações no arquivo `variables.tf` (ou passe via CLI) para receber as notificações reais.
5. Inicialize e aplique o Terraform (certifique-se de estar autenticado em sua CLI da AWS):
   ```bash
   terraform init
   ```
   ```bash
   terraform apply -auto-approve
   ```
6. O Terraform exibirá os `outputs` com a URL do frontend. Acesse e teste a aplicação!

---

## 🛡️ Validação da Imutabilidade (Provimento nº 213/2026)

Após realizar o upload de um arquivo PDF no painel, ele será processado e gravado no bucket de armazenamento permanente de conformidade. Você pode validar a proteção contra ransomware e exclusões indevidas executando o comando da AWS CLI para tentar excluir o arquivo processado:

```bash
# Substitua o nome do bucket pelo valor do seu output correspondente
aws s3 rm s3://cartorio-digital-imultavel-xxxx/certificado_xxxx_documento.pdf
```

A AWS retornará um erro informando que o objeto está bloqueado por **Object Lock (Access Denied)**, demonstrando a conformidade estrita e imutabilidade exigida por lei.
