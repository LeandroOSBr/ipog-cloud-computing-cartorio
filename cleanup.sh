#!/bin/bash
# ==============================================================================
# SCRIPT DE CLEANUP AUTOMATIZADO - CARTÓRIO DIGITAL
# Este script remove todos os recursos órfãos criados na AWS relacionados
# ao projeto 'cartorio-digital' (exceto a role de deploy do GitHub Actions).
# ==============================================================================

echo "🔍 Iniciando cleanup dos recursos do 'cartorio-digital'..."

# 1. Obter Account ID atual
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID ativo: $ACCOUNT_ID"

# 2. Deletar Buckets S3 (incluindo todas as versões e delete markers)
echo "🪣 Buscando buckets S3 órfãos..."
BUCKETS=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'cartorio-digital')].Name" --output text)

for BUCKET in $BUCKETS; do
  # Ignorar o bucket de state file para segurança se contiver este nome
  if [[ "$BUCKET" == *"ipog-terraform-state-file"* ]]; then
    echo "⚠️ Ignorando o bucket de state file: $BUCKET"
    continue
  fi

  echo "🧹 Esvaziando bucket: $BUCKET"
  
  # Deletar todas as versões de objetos
  versions=$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --output json)
  if [ "$versions" != "null" ] && [ -n "$versions" ] && [ "$versions" != '{"Objects": null}' ] && [ "$versions" != '{"Objects": []}' ]; then
    echo "Deletando versões de objetos..."
    aws s3api delete-objects --bucket "$BUCKET" --delete "$versions" >/dev/null
  fi
  
  # Deletar todos os marcadores de exclusão (delete markers)
  markers=$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --output json)
  if [ "$markers" != "null" ] && [ -n "$markers" ] && [ "$markers" != '{"Objects": null}' ] && [ "$markers" != '{"Objects": []}' ]; then
    echo "Deletando marcadores de exclusão..."
    aws s3api delete-objects --bucket "$BUCKET" --delete "$markers" >/dev/null
  fi

  echo "❌ Deletando bucket: $BUCKET"
  aws s3 rb "s3://$BUCKET" --force
done

# 3. Deletar funções AWS Lambda
echo "⚡ Buscando funções AWS Lambda..."
FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, 'cartorio-digital')].FunctionName" --output text)

for FUNC in $FUNCTIONS; do
  echo "❌ Deletando função Lambda: $FUNC"
  aws lambda delete-function --function-name "$FUNC"
done

# 4. Deletar CloudWatch Log Groups
echo "📝 Buscando Log Groups no CloudWatch..."
LOG_GROUPS=$(aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'cartorio-digital')].logGroupName" --output text)

for LOG in $LOG_GROUPS; do
  echo "❌ Deletando Log Group: $LOG"
  aws logs delete-log-group --log-group-name "$LOG"
done

# 5. Deletar API Gateway HTTP
echo "🌐 Buscando API Gateways..."
APIS=$(aws apigatewayv2 get-apis --query "Items[?contains(Name, 'cartorio-digital')].ApiId" --output text)

for API in $APIS; do
  echo "❌ Deletando API Gateway ID: $API"
  aws apigatewayv2 delete-api --api-id "$API"
done

# 6. Deletar Tópico SNS
echo "📢 Buscando tópicos SNS..."
TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'cartorio-digital-notifications')].TopicArn" --output text)

for TOPIC in $TOPICS; do
  echo "❌ Deletando tópico SNS: $TOPIC"
  aws sns delete-topic --topic-arn "$TOPIC"
done

# 7. Deletar Roles e Políticas IAM
# Nota: NÃO removemos a role 'github-actions-deploy-role' para manter a pipeline conectada.
echo "🔑 Limpando Roles e Políticas IAM das Lambdas..."
ROLES="cartorio-digital-lambda-api-role cartorio-digital-lambda-processor-role"

for ROLE in $ROLES; do
  if aws iam get-role --role-name "$ROLE" &>/dev/null; then
    echo "Limpando políticas associadas à role: $ROLE"
    POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE" --query "AttachedPolicies[].PolicyArn" --output text)
    
    for POLICY in $POLICIES; do
      echo "Desvinculando política: $POLICY"
      aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY"
      
      # Se for uma política customizada criada para o projeto, deletar
      if [[ "$POLICY" == *"policy/cartorio-digital"* ]]; then
        echo "❌ Deletando política customizada: $POLICY"
        aws iam delete-policy --policy-arn "$POLICY"
      fi
    done
    
    echo "❌ Deletando role: $ROLE"
    aws iam delete-role --role-name "$ROLE"
  else
    echo "Role $ROLE não encontrada."
  fi
done

# 8. Deletar Cognito User Pools
echo "👥 Buscando Cognito User Pools..."
USER_POOLS=$(aws cognito-idp list-user-pools --max-results 60 --query "UserPools[?contains(Name, 'cartorio-digital')].Id" --output text)

for POOL_ID in $USER_POOLS; do
  echo "❌ Deletando Cognito User Pool ID: $POOL_ID"
  aws cognito-idp delete-user-pool --user-pool-id "$POOL_ID"
done

# 9. Deletar WAF Web ACL (Global / CloudFront Scope)
echo "🛡️ Buscando WAF Web ACLs..."
WAF_ACLS=$(aws wafv2 list-web-acls --scope CLOUDFRONT --query "WebACLs[?contains(Name, 'cartorio-digital')].[Name,Id]" --output text)

if [ -n "$WAF_ACLS" ] && [ "$WAF_ACLS" != "None" ]; then
  while read -r WAF_NAME WAF_ID; do
    if [ -n "$WAF_NAME" ] && [ -n "$WAF_ID" ]; then
      echo "Obtendo Lock Token para Web ACL: $WAF_NAME ($WAF_ID)"
      LOCK_TOKEN=$(aws wafv2 get-web-acl --name "$WAF_NAME" --scope CLOUDFRONT --id "$WAF_ID" --query "LockToken" --output text)
      echo "❌ Deletando WAF Web ACL: $WAF_NAME"
      aws wafv2 delete-web-acl --name "$WAF_NAME" --scope CLOUDFRONT --id "$WAF_ID" --lock-token "$LOCK_TOKEN"
    fi
  done <<< "$WAF_ACLS"
fi

echo "🎉 Cleanup concluído com sucesso!"
