# Azure Blob Storage — rclone 폐쇄망 설정 가이드

이 디렉토리는 Azure Blob Storage 전용 rclone 설정 파일과 스크립트를 포함합니다.

---

## 파일 구조

```
azure/
├── README-azureblob.md          ← 이 파일
├── rclone-azureblob.conf        ← 전체 인증 방식 주석 템플릿
├── conf-examples/
│   ├── azblob-key.conf          ← mount 설정: Account Key 인증
│   ├── azblob-sp.conf           ← mount 설정: Service Principal
│   └── azblob-msi.conf          ← mount 설정: Managed Identity
└── certs/                       ← SP 인증서 배치 위치 (설치 후: /etc/rclone/certs/)
```

---

## 인증 방식 선택

### 폐쇄망 환경에서의 권장 순서

```
우선순위  방식                     login.microsoft.com 필요 여부
  ①      Account Key (Shared Key)  ❌ 불필요 (가장 안전한 폐쇄망 선택)
  ②      Connection String         ❌ 불필요
  ③      SAS URL                   ❌ 불필요 (만료 기한 주의)
  ④      Service Principal         ✅ 필요 (Private Link + DNS 오버라이드)
  ⑤      Managed Identity (MSI)    ✅ 필요 (Azure VM 한정)
  ⑥      env_auth                  ✅ 필요
```

> **핵심:** `disable_instance_discovery = true` 를 반드시 추가해야  
> rclone 이 `https://login.microsoft.com/` 에 메타데이터 조회를 하지 않습니다.

---

## 빠른 설정

### 옵션 A: 도우미 스크립트 (권장)

```bash
bash scripts/configure-azureblob.sh
```

인터랙티브하게 인증 방식을 선택하고 `/etc/rclone/rclone.conf` 에 추가합니다.

### 옵션 B: 수동 편집

`azure/rclone-azureblob.conf` 에서 원하는 섹션의 주석을 해제하고
`/etc/rclone/rclone.conf` 에 복사합니다.

```bash
# 예시: Account Key 방식
cat >> /etc/rclone/rclone.conf << 'EOF'

[azblob]
type                     = azureblob
account                  = mystorageaccount
key                      = Base64EncodedAccessKey==
disable_instance_discovery = true
upload_concurrency       = 16
chunk_size               = 4M
EOF
```

---

## 인증 방식별 상세 설정

### ① Account Key — 가장 단순하고 폐쇄망에 적합

```ini
[azblob]
type                     = azureblob
account                  = <스토리지계정이름>
key                      = <Base64인코딩AccessKey>
disable_instance_discovery = true
```

**Key 확인 위치:** Azure Portal → 스토리지 계정 → 보안 + 네트워킹 → 액세스 키

---

### ② SAS URL

```ini
[azblob-sas]
type                     = azureblob
sas_url                  = https://<account>.blob.core.windows.net/?sv=2022-11-02&ss=b&srt=sco&sp=rwdlacuptfx&se=2026-12-31T00:00:00Z&st=2025-01-01T00:00:00Z&spr=https&sig=<SIGNATURE>
disable_instance_discovery = true
```

**주의:** SAS URL 은 만료 기한이 있습니다. 장기 운용에는 Account Key 방식이 적합합니다.

---

### ③ Connection String

```ini
[azblob-conn]
type                     = azureblob
connection_string        = DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>;EndpointSuffix=core.windows.net
disable_instance_discovery = true
```

---

### ④ Service Principal (Client Secret)

Azure AD 앱 등록 후 Storage Blob 역할 할당이 필요합니다.

```bash
# Azure CLI로 앱 등록 및 역할 할당 (인터넷 있는 머신에서 수행)
az ad sp create-for-rbac \
  --name "rclone-sp" \
  --role "Storage Blob Data Contributor" \
  --scopes "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<SA>"
```

```ini
[azblob-sp]
type                     = azureblob
account                  = <스토리지계정이름>
tenant                   = <TenantID>
client_id                = <AppClientID>
client_secret            = <ClientSecret>
disable_instance_discovery = true
```

**폐쇄망 주의:** `login.microsoftonline.com` 접근이 필요합니다.  
→ Private Link for Azure AD 또는 Microsoft Entra Private Endpoint 구성 필요

---

### ④-b Service Principal (인증서)

```bash
# 인증서 생성 (OpenSSL)
openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/rclone/certs/sp-key.pem \
  -out /etc/rclone/certs/sp-cert.pem \
  -days 365 -nodes -subj "/CN=rclone-sp"

# 인증서를 Azure AD 앱에 업로드 후:
rclone obscure <cert-password>  # 암호가 있는 경우
```

```ini
[azblob-sp-cert]
type                          = azureblob
account                       = <스토리지계정이름>
tenant                        = <TenantID>
client_id                     = <AppClientID>
client_certificate_path       = /etc/rclone/certs/sp-cert.pem
# client_certificate_password = <rclone obscure 결과>
disable_instance_discovery    = true
```

---

### ⑤ Managed Identity (Azure VM 전용)

VM에 관리 ID 할당 후 Storage Blob 역할을 부여합니다.

```bash
# 역할 할당 (Azure CLI)
az role assignment create \
  --assignee <VM-Principal-ID> \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<SA>"
```

```ini
[azblob-msi]
type                     = azureblob
account                  = <스토리지계정이름>
use_msi                  = true
# 사용자 할당 MSI인 경우:
# msi_client_id          = <MSI-ClientID>
disable_instance_discovery = true
```

---

## Private Endpoint 설정

Azure Storage Private Endpoint 사용 시:

1. **DNS 오버라이드** (VM의 `/etc/hosts` 또는 내부 DNS):
   ```
   10.0.1.5   mystorageaccount.blob.core.windows.net
   ```

2. **rclone.conf endpoint 명시:**
   ```ini
   endpoint = https://mystorageaccount.blob.core.windows.net
   ```

3. **TLS 인증서:** Private Endpoint 는 동일한 공개 인증서를 사용하므로 별도 CA 설정 불필요  
   (단, 인터넷 차단 환경에서 CRL/OCSP 확인이 실패할 수 있으면 `RCLONE_AZUREBLOB_DISABLE_INSTANCE_DISCOVERY=true` 확인)

---

## mount 운영

### 포어그라운드 테스트

```bash
mkdir -p /mnt/azureblob

rclone mount azblob:mycontainer /mnt/azureblob \
  --vfs-cache-mode writes \
  --vfs-cache-max-size 2G \
  --buffer-size 256M \
  --allow-other \
  --log-level INFO &

# 확인
ls /mnt/azureblob
df -h /mnt/azureblob

# 언마운트
fusermount3 -u /mnt/azureblob
```

### systemd 영구 마운트

```bash
# mount 설정 파일 생성
sudo mkdir -p /etc/rclone/mounts
sudo tee /etc/rclone/mounts/myblob.conf << 'EOF'
REMOTE=azblob:mycontainer
MOUNTPOINT=/mnt/azureblob
EXTRA_ARGS=--allow-other --vfs-cache-mode writes --vfs-cache-max-size 2G
EOF

# 마운트 포인트 생성
sudo mkdir -p /mnt/azureblob

# 서비스 시작
sudo systemctl daemon-reload
sudo systemctl start  rclone-azureblob@myblob.service
sudo systemctl enable rclone-azureblob@myblob.service

# 로그 확인
sudo journalctl -u rclone-azureblob@myblob.service -f
# 또는
sudo tail -f /var/log/rclone/azureblob-myblob.log
```

---

## 성능 튜닝

| 시나리오 | 권장 설정 |
|----------|----------|
| 소용량 파일 다수 | `--vfs-cache-mode writes --dir-cache-time 30s` |
| 대용량 파일 업로드 | `--azureblob-upload-concurrency 64 --azureblob-chunk-size 16M` |
| 읽기 위주 | `--vfs-cache-mode minimal --buffer-size 512M` |
| 저지연 필요 | `--vfs-cache-mode full --vfs-cache-max-size 20G` |
| 1Gbps 링크 | `--azureblob-upload-concurrency 64 --buffer-size 512M` |

---

## 검증

```bash
# 기본 환경 검증
bash scripts/verify-azureblob.sh

# 연결 + 컨테이너 목록
bash scripts/verify-azureblob.sh --remote azblob

# 마운트 동작 테스트까지
bash scripts/verify-azureblob.sh --remote azblob --container mycontainer --mount
```

---

## 트러블슈팅

### `AuthenticationFailed` / 403

- Account Key 확인: Azure Portal → 액세스 키 → Key1/Key2 중 하나
- SAS URL 만료 여부 확인
- SP 역할 할당: `Storage Blob Data Contributor` 또는 `Storage Blob Data Reader`

### `context deadline exceeded` / 타임아웃

- 네트워크 차단: `curl -v https://<account>.blob.core.windows.net`
- Private Endpoint DNS: `nslookup <account>.blob.core.windows.net`
- rclone 에 `--contimeout 30s --timeout 60s` 추가

### `login.microsoft.com` 접속 오류

```ini
disable_instance_discovery = true
```
반드시 추가. SP/MSI/env_auth 방식은 추가로 `login.microsoftonline.com` 도 필요.

### 마운트 후 파일이 보이지 않음

```bash
rclone ls azblob:mycontainer   # 직접 조회로 확인
# 성공하면 VFS 캐시 문제: --dir-cache-time 5s 로 줄여서 테스트
```
