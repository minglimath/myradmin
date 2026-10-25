# AutoRadmin 2.0

自动完成 Radmin Viewer 登录：读配置 → 启动 Radmin Viewer → 把账号密码填进「Radmin 安全」窗口。

2.0 的核心变化：**不再自带便携版 Radmin**，直接调用你本机已安装的 Radmin Viewer，路径写在 `config.ini` 里。

---

## 一、和 1.0 的运行机制对比

| | 1.0（旧） | 2.0（本版） |
|---|---|---|
| Radmin 来源 | 内置 `RadminViewerPortable.zip`，用 `7za.exe` 解压到 `%TEMP%\AutoRadmin\` 后启动 | 直接 `Run` 本机已安装的 `Radmin.exe` |
| 路径来源 | 固定在临时目录 | `config.ini` 的 `RADMINDIR`，可写目录也可写完整 exe 路径 |
| 依赖文件 | `7za.exe` + zip 必须一起打包 | 只需 `AutoRadmin.au3` + `icon.ico` |
| 路径失效时 | 直接报错 | 自动探测 → 弹选择框 → 写回配置 |
| 已在运行 | 一律退出 | `IFRUNNING=continue`（新建连接）/ `exit`（退出） |

`RadminViewerPortable.zip` 和 `7za.exe` 这两个文件现在用不到了，可以直接删掉，不要再打包进 exe。

---

## 二、打包

本机已装 AutoIt3（`C:\Program Files (x86)\AutoIt3`），脚本已通过语法检查（Au3Check：0 错误 0 警告）并编译成功。

**最快的方式：双击 `build.bat`**，同目录会生成 `AutoRadmin.exe`（32 位，约 966 KB，已带 icon.ico）。

它实际执行的就是一行：

```
Aut2Exe.exe /in AutoRadmin.au3 /out AutoRadmin.exe /icon icon.ico /x86 /comp 4
```

其他方式：

- 装了 **SciTE4AutoIt3** 的话，右键 `AutoRadmin.au3` → Compile Script (x86)，或在 SciTE 里按 F7。
  好处是 `#AutoIt3Wrapper_*` 指令会生效，exe 的属性里能看到版本号、产品名；裸 `Aut2Exe` 会跳过这些指令（不影响功能）。
- 换机器编译时，把 `build.bat` 里的 `AUT2EXE` 路径改成那台机器的 AutoIt 安装路径。

打包清单：

1. `AutoRadmin.exe`
2. `config.ini`（放同一目录，程序按 exe 所在目录找配置；不放则首次运行自动生成）

`AutoRadmin.au3`、`icon.ico`、`build.bat` 不用跟着分发。

> 编码提醒：`AutoRadmin.au3` 存为 **UTF-8 with BOM**。用记事本/SciTE 重存时务必保持这个编码，否则界面里的中文会变乱码。

---

## 三、配置说明（config.ini）

```
RADMINDIR=C:\Program Files (x86)\Radmin Viewer 3
```

| 键 | 说明 |
|---|---|
| `RADMINDIR` | Radmin Viewer 目录 **或** `Radmin.exe` 完整路径；支持 `%ProgramFiles(x86)%` 这类环境变量；留空=自动探测 |
| `EXENAME` | 主程序文件名，默认 `Radmin.exe`，一般不用改 |
| `ARGS` | 传给 Radmin 的命令行参数，如 `/connect:1.2.3.4:4899 /through:5.6.7.8:4899 /fullstretch` |
| `CONNECTUSER` / `CONNECTPASS` | 目标服务器账号；**两项都留空**表示用 Radmin 已保存的凭据，脚本就不去碰登录框 |
| `THROUGHUSER` / `THROUGHPASS` | 中继服务器（`/through:`）的认证账号，不用中继可留空 |
| `WINDOWTITLE` | **一般不用填**。登录框是靠「进程 + 窗口类 + 输入框数量」识别的，不看标题。只有机器上有多个 Radmin 对话框需要区分时才填一段标题子串做额外过滤 |
| `WAITTIMEOUT` | 等登录窗口出现的超时秒数，默认 15 |
| `IFRUNNING` | Radmin 已开时的行为：`continue` 继续新建连接，`exit` 直接退出 |
| `DEBUG` | 设 `1` 会在同目录生成 `AutoRadmin.log`，记录每一步的判断结果，排查用 |

### 关于 RADMINDIR 的三种写法

```ini
RADMINDIR=C:\Program Files (x86)\Radmin Viewer 3          ; 目录
RADMINDIR=C:\Program Files (x86)\Radmin Viewer 3\Radmin.exe  ; 完整 exe 路径
RADMINDIR=%ProgramFiles(x86)%\Radmin Viewer 3             ; 环境变量
```
带引号也行（`"C:\..."`），程序会自动去掉首尾引号。相对路径按 exe 所在目录解析。

---

## 四、找 Radmin 的顺序

1. `RADMINDIR` 指定的位置（目录 → 拼 `EXENAME`；目录里没有就找 `Radmin*.exe`）
2. 自动探测常见目录：`Program Files`、`Program Files (x86)`、`ProgramW6432` 下的 `Radmin Viewer 3`
3. 注册表卸载项（`DisplayName` 含 `Radmin` 的 `InstallLocation` / `DisplayIcon`）+ `App Paths\Radmin.exe`
4. 仍找不到 → 弹出文件选择框，选完把完整路径写回 `config.ini` 的 `RADMINDIR`

所以就算配置写错，也不会卡死，按提示选一次就自动记住路径。

---

## 五、登录流程

1. 检查 `config.ini`，不存在就生成模板并用记事本打开
2. 解析出 `Radmin.exe` 的实际路径
3. 记录当前已存在的认证框句柄，然后启动 Radmin（工作目录设为 exe 所在目录）
4. 有 `/through:` 且配置了中继账号 → 等**新出现的**认证框，填中继账号密码，点确定
5. 有 `/connect:` 且配置了连接账号 → 等下一个新出现的认证框，填目标账号密码，点确定
6. 等不到认证框不报错，只弹一次托盘提示（视为已用保存的凭据自动登录）

### 怎么认出「那是 Radmin 的登录框」

不看标题（各语言版本标题里的空格数不一样，很容易匹配失败），改用三个硬条件：

| 条件 | 值 |
|---|---|
| 窗口属于哪个进程 | `Radmin.exe` |
| 窗口类名 | `#32770`（Win32 标准对话框） |
| 有几个输入框 | 至少 2 个（用户名 + 密码） |

本机实测能同时排除 `联机信息`、`收到的对象`、`HotKey Listener` 这些同样属于 `#32770` 的窗口。

几个稳定性细节：

- **按句柄差集认窗口**：只认启动后新出现的那个窗口，Radmin 已经开着也不会把密码填到旧窗口里
- **三级填充**：`ControlSend` → 读回不一致就换 `ControlSetText` → 再不行就激活窗口用真实键盘敲；每次写前都 `Ctrl+A` + `Del` 清空，重复尝试不会造成密码叠加
- **密码原样发送**：用 raw 模式，密码里有 `^ + % { }` 不会被当成功能键
- **按文本点「确定」**：不依赖按钮序号（这个对话框里「另存为缺省值」也是个 Button，按序号点很容易点到它或「取消」），遍历按钮找文本为 `确定` / `OK` / `ОК` 的那一个；找不到再退回发回车
- **密码框读不回是正常的**：Radmin 的密码框不响应读取，日志里会出现「内容读不回」，不影响实际填写

---

## 六、常见问题

**提示"未找到 Radmin Viewer 主程序"**
按提示选一次 `Radmin.exe` 即可，程序会把路径写回配置。也可以手动把 `RADMINDIR` 改成实际路径。

**卡在登录框没自动填**
把 `DEBUG` 设成 `1`，重新运行，看同目录的 `AutoRadmin.log`：

- 只有「已启动，等待认证框」→ 没识别到窗口，检查是不是 `Radmin.exe` 这个进程名（改过 `EXENAME` 的话对一下）
- 有「捕获认证框」但没有「填写成功」→ 看是哪一级失败，三级都失败说明对话框结构特殊，把日志发我
- 有「填写成功」但连接失败 → 账号密码问题，先确认能在 Radmin 里手动登录

**服务器用的是 Windows 认证，登录框标题是「Windows 安全性」**
默认不处理（避免误填到系统窗口）。确实需要时显式设 `WINDOWTITLE=Windows 安全性`，那个对话框的三个输入框依次是 用户名 / 密码 / 域，脚本只会填前两个。

**密码填上了但提示错误**
先确认 `CONNECTUSER` 里没有多余空格；Radmin 的账号框通常只填用户名，不需要 `域名\用户` 前缀。

**已经开着 Radmin，双击没反应**
检查 `IFRUNNING` 是否为 `exit`。

**要不要管理员权限**
一般不需要。两点例外：① 把 exe 放在 `Program Files` 这类受保护目录时，回写 `config.ini` 会失败（不影响连接本身）；② Radmin Viewer 本身是以管理员身份运行的，这时 AutoRadmin 也要用管理员身份启动，否则 Windows 的 UIPI 机制会拦住自动填表。
