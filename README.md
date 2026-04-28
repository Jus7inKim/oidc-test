# GitHub Actions + Azure OIDC + Terraform 구성 가이드

비밀번호/자격증명 없이 **OIDC(Workload Identity Federation)** 를 사용하여  
GitHub Actions에서 Azure 리소스를 Terraform으로 배포하는 구성입니다.

---

## 전체 아키텍처

```
GitHub Actions Workflow
        │
        │  1. OIDC JWT 토큰 요청
        ▼
GitHub OIDC Provider
(https://token.actions.githubusercontent.com)
        │
        │  2. JWT 토큰 발급 (sub, iss, aud 포함)
        ▼
Azure AD Federated Identity 검증
(UAMI에 등록된 Federated Credential과 sub/iss 일치 확인)
        │
        │  3. Azure Access Token 발급
        ▼
Azure Resources (Terraform으로 프로비저닝)
```

---

## 인증 흐름 상세

| 단계 | 설명 |
|------|------|
| 1 | GitHub Actions 워크플로우 실행 시 `id-token: write` 권한으로 JWT 토큰 요청 |
| 2 | GitHub OIDC Provider가 JWT 발급 (issuer, subject, audience 포함) |
| 3 | `azure/login@v2` 액션이 JWT를 Azure AD에 제출 |
| 4 | Azure AD가 UAMI에 등록된 Federated Credential과 비교 검증 |
| 5 | 검증 성공 시 Azure Access Token 발급 → Terraform이 이 토큰으로 Azure API 호출 |

---

## 레포지토리 구조

```
.
├── .github/
│   └── workflows/
│       └── deploy-terraform.yml    # Terraform Plan & Apply 워크플로우
└── terraform/
    ├── main.tf                     # AzureRM Provider + VNet 리소스 정의
    ├── variables.tf                # 입력 변수 선언
    └── outputs.tf                  # 출력값 정의
```

---

## 사전 준비 사항

### 1. Azure User Managed Identity (UAMI) 생성

```bash
az identity create \
  --name <UAMI_NAME> \
  --resource-group <RG_NAME> \
  --location <LOCATION>
```

생성 후 아래 값을 메모해 둡니다.

| 항목 | 설명 | 확인 명령 |
|------|------|-----------|
| **Client ID** | GitHub Secrets에 등록할 값 | `az identity show --name <UAMI> --resource-group <RG> --query clientId -o tsv` |
| **Object ID (Principal ID)** | 역할 할당 시 사용 | `az identity show ... --query principalId -o tsv` |
| **Tenant ID** | Azure AD 테넌트 ID | `az account show --query tenantId -o tsv` |
| **Subscription ID** | Azure 구독 ID | `az account show --query id -o tsv` |

---

### 2. UAMI Federated Credential 등록

Azure Portal → Managed Identities → `<UAMI>` → Federated credentials → Add

| 항목 | GitHub.com 값 | GitHub Enterprise 값 |
|------|--------------|----------------------|
| **Scenario** | GitHub Actions | GitHub Actions |
| **Issuer** | `https://token.actions.githubusercontent.com` | `https://<GHES_HOST>/_services/token` |
| **Organization** | GitHub 조직/계정명 | GitHub Enterprise 조직/계정명 |
| **Repository** | 레포지토리 이름 | 레포지토리 이름 |
| **Entity** | Environment | Environment |
| **Environment** | `production` | `production` |

> **Subject Identifier (자동 생성):**  
> `repo:<org>/<repo>:environment:production`

---

### 3. UAMI 역할 할당

Terraform이 배포할 대상 리소스 그룹에 Contributor 권한을 부여합니다.

```bash
az role assignment create \
  --assignee "<UAMI_OBJECT_ID>" \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>"
```

> UAMI는 구독 레벨 권한이 없으므로 리소스 그룹 범위로 할당합니다.  
> `skip_provider_registration = true` 설정이 이를 우회합니다.

---

### 4. GitHub Secrets 등록

레포지토리 → Settings → Secrets and variables → Actions → **Secrets 탭** → New repository secret

| Secret 이름 | 값 | 비고 |
|-------------|-----|------|
| `AZURE_CLIENT_ID` | UAMI의 **Client ID** | Object ID 아님 주의 |
| `AZURE_TENANT_ID` | Azure AD Tenant ID | |
| `AZURE_SUBSCRIPTION_ID` | Azure Subscription ID | |

> **Secret 이름 변경 시**: 이름을 다르게 사용하는 경우(예: `CLIENT_ID`, `TENANT_ID`, `SUBSCRIPTION_ID`) 워크플로우 파일의 `secrets.*` 참조도 동일하게 변경해야 합니다.
>
> ```yaml
> # deploy-terraform.yml 내 변경 위치 (총 4곳)
> env:
>   ARM_CLIENT_ID: ${{ secrets.CLIENT_ID }}           # AZURE_CLIENT_ID → CLIENT_ID
>   ARM_TENANT_ID: ${{ secrets.TENANT_ID }}           # AZURE_TENANT_ID → TENANT_ID
>   ARM_SUBSCRIPTION_ID: ${{ secrets.SUBSCRIPTION_ID }} # AZURE_SUBSCRIPTION_ID → SUBSCRIPTION_ID
> ```

---

### 5. GitHub Actions Variables 등록 (선택)

레포지토리 → Settings → Secrets and variables → Actions → **Variables 탭** → New repository variable

Secrets는 암호화되어 로그에 마스킹되지만, **Variables**는 비민감 설정값을 외부에서 관리할 때 사용합니다.

| Variable 이름 | 값 예시 | 설명 |
|---------------|---------|------|
| `TF_RESOURCE_GROUP` | `AZ-GITACTION-RG` | 기본 리소스 그룹 (워크플로우 default 대체 가능) |
| `TF_LOCATION` | `koreacentral` | 기본 Azure 리전 |
| `TF_VNET_NAME` | `vnet-oidc-test` | 기본 VNet 이름 |

Variables를 워크플로우 default 값으로 활용하려면 아래처럼 수정합니다:

```yaml
# deploy-terraform.yml
inputs:
  resource_group_name:
    default: ${{ vars.TF_RESOURCE_GROUP }}
  location:
    default: ${{ vars.TF_LOCATION }}
  vnet_name:
    default: ${{ vars.TF_VNET_NAME }}
```

> **Secrets vs Variables 선택 기준**
> - 🔒 **Secrets**: Client ID, Tenant ID, Subscription ID 등 외부 노출 시 보안 위험이 있는 값
> - 📋 **Variables**: 리소스 그룹명, 리전, VNet 이름 등 환경마다 달라지는 비민감 설정값

---

### 5. GitHub Environment 생성

레포지토리 → Settings → Environments → New environment

- 이름: `production`
- (선택) Required reviewers, deployment branches 설정 가능

---

## GitHub Enterprise Server (GHES) 적용 시 변경 사항

### 변경 필요 항목 요약

| 항목 | GitHub.com | GitHub Enterprise Server |
|------|-----------|--------------------------|
| OIDC Issuer URL | `https://token.actions.githubusercontent.com` | `https://<GHES_HOST>/_services/token` |
| Federated Credential Issuer | (위와 동일) | **`https://<GHES_HOST>/_services/token`** 으로 변경 |
| 워크플로우 파일 | 변경 없음 | 변경 없음 |
| Secrets | 변경 없음 | 변경 없음 |

---

### 변경 1: Azure UAMI Federated Credential Issuer 수정

Azure Portal에서 기존 Federated Credential을 수정하거나 새로 생성합니다.

**Issuer 필드를 아래로 변경:**
```
https://github.ecodesamsung.com/_services/token
```

> Azure Portal에서 Issuer 필드는 기본적으로 수정 불가(회색)로 표시됩니다.  
> **"Edit (optional)"** 링크를 클릭하면 직접 입력할 수 있습니다.

또는 Azure CLI로 등록:

```bash
az identity federated-credential create \
  --identity-name <UAMI_NAME> \
  --resource-group <UAMI_RG> \
  --name "github-oidc-production" \
  --issuer "https://github.ecodesamsung.com/_services/token" \
  --subject "repo:<org>/<repo>:environment:production" \
  --audiences "api://AzureADTokenExchange"
```

---

### 변경 2: GHES OIDC 기능 활성화 확인

GHES 관리자가 아래 설정을 활성화했는지 확인합니다.

```
GitHub Enterprise Server → Site Admin → Settings
→ GitHub Actions → Enable OIDC for GitHub Actions
```

OIDC 발급 엔드포인트 확인:
```
https://<GHES_HOST>/_services/token/.well-known/openid-configuration
```

---

### 변경 3: (선택) azure/login 액션 audience 명시

GHES 환경에 따라 audience가 다를 수 있습니다. 워크플로우에서 명시적으로 지정합니다.

```yaml
- name: Azure OIDC Login
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    audience: api://AzureADTokenExchange   # 명시적 지정 (GHES 환경 권장)
```

---

## 워크플로우 사용 방법

### Terraform Plan (변경 사항 미리 보기)

GitHub → Actions → `02 - Terraform Plan & Apply` → Run workflow

| 입력 항목 | 기본값 | 설명 |
|-----------|--------|------|
| `resource_group_name` | `AZ-GITACTION-RG` | 대상 리소스 그룹 |
| `location` | `koreacentral` | Azure 리전 |
| `vnet_name` | `vnet-oidc-test` | 생성할 VNet 이름 |
| `action` | `plan` | `plan` / `apply` / `destroy` |

### Terraform Apply (실제 배포)

동일하게 실행하되 `action`을 `apply`로 선택합니다.  
`production` Environment 보호 규칙이 설정된 경우 승인 후 실행됩니다.

### Terraform Destroy (리소스 삭제)

`action`을 `destroy`로 선택합니다.

---

## Terraform 리소스 구성

| 리소스 | 이름 | 설명 |
|--------|------|------|
| `azurerm_virtual_network` | `var.vnet_name` | Address Space: `10.0.0.0/16` |
| `azurerm_subnet` | `snet-default` | `10.0.1.0/24` |
| `azurerm_subnet` | `snet-app` | `10.0.2.0/24` |

---

## Terraform 변수 목록

| 변수명 | 기본값 | 필수 여부 | 설명 |
|--------|--------|-----------|------|
| `subscription_id` | - | ✅ 필수 | Azure Subscription ID (Secrets에서 주입) |
| `tenant_id` | - | ✅ 필수 | Azure Tenant ID (Secrets에서 주입) |
| `client_id` | - | ✅ 필수 | UAMI Client ID (Secrets에서 주입) |
| `resource_group_name` | `AZ-GITACTION-RG` | 선택 | 대상 리소스 그룹 |
| `location` | `koreacentral` | 선택 | Azure 리전 |
| `vnet_name` | `vnet-oidc-test` | 선택 | VNet 이름 |

---

## 트러블슈팅

| 오류 | 원인 | 해결 방법 |
|------|------|-----------|
| `AADSTS700016` | Client ID가 아닌 Object ID 입력 | `AZURE_CLIENT_ID` Secret을 Client ID 값으로 재등록 |
| `AuthorizationFailed` on Resource Provider registration | UAMI에 구독 레벨 권한 없음 | `skip_provider_registration = true` 설정 (이미 적용됨) |
| `AuthorizationFailed` on resource group read | UAMI에 해당 RG 권한 없음 | `az role assignment create`로 RG에 Contributor 할당 |
| `tfplan not found` | `terraform plan -detailed-exitcode`의 exit code 2를 실패로 처리 | `terraform_wrapper: false` + `\|\| EXIT_CODE=$?` 패턴 사용 (이미 적용됨) |
| OIDC token issuer mismatch | Federated Credential의 Issuer가 실제 OIDC 발급자와 불일치 | GHES 사용 시 Issuer를 `https://<GHES_HOST>/_services/token`으로 변경 |
