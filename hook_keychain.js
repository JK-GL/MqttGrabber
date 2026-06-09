# MQTT 凭据来源 Frida Hook

## 使用方法

### 1. 确保 Frida 已安装

```bash
# 在 Cydia/Sileo 安装 Frida
# 或者手动安装
dpkg -i frida-server*.deb
```

### 2. 启动五菱汽车 App

```bash
# 在手机上打开五菱汽车 App
```

### 3. 运行 Frida 脚本

```bash
# 在电脑上运行
frida -U -n "LingLingBang" -l hook_keychain.js
```

### 4. 查看输出

脚本会显示：
1. **Keychain 读写** — 找到 MQTT 凭据存储位置
2. **MQTT 连接** — 确认凭据值
3. **内存扫描** — 找到凭据在内存中的位置

## 预期输出

```
[KEYCHAIN WRITE] ✅ 写入 MQTT 凭据!
[KEYCHAIN WRITE]   Service: com.cloudy.LingLingBang
[KEYCHAIN WRITE]   Account: mqtt_username
[KEYCHAIN WRITE]   Data: d4a107b765f38550d13a24b54fdcdecf

[MQTT CONNECT] Username: d4a107b765f38550d13a24b54fdcdecf
[MQTT CONNECT] Password: 7c039ddfbdad50f3d0caf974fbcd5a5f
[MQTT CONNECT] ClientID: LK6ADAH92RB765125_4456
```

## 如果没有 Frida

可以用 `keychain_dump` 工具：

```bash
# 安装 keychain_dump
apt-get install keychain-dump

# dump 所有 Keychain 数据
keychain_dump > keychain.txt

# 搜索 MQTT 凭据
grep -i "mqtt\|username\|password" keychain.txt
```

## 注意事项

1. 需要 Dopamine 越狱环境
2. Frida 需要在电脑上运行
3. 如果没有电脑，可以用 `keychain_dump` 工具
