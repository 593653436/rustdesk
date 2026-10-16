# TCGROUP 定制客户端 —— fork 操作说明

目标：在你的 GitHub fork 上用 Actions 编出 **TCGROUP Remote Desktop**（服务器已内置 `8.129.216.1`），产物是官方那种 25 MB 自解压便携 exe。

---

## 一、目录里有什么

```
fork-kit/
├─ .github/workflows/build-tcgroup-client.yml   ← 放进去，Actions 里就能手动跑
└─ tcgroup/
   ├─ apply-tcgroup.ps1                          ← 定制脚本（CI 会调用）
   └─ assets/
      ├─ logo.png              应用内 logo（亮色主题，561×120 透明底）
      ├─ logo_dark.png         应用内 logo（暗色主题）
      ├─ icon.png              方形图标 256×256
      └─ app_icon.ico          多尺寸图标（16→256，只留圆形标志）
```

---

## 二、操作步骤（约 10 分钟 + 一次 CI 等待）

### 1. fork

浏览器打开 `https://github.com/rustdesk/rustdesk` → Fork 到你账号（593653436）。
**fork 时不需要勾选任何特殊选项**，但要确认 fork 出来的仓库里 `libs/hbb_common` 子模块是好的（GitHub fork 会保留 submodule 引用，CI 里用 `submodules: recursive` 拉全）。

### 2. 放进两个东西

把本目录里的：

- `.github/workflows/build-tcgroup-client.yml`
- `tcgroup/`（整个目录）

按原样提交到 fork 的 `master` 分支根目录。

> 用网页上传也可以（Add file → Upload files），只要保持 `tcgroup/` 这层目录结构。
> 用 git 的话：
> ```bash
> git clone --recursive https://github.com/<你的账号>/rustdesk.git
> cd rustdesk
> # 把 fork-kit 里的 .github / tcgroup 拷进来
> git add .github/workflows/build-tcgroup-client.yml tcgroup
> git commit -m "TCGROUP custom client"
> git push
> ```

### 3. 开启 Actions

fork 后第一次要手动点一下：仓库 → **Actions** 标签页 → 若提示 "Workflows aren't being run on this forked repository" → 点 **I understand my workflows, go ahead and enable them**。

### 4. 跑一次

Actions → 左侧 **Build TCGROUP Client (Windows x64)** → **Run workflow** → 分支选 `master` → Run。

- `upload-tag` 保持 `tcgroup`
- `upload-artifact` 保持 `true`

### 5. 取产物

跑完（预计 **30–60 分钟**，首次 vcpkg 依赖编译最慢）在该次运行页面底部 **Artifacts** 下载：

| 产物名 | 内容 |
|---|---|
| `rustdesk-unsigned-<arch>` | **主产物** —— 自解压便携 exe（就是你要发给客户的那个） |
| `rustdesk-unsigned-msi-template-<arch>` | MSI 模板（可选，需管理员安装时用） |

> ⚠️ 产物是 **未签名** 的。客户双击会看到 Windows SmartScreen「已保护你的电脑」，需要点「更多信息 → 仍要运行」。这是自编译无法避免的（RustDesk 官方证书只在官方构建里）。

---

## 三、这个 workflow 做了什么

取自官方 `flutter-build.yml`，**只保留 Windows 构建必需的 3 个 job**（逐行照搬，未改写逻辑）：

| job | 作用 |
|---|---|
| `generate-bridge` | 调 `./.github/workflows/bridge.yml`，产出 `bridge-artifact`（主构建依赖它） |
| `build-RustDeskTempTopMostWindow` | 调 `./.github/workflows/third-party-RustDeskTempTopMostWindow.yml`，产出窗口注入件 |
| `build-for-windows-flutter` | 主构建（**只保留 x86_64 / windows-2022**，剔掉了 arm64 条目省一半时间） |

### 相对官方的三处改动

1. **触发方式**：`workflow_call` → `workflow_dispatch`（手动触发），并补上 `upload-tag` / `upload-artifact` 两个输入
2. **新增一步**：在 `build-for-windows-flutter` 的 `steps` 最前面插入
   ```yaml
   - name: Apply TCGROUP customization
     shell: pwsh
     run: |
       pwsh -File ./tcgroup/apply-tcgroup.ps1
   ```
3. **`Publish Release` 步骤 `if` 改成 `false`**
   > 官方那步在 `UPLOAD_ARTIFACT=='true'` 时就会真去建 Release；fork 的默认 `GITHUB_TOKEN` 没有 `contents: write`，会**让整个 job 在编完之后失败**。必须禁掉。
   > 也因此 **不需要给 fork 配任何 secret**。

### 关于签名：无需配置，自动跳过

```yaml
SIGN_BASE_URL: "${{ secrets.SIGN_BASE_URL }}-2"        # 你没有该 secret → 字面量 "-2"
...
- name: Sign rustdesk files
  if: ... && env.SIGN_BASE_URL != '-2'                 # → 恒假，跳过
```

`Sign rustdesk files` / `Sign rustdesk self-extracted file` 两处都会自动跳过，未签名产物走 `Upload unsigned` 步骤上传。

---

## 四、定制脚本改了什么

`tcgroup/apply-tcgroup.ps1` 只做 4 组改动，**每一项都要求"精确命中且仅命中一次"，匹配不上就抛错让构建变红**（不会静默产出一个没改成功的包）：

### 1. 服务器指向 —— `libs/hbb_common/src/config.rs`

| 原值 | 新值 |
|---|---|
| `APP_NAME = RwLock::new("RustDesk")` | `"TCGROUP"` |
| `RENDEZVOUS_SERVERS = &["rs-ny.rustdesk.com"]` | `&["8.129.216.1"]` |
| `RS_PUB_KEY = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="` | `"LSxLzSQMlctLSH2Hrpe5brFzV0gtfrIZAtxSdwHS8Lw="` |

> `RS_PUB_KEY` 必须是合法 base64 32 字节 ed25519 公钥（客户端会 `get_rs_pk()` 解析），上表这个值就是 `hbbs` 生成的公钥，**同时也是备份里的 `id_ed25519.pub`**。**两者必须一致，改服务器密钥时要同步改这里并重新编译。**

### 2. exe 属性 —— `flutter/windows/runner/Runner.rc`

`CompanyName` / `FileDescription` / `InternalName` / `LegalCopyright` / `OriginalFilename` / `ProductName` 六项全部改成 TCGROUP。

### 3. 资源文件

| 目标 | 来源 |
|---|---|
| `flutter/assets/logo.png` | `tcgroup/assets/logo.png` |
| `flutter/assets/logo_dark.png` | `tcgroup/assets/logo_dark.png` |
| `flutter/assets/icon.png` | `tcgroup/assets/icon.png` |
| `flutter/windows/runner/resources/app_icon.ico` | `tcgroup/assets/app_icon.ico` |
| `res/icon.ico` | 同上 |
| `res/tray-icon.ico` | 同上 |

> 应用内 logo **不需要改任何 Dart 代码** —— `common.dart` 是运行时探测 `assets/logo.png`，文件不存在就跳过；`pubspec.yaml` 声明的是整个 `assets/` 目录。

### 4. 预置无人值守密码 —— `src/core_main.rs`

在 `crate::load_custom_client();` 之后插入：

```rust
{
    const TCG_PRESET_PASSWORD: &str = "TCG-Rm@2026#Xk9pQm4Vz8Lw6Nb";
    if !hbb_common::config::Config::has_permanent_password() {
        let _ = hbb_common::config::Config::set_permanent_password(TCG_PRESET_PASSWORD);
        log::info!("TCGROUP: preset permanent password applied");
    }
}
```

`has_permanent_password()` / `set_permanent_password()` 都是 `hbb_common::config::Config` 的公开方法（`hbb_common/src/config.rs:1391` / `:1290`），已确认可见性。

**效果**：客户端首次运行即写入固定密码，客户不用念 ID，你随时无人值守连进去。只在没有密码时写一次，不会每次启动覆盖。

> 要改密码：改脚本里那个常量 → 重新跑 CI。
> **发给客户的包和你要连的密码是同一个**，所以别把密码泄露给客户以外的人。

---

## 五、已知不确定项（我没法在这里验证的部分）

我把能查的都查了（源码逐行 + 本机实测），但以下几项**只有在 CI 真跑一次才知道**：

| 项 | 风险 | 万一失败怎么办 |
|---|---|---|
| 三个 job 的依赖衔接（bridge artifact / topmost artifact 名称） | 低 —— 逐行照搬官方，未改写 | 报错信息会指明缺哪个 artifact |
| `apply-tcgroup.ps1` 的文本匹配 | **已本地空跑验证通过** —— 16 项改动全部命中，旧值全部消失 | 报错会打印期望片段，贴给我即可 |
| `--portable` 产出的自解压 exe 形态 | 低 —— 与官方发布页同一命令 | 退一步可只取 `./rustdesk/` 目录自己打包 |
| 预置密码是否真的生效 | **中** —— API 可见性已确认（`hbb_common/src/config.rs:1290/1391`），但运行时行为未实测 | 编出来后跑一次，看 `RustDesk.toml` 的 `password` 字段是否非空；空就贴日志给我 |

### 预置密码有一个我还没验证的点：服务侧

在你这台机器上实测时我看到 **RustDesk 的 Windows 服务有自己的配置**（`C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml`，需要管理员才能读）。

而上面那个补丁插在 `core_main()` 里 —— 那是**用户侧进程**启动时执行的。所以：

- **有用户登录时**：用户侧进程起来就写密码，无人值守连接由该进程响应 → **应该没问题**
- **无用户登录时**（锁屏 / 没人登着）：连接由 **LocalSystem 服务**响应，服务读的是它自己的配置 → **我们的补丁可能覆盖不到**

**如果"客户机锁屏也能连"是硬需求**，需要额外处理服务侧配置（或改用"安装版 + `--silent-install --password <密码>`"，那条路径是官方支持的、明确写服务侧配置）。

第一次编出来后**请在锁屏状态下试连一次**，这条必须实测，我不替它打包票。

**跑第一次时把失败日志贴给我，我改。** 我这边无法访问你的 GitHub，所以这一步必须你点。

---

## 六、编出来之后怎么验收（三步）

1. **确认服务器内置**：在一台干净机器跑，看它是否注册到 `8.129.216.1`
   （我这边一条命令判定：`sqlite3 /opt/rustdesk/db_v2.sqlite3 "select id,created_at from peer"`）
2. **确认品牌**：exe 属性里 CompanyName/ProductName = TCGROUP，任务栏/托盘图标是 TCGROUP，主界面左上角是你给的 logo
3. **确认预置密码**：跑起来后在客户端设置里看是否已有固定密码（或直接用该密码无人值守连接）

---

## 七、升级上游怎么办

官方发新版后：

```bash
git remote add upstream https://github.com/rustdesk/rustdesk.git
git fetch upstream --tags
git rebase upstream/<新版本tag>
git push --force-with-lease
```

`apply-tcgroup.ps1` 的改动只有 4 组、都是精确字符串替换，冲突概率低；万一上游改了那几行原文，脚本会直接抛错告诉你哪一项没匹配上，不会默默编出一个半成品。
