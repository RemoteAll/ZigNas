# Synology NAS 快速部署脚本
# 用法: .\deploy-to-nas.ps1 -NasIP "192.168.1.100" -NasUser "admin"

param(
    [Parameter(Mandatory=$true)]
    [string]$NasIP,
    
    [Parameter(Mandatory=$true)]
    [string]$NasUser,
    
    [string]$BinaryPath = "zig-out\bin\zig_nas-linux-armv7",
    
    [string]$TargetDir = "/opt/zig-nas"
)

# 颜色输出函数
function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Error { Write-Host "[ERROR] $args" -ForegroundColor Red }

Write-Info "=== Synology NAS 部署脚本 ==="
Write-Info "目标设备: $NasUser@$NasIP"
Write-Info "二进制文件: $BinaryPath"
Write-Info ""

# 步骤 1: 检查本地文件
if (-not (Test-Path $BinaryPath)) {
    Write-Error "找不到可执行文件: $BinaryPath"
    Write-Info "请先运行: zig build"
    exit 1
}

$fileInfo = Get-Item $BinaryPath
Write-Success "找到可执行文件: $($fileInfo.Name) ($([math]::Round($fileInfo.Length/1KB, 2)) KB)"

# 步骤 2: 检查 SSH 连接
Write-Info "测试 SSH 连接..."
$sshTest = ssh -o ConnectTimeout=5 -o BatchMode=yes $NasUser@$NasIP "echo OK" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "SSH 连接失败，请检查:"
    Write-Host "  1. NAS IP 地址是否正确"
    Write-Host "  2. SSH 服务是否已启用 (DSM → 控制面板 → 终端机和 SNMP)"
    Write-Host "  3. SSH 密钥是否已配置，或准备好输入密码"
    exit 1
}
Write-Success "SSH 连接正常"

# 步骤 3: 传输文件
Write-Info "传输文件到 NAS..."
scp $BinaryPath ${NasUser}@${NasIP}:~/zig_nas-temp
if ($LASTEXITCODE -ne 0) {
    Write-Error "文件传输失败"
    exit 1
}
Write-Success "文件传输完成"

# 步骤 4: 远程安装
Write-Info "在 NAS 上安装..."
$installScript = @"
sudo mkdir -p $TargetDir && \
sudo mv ~/zig_nas-temp $TargetDir/zig_nas && \
sudo chmod +x $TargetDir/zig_nas && \
echo 'Installation complete'
"@

ssh $NasUser@$NasIP $installScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "安装失败（可能需要输入 sudo 密码）"
    exit 1
}
Write-Success "安装完成"

# 步骤 5: 验证安装
Write-Info "验证安装..."
$verifyScript = @"
file $TargetDir/zig_nas && \
ldd $TargetDir/zig_nas 2>&1 | head -n 3
"@

Write-Host ""
Write-Host "=== 二进制信息 ===" -ForegroundColor Yellow
ssh $NasUser@$NasIP $verifyScript
Write-Host ""

# 步骤 6: 运行测试
Write-Info "运行测试..."
Write-Host "=== 程序输出 ===" -ForegroundColor Yellow
ssh $NasUser@$NasIP "$TargetDir/zig_nas"
Write-Host ""

# 完成
Write-Success "========================================="
Write-Success "部署成功！"
Write-Success "========================================="
Write-Host ""
Write-Host "可执行文件路径: $TargetDir/zig_nas" -ForegroundColor Cyan
Write-Host ""
Write-Host "后续操作:" -ForegroundColor Yellow
Write-Host "  1. SSH 登录: ssh $NasUser@$NasIP"
Write-Host "  2. 手动运行: $TargetDir/zig_nas"
Write-Host "  3. 配置开机自启（参考 docs/DEPLOY_SYNOLOGY.md）"
Write-Host ""
