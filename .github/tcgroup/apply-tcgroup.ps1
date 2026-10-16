#requires -Version 5.1
<#
    TCGROUP 定制客户端 —— 源码定制脚本
    在 CI（或本机）构建前执行：pwsh -File ./tcgroup/apply-tcgroup.ps1

    设计原则：每一项改动都要求"精确命中且仅命中一次"，否则立即抛错终止。
    绝不静默跳过 —— 万一上游改了代码导致匹配不上，构建会红，不会出一个"没改成功"的包。
#>
$ErrorActionPreference = 'Stop'

# 本脚本位于 .github/tcgroup/ 下，向上找到仓库根（以 build.py 为标志），
# 这样无论放在哪一层都能正确工作。
$RepoRoot = $PSScriptRoot
while ($RepoRoot -and -not (Test-Path (Join-Path $RepoRoot 'build.py'))) {
    $parent = Split-Path $RepoRoot -Parent
    if ($parent -eq $RepoRoot) { break }
    $RepoRoot = $parent
}
if (-not (Test-Path (Join-Path $RepoRoot 'build.py'))) {
    throw "找不到仓库根（未在祖先目录中发现 build.py）。脚本位置: $PSScriptRoot"
}
Write-Host "仓库根目录: $RepoRoot" -ForegroundColor Cyan

$script:Changed = 0

function Set-Once {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not (Test-Path $Path)) { throw "[$Label] 文件不存在: $Path" }
    $text = [System.IO.File]::ReadAllText($Path)
    $n = ([regex]::Matches($text, [regex]::Escape($From))).Count
    if ($n -eq 0) { throw "[$Label] 未匹配到目标文本（上游可能已改动）: $Path`n  期望片段: $From" }
    if ($n -gt 1) { throw "[$Label] 匹配到 $n 处（应为 1 处），拒绝盲改: $Path" }
    $text = $text.Replace($From, $To)
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
    $script:Changed++
    Write-Host "  [OK] $Label" -ForegroundColor Green
}

function Copy-Asset {
    param([string]$From, [string]$To, [string]$Label)
    if (-not (Test-Path $From)) { throw "[$Label] 源文件不存在: $From" }
    $dir = Split-Path $To -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $From $To -Force
    $script:Changed++
    Write-Host "  [OK] $Label  ->  $($To.Replace($RepoRoot,'.'))" -ForegroundColor Green
}

Write-Host "`n===== 1/4 服务器指向 =====" -ForegroundColor Cyan
$cfg = Join-Path $RepoRoot 'libs/hbb_common/src/config.rs'
Set-Once -Path $cfg -Label 'APP_NAME -> TCGROUP' `
    -From 'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());' `
    -To   'pub static ref APP_NAME: RwLock<String> = RwLock::new("TCGROUP".to_owned());'
Set-Once -Path $cfg -Label 'RENDEZVOUS_SERVERS -> 8.129.216.1' `
    -From 'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];' `
    -To   'pub const RENDEZVOUS_SERVERS: &[&str] = &["8.129.216.1"];'
Set-Once -Path $cfg -Label 'RS_PUB_KEY -> 我们服务器的公钥' `
    -From 'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";' `
    -To   'pub const RS_PUB_KEY: &str = "LSxLzSQMlctLSH2Hrpe5brFzV0gtfrIZAtxSdwHS8Lw=";'

Write-Host "`n===== 2/4 exe 属性（Runner.rc）=====" -ForegroundColor Cyan
$rc = Join-Path $RepoRoot 'flutter/windows/runner/Runner.rc'
Set-Once -Path $rc -Label 'CompanyName'   -From 'VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\0"'                                     -To 'VALUE "CompanyName", "TCGROUP" "\0"'
Set-Once -Path $rc -Label 'FileDescription' -From 'VALUE "FileDescription", "RustDesk Remote Desktop" "\0"'                                -To 'VALUE "FileDescription", "TCGROUP Remote Desktop" "\0"'
Set-Once -Path $rc -Label 'InternalName'  -From 'VALUE "InternalName", "rustdesk" "\0"'                                                   -To 'VALUE "InternalName", "tcgroup" "\0"'
Set-Once -Path $rc -Label 'LegalCopyright' -From 'VALUE "LegalCopyright", "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved." "\0"' -To 'VALUE "LegalCopyright", "Copyright © 2026 TCGROUP. All rights reserved." "\0"'
Set-Once -Path $rc -Label 'OriginalFilename' -From 'VALUE "OriginalFilename", "rustdesk.exe" "\0"'                                        -To 'VALUE "OriginalFilename", "tcgroup.exe" "\0"'
Set-Once -Path $rc -Label 'ProductName'   -From 'VALUE "ProductName", "RustDesk" "\0"'                                                    -To 'VALUE "ProductName", "TCGROUP" "\0"'

Write-Host "`n===== 3/4 资源文件（logo / 图标）=====" -ForegroundColor Cyan
$A = Join-Path $PSScriptRoot 'assets'
Copy-Asset -From (Join-Path $A 'logo.png')      -To (Join-Path $RepoRoot 'flutter/assets/logo.png')                      -Label '应用内 logo（亮色主题）'
Copy-Asset -From (Join-Path $A 'logo_dark.png') -To (Join-Path $RepoRoot 'flutter/assets/logo_dark.png')                 -Label '应用内 logo（暗色主题）'
Copy-Asset -From (Join-Path $A 'icon.png')      -To (Join-Path $RepoRoot 'flutter/assets/icon.png')                      -Label '应用内方形图标'
Copy-Asset -From (Join-Path $A 'app_icon.ico')  -To (Join-Path $RepoRoot 'flutter/windows/runner/resources/app_icon.ico') -Label '窗口/主 exe 图标'
Copy-Asset -From (Join-Path $A 'app_icon.ico')  -To (Join-Path $RepoRoot 'res/icon.ico')                                 -Label '安装包图标'
Copy-Asset -From (Join-Path $A 'app_icon.ico')  -To (Join-Path $RepoRoot 'res/tray-icon.ico')                            -Label '托盘图标'

Write-Host "`n===== 4/4 预置无人值守密码 =====" -ForegroundColor Cyan
$cm = Join-Path $RepoRoot 'src/core_main.rs'
$anchor = 'crate::load_custom_client();'
$cmText = [System.IO.File]::ReadAllText($cm)
if ($cmText.Contains('TCG_PRESET_PASSWORD')) {
    Write-Host "  [SKIP] 已插入过，跳过" -ForegroundColor Yellow
} else {
    $block = @'
crate::load_custom_client();
    // ===== TCGROUP 预置无人值守密码（仅在没有密码时写入一次） =====
    {
        const TCG_PRESET_PASSWORD: &str = "TCG-Rm@2026#Xk9pQm4Vz8Lw6Nb";
        if !hbb_common::config::Config::has_permanent_password() {
            let _ = hbb_common::config::Config::set_permanent_password(TCG_PRESET_PASSWORD);
            log::info!("TCGROUP: preset permanent password applied");
        }
    }
    // ===== end TCGROUP =====
'@
    Set-Once -Path $cm -Label '插入预置密码块' -From $anchor -To $block
}

Write-Host "`n完成：共 $script:Changed 项改动。" -ForegroundColor Cyan
Write-Host "下一步：python3 build.py --portable --flutter --skip-portable-pack --hwcodec" -ForegroundColor Cyan
