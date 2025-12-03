# zig-nas

跨平台 NAS 应用程序，使用 Zig 0.15.2+ 开发，支持多种架构。

## 支持的平台

| 平台 | 架构 | 优化策略 | 典型设备 |
|------|------|---------|---------|
| **Linux** | x86_64 | ReleaseFast（高性能） | 服务器 |
| **Linux** | aarch64 | ReleaseFast（高性能） | ARM64 服务器 |
| **Linux** | ARMv7 | ReleaseSmall（体积优先） | **Synology NAS**, OpenWrt 路由器 |
| **Windows** | x86_64 | ReleaseFast | 桌面/服务器 |
| **macOS** | x86_64/arm64 | ReleaseFast | 桌面 |

### ARMv7 专项支持

针对 **Synology DS218j** 等 ARMv7l 设备进行了优化：

- ✅ **静态链接**：无需额外依赖，开箱即用
- ✅ **体积优化**：启用 ReleaseSmall + strip，二进制体积 < 10KB
- ✅ **ABI 兼容**：支持 glibc (gnueabihf) 和 musl (musleabihf)
- ✅ **平台自动检测**：`build.zig` 自动应用最佳配置

## 快速开始

### 1. 编译项目

```bash
# 编译所有平台目标
zig build

# 仅编译本机目标
zig build -Dtarget=native

# 编译 Synology NAS (ARMv7)
zig build -Dtarget=arm-linux-gnueabihf -Doptimize=ReleaseSmall
```

### 2. 运行测试

```bash
# 本机运行
zig build run

# 运行单元测试
zig build test
```

### 3. 查看生成文件

```bash
# Linux/macOS
ls -lh zig-out/bin/

# Windows PowerShell
Get-ChildItem zig-out\bin | Select-Object Name, Length
```

编译输出：
```
zig_nas-linux-armv7        (9.8 KB)  ← Synology NAS
zig_nas-linux-arm-musl     (9.8 KB)  ← OpenWrt 路由器
zig_nas-linux-aarch64      (880 KB)  ← ARM64 服务器
zig_nas-linux-x86_64       (856 KB)  ← x86_64 Linux
zig_nas-windows-x86_64.exe (930 KB)  ← Windows
```

## 部署到 Synology NAS

### 自动部署（推荐）

使用 PowerShell 脚本一键部署：

```powershell
# Windows
.\deploy-to-nas.ps1 -NasIP "192.168.1.100" -NasUser "admin"
```

### 手动部署

```bash
# 1. 传输文件
scp zig-out/bin/zig_nas-linux-armv7 admin@192.168.1.100:~/

# 2. SSH 登录 NAS
ssh admin@192.168.1.100

# 3. 安装
sudo mkdir -p /opt/zig-nas
sudo mv ~/zig_nas-linux-armv7 /opt/zig-nas/zig_nas
sudo chmod +x /opt/zig-nas/zig_nas

# 4. 运行
/opt/zig-nas/zig_nas
```

📖 **完整部署指南**：[docs/DEPLOY_SYNOLOGY.md](docs/DEPLOY_SYNOLOGY.md)

## 开发环境

### 前置要求

- **Zig**: 0.15.2 或更高版本
- **操作系统**: Windows 10+, Linux 4.4+, macOS 10.13+
- **工具**: Git, SSH 客户端（用于 NAS 部署）

### 安装 Zig

```bash
# Linux/macOS (使用官方安装脚本)
curl https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz | tar -xJ
export PATH=$PATH:$(pwd)/zig-linux-x86_64-0.15.2

# Windows (使用 Scoop)
scoop install zig

# 或直接下载：https://ziglang.org/download/
```

### 项目结构

```
zig-nas/
├── build.zig              # 构建配置（含平台检测）
├── build.zig.zon          # 依赖管理
├── src/
│   ├── main.zig          # 程序入口
│   └── root.zig          # 库入口
├── docs/
│   └── DEPLOY_SYNOLOGY.md # Synology 部署指南
└── deploy-to-nas.ps1     # 自动部署脚本
```

## 平台特定优化

`build.zig` 自动检测目标平台并应用优化：

| 检测条件 | 优化策略 | 目标设备 |
|---------|---------|---------|
| ARM 32位 + musl/glibc | ReleaseSmall + 静态 | 嵌入式/NAS |
| x86_64/aarch64 + glibc | ReleaseFast + 动态 | 高性能服务器 |
| 其他 | 用户指定 | 通用设备 |

### 手动覆盖优化

```bash
# 强制使用 ReleaseFast（牺牲体积换取性能）
zig build -Dtarget=arm-linux-gnueabihf -Doptimize=ReleaseFast

# 强制静态链接
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast -Dlinkage=static
```

## 故障排查

### 1. 编译失败

```bash
# 确认 Zig 版本（必须 >= 0.15.2）
zig version

# 清理缓存重新编译
rm -rf zig-cache zig-out
zig build
```

### 2. NAS 运行失败

```bash
# 检查文件类型
file /opt/zig-nas/zig_nas
# 预期输出: ELF 32-bit LSB executable, ARM, EABI5 version 1

# 检查依赖（静态链接应显示 "not a dynamic executable"）
ldd /opt/zig-nas/zig_nas

# 查看系统架构
uname -m  # 应显示: armv7l
```

### 3. 非法指令错误

```bash
# 使用更低的 CPU 基准重新编译
zig build -Dtarget=arm-linux-gnueabihf -Dcpu=baseline -Doptimize=ReleaseSmall
```

## 贡献指南

欢迎提交 Pull Request！请确保：

1. 遵循 [PeiKeSmart Copilot 协作指令](.github/copilot-instructions.md)
2. 代码通过 `zig build test`
3. 交叉编译目标全部成功构建

## 许可证

[查看 LICENSE 文件](LICENSE)

## 相关资源

- [Zig 官方文档](https://ziglang.org/documentation/master/)
- [Zig 交叉编译指南](https://ziglang.org/learn/overview/#cross-compiling-is-a-first-class-use-case)
- [Synology DSM 开发者指南](https://help.synology.com/developer-guide/)

---

**提示**：本项目基于 Zig 0.15.2+，利用其强大的交叉编译能力实现 "一次编译，多平台运行"。
