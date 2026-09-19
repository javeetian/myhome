<#
  sdk/device -> 目标 Jieli SDK 一键部署 (framework 唯一源在本项目)

  用法 (PowerShell):
    .\deploy_to_sdk.ps1 -SdkRoot C:\work\jl\jl380n_demo\SDK
  或双击 / cmd:
    deploy_to_sdk.bat C:\work\jl\jl380n_demo\SDK
    deploy_to_sdk.bat C:\work\jl\<别的杰里IC>_demo\SDK      # 移植到新 IC 时

  做的事 (幂等, 可反复执行; 全部按本项目当前内容重建):
    1) 全量重建 <SDK>\apps\myhome\framework\  (core/ hardware/ platform/ + README)
       先删后拷 —— SDK 里不会残留本项目已删除/已改名的文件
    2) build\include_dir.txt : 重写本脚本管理的 -I 行 (framework + 每个设备的 generated/c)
    3) build\genFileList.c   : 重写标记块里的源文件列表 (framework 7 个 .c + 每个设备 3 个 .c)
    4) 自动发现设备: apps\myhome\<设备>\ 下有 device_app.c 的目录即视为一个设备

  改完本项目 framework 后必须重跑本脚本, 否则 SDK 里还是旧代码。

  每个 SDK 仍需手工一次 (脚本结尾会打印清单):
    - ble_rcsp_server.c: custom_fff0_write_handler / 断连事件 各接一行
#>
param(
    [Parameter(Mandatory = $true)][string]$SdkRoot
)

$ErrorActionPreference = 'Stop'

$Src       = $PSScriptRoot
$Dst       = Join-Path $SdkRoot 'apps\myhome\framework'
$MyHomeDir = Join-Path $SdkRoot 'apps\myhome'
$BuildDir  = Join-Path $SdkRoot 'build'

if (-not (Test-Path $BuildDir)) {
    Write-Error "不是有效的 SDK 目录 (缺 build\): $SdkRoot"
    exit 1
}

# ------------------------------------------------------------------ 工具函数

# 字节保真读写: Latin1 是 1 字节 <-> 1 字符的单字节编码, 用它做中间层
# 可以把文件原样读进来、改完原样写回去 (SDK 的 genFileList.c 里有中文注释,
# 不做解码/编码转换就不会破坏它)
$Latin1 = [Text.Encoding]::GetEncoding(28591)
function Read-Raw([string]$Path) { return $Latin1.GetString([IO.File]::ReadAllBytes($Path)) }
function Write-Raw([string]$Path, [string]$Text) {
    [IO.File]::WriteAllBytes($Path, $Latin1.GetBytes($Text))
}

# 删目录: 目标是 junction / symlink 时用 rd 只删链接本身, 绝不跟进删除目标内容
function Remove-DirSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        cmd /c rd "$Path" | Out-Null
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

# 追加时沿用文件最后一行的换行风格: SDK 的 build 文件行尾不统一, 不能假设整文件一致
function Get-Newline([string]$Text) {
    $m = [regex]::Match($Text, '(\r?\n)\z')
    if ($m.Success) { return $m.Groups[1].Value }
    if ($Text -match "`r`n") { return "`r`n" }
    return "`n"
}

# ------------------------------------------------ 1/4 同步 framework 源码
Write-Host "[1/4] 全量重建 framework -> $Dst"
Remove-DirSafe $Dst
New-Item -ItemType Directory -Force -Path $Dst | Out-Null
$fileCount = 0
foreach ($sub in @('core', 'hardware', 'platform')) {
    $from = Join-Path $Src $sub
    if (Test-Path -LiteralPath $from) {
        Copy-Item -Path $from -Destination $Dst -Recurse -Force
        $fileCount += (Get-ChildItem -Path $from -Recurse -File).Count
    }
}
Copy-Item -Path (Join-Path $Src 'README.md') -Destination $Dst -Force
Write-Host "      ok ($fileCount 个源文件)"

# ------------------------------------------------------------ 发现设备目录
$devices = @()
if (Test-Path -LiteralPath $MyHomeDir) {
    $devices = @(Get-ChildItem -Path $MyHomeDir -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'device_app.c') } |
        Sort-Object Name)
}
Write-Host "      设备: $(if ($devices.Count) { ($devices.Name -join ', ') } else { '(无)' })"

# ------------------------------------------------ 2/4 include_dir.txt
Write-Host "[2/4] 重写 include_dir.txt 的 myhome 行"
$includeFile = Join-Path $BuildDir 'include_dir.txt'
$text = Read-Raw $includeFile
$nl   = Get-Newline $text

# 只按行删掉本脚本管理过的旧行 (路径过期时自动纠正); 其余字节一律原样保留。
# 不做"拆行再拼回" —— 那会把整文件行尾统一改写, 产生几百行的假 diff
$text = [regex]::Replace($text, '(?m)^-Iapps/myhome/framework[^\r\n]*\r?\n', '')
$text = [regex]::Replace($text, '(?m)^-Iapps/myhome/[^/\r\n]+/generated/c[ \t]*\r?\n', '')
# 保留文件原有的结尾换行结构 (可能带空行)
$tail = [regex]::Match($text, '[\r\n]+\z').Value
$body = [regex]::Replace($text, '[\r\n]+\z', '')

$managed = New-Object System.Collections.Generic.List[string]
foreach ($inc in @(
    '-Iapps/myhome/framework',
    '-Iapps/myhome/framework/core/runtime',
    '-Iapps/myhome/framework/core/codec',
    '-Iapps/myhome/framework/hardware',
    '-Iapps/myhome/framework/platform/jieli'
)) { $managed.Add($inc) }
foreach ($dev in $devices) { $managed.Add("-Iapps/myhome/$($dev.Name)/generated/c") }

Write-Raw $includeFile ($body + $tail + ($managed -join $nl) + $nl)
foreach ($inc in $managed) { Write-Host "      $inc" }

# ------------------------------------------------ 3/4 genFileList.c
Write-Host "[3/4] 重写 genFileList.c 的 myhome 源文件列表"
$listFile = Join-Path $BuildDir 'genFileList.c'
$text = Read-Raw $listFile

# 1) 删掉本脚本上次写的标记块
$text = [regex]::Replace($text, '(?s)/\* myhome-framework:begin.*?/\* myhome-framework:end \*/\r?\n?', '')
$text = [regex]::Replace($text, '(?s)/\* myhome-devices:begin.*?/\* myhome-devices:end \*/\r?\n?', '')
# 2) 删掉标记块之前手工加的遗留行 (例如重构前 frame 根下的 myhome_glue.c)
$text = [regex]::Replace($text, '(?m)^c_SRC_FILES \+= [^\r\n]*apps/myhome/framework/[^\r\n]*\r?\n?', '')
$text = [regex]::Replace($text, '(?m)^c_SRC_FILES \+= [^\r\n]*apps/myhome/[^/\r\n]+/device_app\.c[^\r\n]*\r?\n?', '')

$nl = Get-Newline $text
if ($text -notmatch "\r?\n$") { $text += $nl }

# framework 固定 7 个 .c
$frameworkSrc = @(
    'apps/myhome/framework/core/protocol/crc16.c',
    'apps/myhome/framework/core/protocol/ble_frame.c',
    'apps/myhome/framework/core/codec/device_json.c',
    'apps/myhome/framework/core/runtime/ble_stream_decoder.c',
    'apps/myhome/framework/core/runtime/fragment.c',
    'apps/myhome/framework/core/runtime/device_runtime.c',
    'apps/myhome/framework/platform/jieli/myhome_glue.c'
)

$block  = "/* myhome-framework:begin  (generated by sdk/device/deploy_to_sdk.ps1; do not edit) */$nl"
$block += 'c_SRC_FILES += ' + ($frameworkSrc -join ' ') + "$nl"
$block += "/* myhome-framework:end */$nl"

# 每个设备: device_app.c + generated/c/*.c
foreach ($dev in $devices) {
    $srcList = New-Object System.Collections.Generic.List[string]
    $srcList.Add("apps/myhome/$($dev.Name)/device_app.c")
    $genDir = Join-Path $dev.FullName 'generated\c'
    if (Test-Path -LiteralPath $genDir) {
        foreach ($f in (Get-ChildItem -Path $genDir -Filter '*.c' -File | Sort-Object Name)) {
            $srcList.Add("apps/myhome/$($dev.Name)/generated/c/$($f.Name)")
        }
    }
    $block += "/* myhome-devices:begin  ($($dev.Name)) */$nl"
    $block += 'c_SRC_FILES += ' + ($srcList -join ' ') + "$nl"
    $block += "/* myhome-devices:end */$nl"
    Write-Host "      $($dev.Name): $($srcList.Count) 个 .c"
}

Write-Raw $listFile ($text + $block)

# ------------------------------------------------ 4/4 手工清单
Write-Host "[4/4] 完成。目标 SDK: $SdkRoot"
Write-Host ""
Write-Host "每个 SDK 仍需手工一次:"
Write-Host "  1) apps/common/third_party_profile/jieli/rcsp/ble_rcsp_server.c:"
Write-Host "       custom_fff0_write_handler      -> myhome_ble_on_write(buffer, buffer_size)"
Write-Host "       HCI_EVENT_DISCONNECTION_COMPLETE -> myhome_on_disconnect()"
Write-Host "  2) 设备目录内容 (device.yaml / ui / generated / device_app.c)"
Write-Host "       由本项目工具生成后的改动, 也要重跑本脚本才能进 SDK 构建"
Write-Host "  3) apps/myhome/deploy_ui.bat 部署 ui.pkg + manifest.json"
Write-Host ""
Write-Host "改完本项目 framework 后, 重跑本脚本再到 SDK 里 make。"
