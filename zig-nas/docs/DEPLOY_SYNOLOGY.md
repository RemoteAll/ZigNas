# Synology NAS (ARMv7) 部署指南

本指南适用于在 Synology NAS（如 DS218j）等 ARMv7 架构设备上部署 zig-nas 项目。

## 目标设备信息

- **设备型号**: Synology DS218j（或其他 armv7l 设备）
- **CPU 架构**: ARMv7 Processor (v7l)
- **操作系统**: Linux (Synology Linux 内核)
- **内核版本**: 3.10.108 或更高
- **ABI**: GNU EABI 硬浮点 (gnueabihf)

## 前置要求

### 开发机器（编译环境）
- Zig 0.15.2 或更高版本
- Windows、Linux 或 macOS 均可

### 目标设备（Synology NAS）
- 已启用 SSH 访问（控制面板 → 终端机和 SNMP → 启动 SSH 功能）
- 具有管理员权限的用户账户
- 可选：安装 Docker 套件（用于容器化部署）

## 编译步骤

### 方式 1：编译所有交叉平台目标

在项目根目录执行：

```powershell
# Windows PowerShell
cd f:\Project\ZigNas\zig-nas
zig build

# 检查生成的 ARMv7 可执行文件
Get-ChildItem zig-out\bin\*armv7*
```

生成的文件：
- `zig-out/bin/zig_nas-linux-armv7` - 专为 Synology ARMv7l 优化（推荐）
- `zig-out/bin/zig_nas-linux-arm-musl` - musl libc 版本（备选，适用于 OpenWrt 等）

### 方式 2：仅编译 ARMv7 目标

指定目标架构编译：

```powershell
# 编译 Synology NAS 版本（glibc + 硬浮点）
zig build -Dtarget=arm-linux-gnueabihf -Doptimize=ReleaseSmall

# 或编译 musl 版本（更通用但性能略低）
zig build -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseSmall
```

### 编译优化说明

| 优化模式 | 二进制体积 | 性能 | 调试友好 | 推荐场景 |
|---------|----------|-----|---------|---------|
| ReleaseSmall | 最小 | 中 | 否 | **NAS 默认**（存储空间有限） |
| ReleaseFast | 较大 | 高 | 否 | 高性能需求 |
| ReleaseSafe | 中等 | 中 | 是 | 开发调试 |

**平台自动优化**：
- ARMv7 设备默认使用 `ReleaseSmall` + 静态链接
- 自动启用 strip 减小体积
- 静态链接避免依赖问题

## 部署步骤

### 1. 传输文件到 NAS

使用 SCP、SFTP 或 Synology File Station 传输：

**方式 A：SCP（推荐）**
```powershell
# 传输到 NAS（替换 IP 地址和用户名）
scp zig-out/bin/zig_nas-linux-armv7 admin@192.168.1.100:/volume1/homes/admin/
```

**方式 B：WinSCP / FileZilla**
1. 连接到 NAS（SFTP 协议，端口 22）
2. 将文件上传到 `/volume1/homes/admin/` 或 `/opt/`

### 2. SSH 登录 NAS

```bash
ssh admin@192.168.1.100
```

### 3. 安装与配置

```bash
# 创建应用目录
sudo mkdir -p /opt/zig-nas
sudo mv ~/zig_nas-linux-armv7 /opt/zig-nas/zig_nas

# 设置执行权限
sudo chmod +x /opt/zig-nas/zig_nas

# 验证二进制文件
file /opt/zig-nas/zig_nas
# 输出应包含: ELF 32-bit LSB executable, ARM, EABI5 version 1

# 检查依赖（静态链接版本应显示 "not a dynamic executable"）
ldd /opt/zig-nas/zig_nas
```

### 4. 运行测试

```bash
cd /opt/zig-nas
./zig_nas
```

预期输出：
```
All your codebase are belong to us.
Run `zig build test` to run the tests.
```

## 开机自启动配置

### 方式 1：Synology 任务计划

1. 打开 DSM 控制面板 → 任务计划
2. 新增 → 触发的任务 → 用户定义的脚本
3. 常规设置：
   - 任务名称：`zig-nas-autostart`
   - 用户：`root`
   - 事件：开机
4. 任务设置 → 用户定义的脚本：
   ```bash
   #!/bin/bash
   /opt/zig-nas/zig_nas > /var/log/zig-nas.log 2>&1 &
   ```

### 方式 2：init.d 脚本

创建服务脚本 `/usr/local/etc/rc.d/zig-nas.sh`：

```bash
#!/bin/bash

case "$1" in
    start)
        echo "Starting zig-nas..."
        /opt/zig-nas/zig_nas > /var/log/zig-nas.log 2>&1 &
        echo $! > /var/run/zig-nas.pid
        ;;
    stop)
        echo "Stopping zig-nas..."
        kill $(cat /var/run/zig-nas.pid)
        rm /var/run/zig-nas.pid
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac
```

设置权限：
```bash
sudo chmod +x /usr/local/etc/rc.d/zig-nas.sh
```

## 性能优化建议

### 1. CPU 亲和性（多核 NAS）
```bash
# 绑定到特定 CPU 核心
taskset -c 0 /opt/zig-nas/zig_nas
```

### 2. 进程优先级
```bash
# 降低优先级避免影响 NAS 核心服务
nice -n 10 /opt/zig-nas/zig_nas
```

### 3. 内存限制（可选）
```bash
# 限制最大内存使用（需要 cgroup 支持）
systemd-run --scope -p MemoryMax=256M /opt/zig-nas/zig_nas
```

## 故障排查

### 问题 1：权限不足
```bash
# 错误: Permission denied
sudo chown root:root /opt/zig-nas/zig_nas
sudo chmod +x /opt/zig-nas/zig_nas
```

### 问题 2：动态库缺失（musl 版本）
```bash
# 错误: /lib/ld-musl-armhf.so.1: No such file or directory
# 解决: 使用 glibc 版本 (zig_nas-linux-armv7)
```

### 问题 3：非法指令错误
```bash
# 错误: Illegal instruction
# 原因: CPU 不支持编译目标的指令集
# 解决: 重新编译，指定更低的 CPU 基准
zig build -Dtarget=arm-linux-gnueabihf -Dcpu=baseline -Doptimize=ReleaseSmall
```

### 问题 4：查看系统架构信息
```bash
# 确认 CPU 架构
uname -m  # 应显示: armv7l

# 查看 CPU 详细信息
cat /proc/cpuinfo | grep -E "Processor|Features|CPU"

# 查看系统 ABI
file /bin/ls | grep ARM
```

## 卸载

```bash
# 停止服务
sudo /usr/local/etc/rc.d/zig-nas.sh stop

# 删除文件
sudo rm -rf /opt/zig-nas
sudo rm /usr/local/etc/rc.d/zig-nas.sh
sudo rm /var/log/zig-nas.log

# 删除任务计划（通过 DSM 控制面板）
```

## 技术细节

### 平台检测逻辑

`build.zig` 自动检测 ARMv7 设备并应用优化：

```zig
// 检测嵌入式 ARM 设备
const is_embedded_arm = blk: {
    if (cpu_arch != .arm) break :blk false;
    
    // 检测 gnueabihf/musleabihf ABI
    if (target_query.abi) |abi| {
        if (abi == .musleabi or abi == .musleabihf or 
            abi == .gnueabi or abi == .gnueabihf) {
            break :blk true;
        }
    }
    break :blk false;
};

// 应用平台优化
if (is_embedded_arm) {
    return PlatformConfig{
        .optimize = .ReleaseSmall,  // 体积优先
        .linkage = .static,         // 静态链接
        .strip = true,              // 移除符号表
    };
}
```

### 交叉编译目标对比

| 目标标识 | ABI | libc | 浮点 | 适用设备 |
|---------|-----|------|-----|---------|
| `linux-armv7` | gnueabihf | glibc | 硬件 | **Synology NAS（推荐）** |
| `linux-arm-musl` | musleabihf | musl | 硬件 | OpenWrt 路由器 |
| `linux-aarch64` | gnu | glibc | - | ARM64 服务器 |

## 参考资源

- [Zig 交叉编译文档](https://ziglang.org/learn/overview/#cross-compiling-is-a-first-class-use-case)
- [Synology DSM 开发者指南](https://help.synology.com/developer-guide/)
- [ARM 架构参考手册](https://developer.arm.com/documentation/)

---

**提示**：本指南基于 Zig 0.15.2+ 版本，不同版本可能需调整编译参数。
