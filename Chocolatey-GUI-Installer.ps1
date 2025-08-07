<#
.SYNOPSIS
Chocolatey GUI 安裝器
.DESCRIPTION
提供圖形化界面來安裝 Chocolatey 和管理軟體套件
.AUTHOR
Generated based on 1. 一鍵安裝.bat
#>

param(
    [switch]$Elevated
)

# 檢查是否以管理員身份執行
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 如果沒有管理員權限則提升權限
if (-not (Test-Administrator)) {
    if (-not $Elevated) {
        Write-Host "正在請求管理員權限..." -ForegroundColor Yellow
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Elevated"
        Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
        exit
    } else {
        Write-Host "無法取得管理員權限，程式結束" -ForegroundColor Red
        Read-Host "按 Enter 鍵結束"
        exit
    }
}

# 設定執行策略以允許載入腳本
try {
    Write-Host "設定 PowerShell 執行策略..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Host "執行策略已設定為 Bypass (限於當前處理序)" -ForegroundColor Green
}
catch {
    Write-Host "警告：無法設定執行策略 - $($_.Exception.Message)" -ForegroundColor Yellow
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 載入管理器類別
try {
    # 取得執行檔所在目錄 (相容於 ps2exe 編譯版本)
    $scriptDir = if ($PSScriptRoot) { 
        $PSScriptRoot 
    } elseif ($MyInvocation.MyCommand.Path) { 
        Split-Path $MyInvocation.MyCommand.Path -Parent
    } else { 
        Get-Location | Select-Object -ExpandProperty Path
    }
    
    $managerPath = Join-Path $scriptDir "ChocolateyManager.ps1"
    Write-Host "嘗試載入: $managerPath" -ForegroundColor Gray
    
    if (Test-Path $managerPath) {
        . $managerPath
        Write-Host "✅ ChocolateyManager 載入成功" -ForegroundColor Green
    } else {
        throw "找不到 ChocolateyManager.ps1 檔案: $managerPath"
    }
}
catch {
    Write-Host "錯誤：無法載入 ChocolateyManager - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "請確認 ChocolateyManager.ps1 檔案存在於相同目錄中" -ForegroundColor Red
    Read-Host "按 Enter 鍵結束"
    exit
}

# 全域變數
$script:Manager = $null
$script:MainForm = $null
$script:InstallChocoButton = $null
$script:InstallButton = $null
$script:UninstallButton = $null
$script:RefreshStatusButton = $null
$script:StatusLabel = $null
$script:LogTextBox = $null
$script:TabControl = $null

# 異步操作變數
$script:AsyncPackages = @()
$script:AsyncOperation = ""
$script:AsyncOnComplete = $null
$script:AsyncCurrentIndex = 0
$script:AsyncSuccessCount = 0
$script:AsyncErrorCount = 0
$script:AsyncCompletedCount = 0

# 匯出/匯入相關變數
$script:ExportButton = $null
$script:ImportButton = $null

# 異步套件操作函數 (修復版本 - 確保正確等待和計數)
function Start-AsyncPackageOperation {
    param(
        [array]$Packages,
        [string]$Operation,  # "install" 或 "uninstall"
        [scriptblock]$OnComplete
    )
    
    # 將資料儲存在腳本範圍變數中
    $script:AsyncPackages = $Packages
    $script:AsyncOperation = $Operation
    $script:AsyncOnComplete = $OnComplete
    $script:AsyncCurrentIndex = 0
    $script:AsyncSuccessCount = 0
    $script:AsyncErrorCount = 0
    $script:AsyncCompletedCount = 0  # 新增：追蹤已完成的套件數量
    
    # 開始處理第一個套件
    Process-NextPackage
}

# 處理下一個套件
function Process-NextPackage {
    if ($script:AsyncCurrentIndex -ge $script:AsyncPackages.Count) {
        # 所有套件都已開始處理，等待全部完成
        return
    }
    
    $package = $script:AsyncPackages[$script:AsyncCurrentIndex]
    $script:AsyncCurrentIndex++
    
    try {
        # 更新UI顯示
        $action = if ($script:AsyncOperation -eq "install") { "安裝" } else { "移除" }
        $script:LogTextBox.AppendText("正在${action}：$($package.DisplayName)...$($script:AsyncCurrentIndex)/$($script:AsyncPackages.Count)`r`n")
        $script:LogTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        
        # 建構命令參數
        if ($script:AsyncOperation -eq "install") {
            $chocoArgs = "install $($package.Name) -y"
            if ($package.Extra) {
                $chocoArgs += " $($package.Extra)"
            }
        } else {
            $chocoArgs = "uninstall $($package.Name) -x -y"
        }
        
        # 執行命令 (同步方式，但允許UI更新)
        $result = Invoke-ChocoCommandWithUI -Arguments $chocoArgs
        
        # 處理結果
        if ($result.Success) {
            $script:LogTextBox.AppendText("✓ $($package.DisplayName) ${action}成功`r`n")
            $script:AsyncSuccessCount++
            
            # 更新套件狀態
            if ($script:AsyncOperation -eq "uninstall") {
                $package.IsInstalled = $false
                $package.InstalledVersion = $null
                $package.Selected = $false
            }
        } else {
            $script:LogTextBox.AppendText("✗ $($package.DisplayName) ${action}失敗 (退出代碼: $($result.ExitCode))`r`n")
            $script:AsyncErrorCount++
        }
        
        $script:AsyncCompletedCount++
        $script:LogTextBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        
        # 檢查是否全部完成
        if ($script:AsyncCompletedCount -ge $script:AsyncPackages.Count) {
            # 所有套件都處理完成
            $script:AsyncOnComplete.Invoke($script:AsyncSuccessCount, $script:AsyncErrorCount)
        } else {
            # 處理下一個套件
            Process-NextPackage
        }
        
    } catch {
        $script:LogTextBox.AppendText("✗ $($package.DisplayName) 處理時發生錯誤：$($_.Exception.Message)`r`n")
        $script:LogTextBox.ScrollToCaret()
        $script:AsyncErrorCount++
        $script:AsyncCompletedCount++
        
        # 檢查是否全部完成
        if ($script:AsyncCompletedCount -ge $script:AsyncPackages.Count) {
            $script:AsyncOnComplete.Invoke($script:AsyncSuccessCount, $script:AsyncErrorCount)
        } else {
            Process-NextPackage
        }
    }
}

# 執行 Chocolatey 命令但允許UI更新
function Invoke-ChocoCommandWithUI {
    param([string]$arguments)
    
    $result = @{
        Success = $false
        ExitCode = -1
        Output = ""
        Error = ""
    }
    
    try {
        # 使用 ProcessStartInfo 來捕獲輸出
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "choco"
        $processInfo.Arguments = $arguments  
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start()
        
        # 使用非阻塞方式讀取輸出，同時允許UI更新
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder
        
        while (-not $process.HasExited) {
            # 讀取標準輸出
            if (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                if ($line) {
                    $script:LogTextBox.AppendText("  $line`r`n")
                    $script:LogTextBox.ScrollToCaret()
                    [void]$outputBuilder.AppendLine($line)
                }
            }
            
            # 讀取錯誤輸出
            if (-not $process.StandardError.EndOfStream) {
                $errorLine = $process.StandardError.ReadLine()
                if ($errorLine) {
                    $script:LogTextBox.AppendText("  [錯誤] $errorLine`r`n")
                    $script:LogTextBox.ScrollToCaret()
                    [void]$errorBuilder.AppendLine($errorLine)
                }
            }
            
            # 允許UI更新
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        
        # 讀取剩餘的輸出
        $remainingOutput = $process.StandardOutput.ReadToEnd()
        if ($remainingOutput.Trim()) {
            $script:LogTextBox.AppendText("  $remainingOutput")
            $script:LogTextBox.ScrollToCaret()
            [void]$outputBuilder.Append($remainingOutput)
        }
        
        $remainingError = $process.StandardError.ReadToEnd()  
        if ($remainingError.Trim()) {
            $script:LogTextBox.AppendText("  [錯誤] $remainingError")
            $script:LogTextBox.ScrollToCaret()
            [void]$errorBuilder.Append($remainingError)
        }
        
        # 等待Process完全結束
        $process.WaitForExit()
        
        $result.ExitCode = $process.ExitCode
        $result.Success = $process.ExitCode -eq 0
        $result.Output = $outputBuilder.ToString()
        $result.Error = $errorBuilder.ToString()
        
        $process.Close()
    }
    catch {
        $result.Error = $_.Exception.Message
        $script:LogTextBox.AppendText("  [異常] $($_.Exception.Message)`r`n")
    }
    
    return $result
}

# 執行 Chocolatey 命令 (保留同步版本供其他功能使用)
function Invoke-ChocoCommand {
    param([string]$arguments)
    
    $result = @{
        Success = $false
        ExitCode = -1
        Output = ""
        Error = ""
    }
    
    try {
        # 使用 ProcessStartInfo 來捕獲輸出
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "choco"
        $processInfo.Arguments = $arguments
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start()
        
        # 使用同步方式讀取輸出
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder
        
        while (-not $process.HasExited) {
            # 讀取標準輸出
            if (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                if ($line) {
                    $script:LogTextBox.AppendText("  $line`r`n")
                    $script:LogTextBox.ScrollToCaret()
                    [void]$outputBuilder.AppendLine($line)
                }
            }
            
            # 讀取錯誤輸出
            if (-not $process.StandardError.EndOfStream) {
                $errorLine = $process.StandardError.ReadLine()
                if ($errorLine) {
                    $script:LogTextBox.AppendText("  [錯誤] $errorLine`r`n")
                    $script:LogTextBox.ScrollToCaret()
                    [void]$errorBuilder.AppendLine($errorLine)
                }
            }
            
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        
        # 讀取剩餘的輸出
        $remainingOutput = $process.StandardOutput.ReadToEnd()
        if ($remainingOutput.Trim()) {
            $script:LogTextBox.AppendText("  $remainingOutput")
            $script:LogTextBox.ScrollToCaret()
            [void]$outputBuilder.Append($remainingOutput)
        }
        
        $remainingError = $process.StandardError.ReadToEnd()
        if ($remainingError.Trim()) {
            $script:LogTextBox.AppendText("  [錯誤] $remainingError")
            $script:LogTextBox.ScrollToCaret()
            [void]$errorBuilder.Append($remainingError)
        }
        
        $result.ExitCode = $process.ExitCode
        $result.Success = $process.ExitCode -eq 0
        $result.Output = $outputBuilder.ToString()
        $result.Error = $errorBuilder.ToString()
        
        $process.Close()
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    
    return $result
}

# 安裝 Chocolatey
function Install-Chocolatey {
    try {
        $script:LogTextBox.AppendText("開始安裝 Chocolatey...`r`n")
        $script:LogTextBox.Refresh()
        
        # 先檢查是否已經安裝
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $script:LogTextBox.AppendText("Chocolatey 已經安裝！`r`n")
            $script:Manager.IsInstalled = $true
            $script:InstallChocoButton.Text = "✓ Chocolatey 已安裝"
            $script:InstallChocoButton.Enabled = $false
            $script:StatusLabel.Text = "狀態：Chocolatey 已安裝，可以開始選擇套件"
            return $true
        }
        
        # 禁用按鈕防止重複點擊
        $script:InstallChocoButton.Enabled = $false
        $script:InstallChocoButton.Text = "正在安裝..."
        
        # 設定執行策略和安全協定
        $script:LogTextBox.AppendText("配置安全性設定...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        try {
            # 設定執行策略
            Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
            $script:LogTextBox.AppendText("✓ 執行策略已設定`r`n")
        }
        catch {
            $script:LogTextBox.AppendText("警告：無法設定執行策略 - $($_.Exception.Message)`r`n")
        }
        
        try {
            # 設定 TLS 安全協定
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            $script:LogTextBox.AppendText("✓ TLS 安全協定已設定`r`n")
        }
        catch {
            $script:LogTextBox.AppendText("警告：無法設定 TLS 協定 - $($_.Exception.Message)`r`n")
        }
        
        [System.Windows.Forms.Application]::DoEvents()
        
        # 方法 1：使用 WebClient 下載安裝腳本
        $script:LogTextBox.AppendText("正在下載 Chocolatey 安裝腳本...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "PowerShell")
            $installScript = $webClient.DownloadString('https://community.chocolatey.org/install.ps1')
            $script:LogTextBox.AppendText("✓ 安裝腳本下載成功`r`n")
            [System.Windows.Forms.Application]::DoEvents()
            
            # 執行安裝腳本
            $script:LogTextBox.AppendText("正在執行 Chocolatey 安裝...`r`n")
            [System.Windows.Forms.Application]::DoEvents()
            
            Invoke-Expression $installScript
            $script:LogTextBox.AppendText("✓ Chocolatey 安裝腳本執行完成`r`n")
        }
        catch {
            $script:LogTextBox.AppendText("方法 1 失敗：$($_.Exception.Message)`r`n")
            $script:LogTextBox.AppendText("嘗試備用安裝方法...`r`n")
            [System.Windows.Forms.Application]::DoEvents()
            
            # 方法 2：使用 Invoke-RestMethod
            try {
                $installScript = Invoke-RestMethod -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing
                $script:LogTextBox.AppendText("✓ 使用 REST 方法下載成功`r`n")
                [System.Windows.Forms.Application]::DoEvents()
                
                Invoke-Expression $installScript
                $script:LogTextBox.AppendText("✓ Chocolatey 安裝完成`r`n")
            }
            catch {
                $script:LogTextBox.AppendText("方法 2 也失敗：$($_.Exception.Message)`r`n")
                
                # 方法 3：手動安裝
                $script:LogTextBox.AppendText("嘗試手動安裝方法...`r`n")
                [System.Windows.Forms.Application]::DoEvents()
                
                $chocoInstallPath = "$env:ALLUSERSPROFILE\chocolatey"
                $chocoExePath = "$chocoInstallPath\bin"
                
                # 建立目錄
                New-Item -Path $chocoInstallPath -ItemType Directory -Force | Out-Null
                New-Item -Path $chocoExePath -ItemType Directory -Force | Out-Null
                
                # 下載 chocolatey.nupkg
                $chocoUrl = "https://packages.chocolatey.org/chocolatey.0.12.1.nupkg"
                $chocoNupkg = "$chocoInstallPath\chocolatey.0.12.1.nupkg"
                
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($chocoUrl, $chocoNupkg)
                $script:LogTextBox.AppendText("✓ Chocolatey 套件下載完成`r`n")
                
                # 解壓縮
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($chocoNupkg, $chocoInstallPath)
                $script:LogTextBox.AppendText("✓ Chocolatey 套件解壓縮完成`r`n")
                
                throw "請手動完成安裝或檢查網路連線"
            }
        }
        
        # 等待幾秒讓安裝完成
        Start-Sleep -Seconds 3
        
        # 重新整理環境變數
        $script:LogTextBox.AppendText("更新環境變數...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
        
        # 手動添加 Chocolatey 路徑
        $chocoPath = "$env:ALLUSERSPROFILE\chocolatey\bin"
        if (Test-Path $chocoPath) {
            $env:Path = "$env:Path;$chocoPath"
            $script:LogTextBox.AppendText("✓ Chocolatey 路徑已添加到 PATH`r`n")
        }
        
        [System.Windows.Forms.Application]::DoEvents()
        
        # 驗證安裝
        $script:LogTextBox.AppendText("驗證 Chocolatey 安裝...`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        Start-Sleep -Seconds 2
        
        # 嘗試執行 choco 命令驗證
        try {
            $chocoVersion = & choco --version 2>$null
            if ($chocoVersion) {
                $script:LogTextBox.AppendText("✓ Chocolatey 安裝成功！版本：$chocoVersion`r`n")
                $script:Manager.IsInstalled = $true
                $script:InstallChocoButton.Text = "✓ Chocolatey 已安裝"
                $script:InstallChocoButton.Enabled = $false
                $script:StatusLabel.Text = "狀態：Chocolatey 已安裝，可以開始選擇套件"
                return $true
            } else {
                throw "無法執行 choco 命令"
            }
        }
        catch {
            $script:LogTextBox.AppendText("警告：無法驗證安裝，但可能已安裝成功`r`n")
            $script:LogTextBox.AppendText("請手動檢查或重啟程式`r`n")
            
            # 重新啟用按鈕
            $script:InstallChocoButton.Enabled = $true
            $script:InstallChocoButton.Text = "重試安裝"
            $script:StatusLabel.Text = "狀態：Chocolatey 安裝可能未完成，請重試"
            return $false
        }
        
    }
    catch {
        $script:LogTextBox.AppendText("安裝 Chocolatey 時發生錯誤：$($_.Exception.Message)`r`n")
        $script:LogTextBox.AppendText("可能的解決方案：`r`n")
        $script:LogTextBox.AppendText("1. 檢查網路連線`r`n")
        $script:LogTextBox.AppendText("2. 以管理員身分執行`r`n")
        $script:LogTextBox.AppendText("3. 檢查防火牆設定`r`n")
        $script:LogTextBox.AppendText("4. 手動安裝：https://chocolatey.org/install`r`n")
        
        # 重新啟用按鈕
        $script:InstallChocoButton.Enabled = $true
        $script:InstallChocoButton.Text = "重試安裝"
        $script:StatusLabel.Text = "狀態：Chocolatey 安裝失敗"
        return $false
    }
}

# 安裝選定套件 (非同步)
function Install-SelectedPackages {
    if (-not $script:Manager.IsInstalled) {
        [System.Windows.Forms.MessageBox]::Show("請先安裝 Chocolatey！", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selectedPackages = $script:Manager.GetSelectedPackages()
    if ($selectedPackages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("請選擇要安裝的套件！", "提醒", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    
    # 禁用按鈕，防止重複執行
    $script:InstallButton.Enabled = $false
    $script:UninstallButton.Enabled = $false
    $script:RefreshStatusButton.Enabled = $false
    $script:StatusLabel.Text = "狀態：正在安裝套件..."
    $script:LogTextBox.AppendText("開始安裝 $($selectedPackages.Count) 個套件...`r`n")
    
    # 啟動背景工作
    Start-AsyncPackageOperation -Packages $selectedPackages -Operation "install" -OnComplete {
        param($successCount, $errorCount)
        
        # 在UI線程中更新界面
        $script:MainForm.Invoke([Action]{
            $script:LogTextBox.AppendText("`r`n安裝完成！成功：$successCount，失敗：$errorCount`r`n")
            $script:StatusLabel.Text = "狀態：安裝完成 - 成功：$successCount，失敗：$errorCount"
            $script:InstallButton.Enabled = $true
            $script:UninstallButton.Enabled = $true
            $script:RefreshStatusButton.Enabled = $true
            
            # 重新整理套件狀態
            Refresh-PackageStatus
        })
    }
}

# 移除選定套件 (非同步)
function Uninstall-SelectedPackages {
    if (-not $script:Manager.IsInstalled) {
        [System.Windows.Forms.MessageBox]::Show("需要先安裝 Chocolatey！", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selectedPackages = $script:Manager.GetSelectedPackages()
    $installedPackages = $selectedPackages | Where-Object { $_.IsInstalled -eq $true }
    
    if ($installedPackages.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("請選擇要移除的已安裝套件！", "提醒", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    
    # 確認對話框
    $result = [System.Windows.Forms.MessageBox]::Show("確定要移除選定的 $($installedPackages.Count) 個套件嗎？`n`n這個動作無法復原。", "確認移除", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }
    
    # 禁用按鈕，防止重複執行
    $script:UninstallButton.Enabled = $false
    $script:InstallButton.Enabled = $false
    $script:RefreshStatusButton.Enabled = $false
    $script:StatusLabel.Text = "狀態：正在移除套件..."
    $script:LogTextBox.AppendText("開始移除 $($installedPackages.Count) 個套件...`r`n")
    
    # 啟動背景工作
    Start-AsyncPackageOperation -Packages $installedPackages -Operation "uninstall" -OnComplete {
        param($successCount, $errorCount)
        
        # 在UI線程中更新界面
        $script:MainForm.Invoke([Action]{
            $script:LogTextBox.AppendText("`r`n移除完成！成功：$successCount，失敗：$errorCount`r`n")
            $script:StatusLabel.Text = "狀態：移除完成 - 成功：$successCount，失敗：$errorCount"
            $script:UninstallButton.Enabled = $true
            $script:InstallButton.Enabled = $true
            $script:RefreshStatusButton.Enabled = $true
            
            # 重新整理套件狀態
            Refresh-PackageStatus
        })
    }
}

# 檢查 Chocolatey 狀態
function Test-ChocolateyStatus {
    $script:Manager.IsInstalled = $script:Manager.TestChocolateyInstalled()
    if ($script:Manager.IsInstalled) {
        $script:InstallChocoButton.Text = "✓ Chocolatey 已安裝"
        $script:InstallChocoButton.Enabled = $false
        $script:StatusLabel.Text = "狀態：Chocolatey 已安裝，可以開始選擇套件"
    } else {
        $script:InstallChocoButton.Text = "安裝 Chocolatey"
        $script:InstallChocoButton.Enabled = $true
        $script:StatusLabel.Text = "狀態：需要先安裝 Chocolatey"
    }
}

# 重新整理套件狀態
function Refresh-PackageStatus {
    $script:StatusLabel.Text = "狀態：正在檢查套件安裝狀態..."
    $script:RefreshStatusButton.Enabled = $false
    
    try {
        $script:Manager.UpdatePackageInstallationStatus()
        Refresh-PackageDisplay
        $script:StatusLabel.Text = "狀態：套件狀態已更新"
    }
    catch {
        $script:StatusLabel.Text = "狀態：更新失敗 - $($_.Exception.Message)"
        $script:LogTextBox.AppendText("錯誤：$($_.Exception.Message)`r`n")
    }
    finally {
        $script:RefreshStatusButton.Enabled = $true
    }
}

# 匯出已安裝套件清單 (使用 choco export)
function Export-InstalledPackages {
    try {
        if (-not $script:Manager.IsInstalled) {
            [System.Windows.Forms.MessageBox]::Show("需要先安裝 Chocolatey！", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # 選擇儲存位置
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Chocolatey 套件配置 (*.config)|*.config|所有檔案 (*.*)|*.*"
        $saveDialog.Title = "匯出已安裝套件清單"
        $saveDialog.FileName = "packages-$(Get-Date -Format 'yyyyMMdd-HHmmss').config"
        
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:StatusLabel.Text = "狀態：正在匯出套件清單..."
            $script:LogTextBox.AppendText("使用 choco export 匯出已安裝套件清單...`r`n")
            
            # 禁用按鈕
            $script:ExportButton.Enabled = $false
            
            # 使用 choco export 命令
            $success = $script:Manager.ExportInstalledPackagesWithChoco($saveDialog.FileName, $false)
            
            if ($success) {
                # 計算匯出的套件數量
                $packageCount = $script:Manager.GetPackageCountFromConfig($saveDialog.FileName)
                
                $script:LogTextBox.AppendText("✓ 成功匯出 $packageCount 個套件到：`r`n")
                $script:LogTextBox.AppendText("  $($saveDialog.FileName)`r`n")
                $script:StatusLabel.Text = "狀態：匯出完成 - 已匯出 $packageCount 個套件"
                
                [System.Windows.Forms.MessageBox]::Show("成功匯出 $packageCount 個已安裝套件！`n`n格式：Chocolatey packages.config`n儲存位置：`n$($saveDialog.FileName)", "匯出成功", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                throw "choco export 命令執行失敗"
            }
        }
    }
    catch {
        $script:StatusLabel.Text = "狀態：匯出失敗 - $($_.Exception.Message)"
        $script:LogTextBox.AppendText("✗ 匯出失敗：$($_.Exception.Message)`r`n")
        [System.Windows.Forms.MessageBox]::Show("匯出失敗：$($_.Exception.Message)", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $script:ExportButton.Enabled = $true
    }
}

# 匯入套件清單並一鍵安裝 (使用 choco install packages.config)
function Import-PackageList {
    try {
        if (-not $script:Manager.IsInstalled) {
            [System.Windows.Forms.MessageBox]::Show("需要先安裝 Chocolatey！", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # 選擇匯入檔案
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "Chocolatey 套件配置 (*.config)|*.config|所有檔案 (*.*)|*.*"
        $openDialog.Title = "選擇 packages.config 檔案"
        
        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:StatusLabel.Text = "狀態：正在載入套件清單..."
            $script:LogTextBox.AppendText("載入套件清單：$($openDialog.FileName)`r`n")
            
            # 讀取並解析 packages.config 檔案
            try {
                [xml]$configXml = Get-Content $openDialog.FileName -Encoding UTF8
                $packageCount = $configXml.packages.package.Count
                
                if ($packageCount -eq 0) {
                    throw "套件清單檔案中沒有找到任何套件"
                }
                
                # 取得套件名稱列表以供確認
                $packageNames = $configXml.packages.package | ForEach-Object { $_.id }
                $script:LogTextBox.AppendText("發現 $packageCount 個套件待安裝`r`n")
                
                # 確認安裝
                $packageList = $packageNames -join "`n• "
                $result = [System.Windows.Forms.MessageBox]::Show("發現 $packageCount 個套件：`n`n• $packageList`n`n確定要安裝這些套件嗎？", "確認一鍵安裝", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                
                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    # 禁用按鈕
                    $script:ExportButton.Enabled = $false
                    $script:ImportButton.Enabled = $false
                    $script:InstallButton.Enabled = $false
                    $script:UninstallButton.Enabled = $false
                    $script:RefreshStatusButton.Enabled = $false
                    
                    $script:StatusLabel.Text = "狀態：正在使用 choco install 安裝套件..."
                    $script:LogTextBox.AppendText("使用 choco install `"$($openDialog.FileName)`" 開始批量安裝...`r`n")
                    
                    # 使用 choco install packages.config 命令
                    $chocoArgs = "install `"$($openDialog.FileName)`" -y"
                    $result = Invoke-ChocoCommandWithUI -Arguments $chocoArgs
                    
                    if ($result.Success) {
                        $script:LogTextBox.AppendText("✓ 一鍵安裝完成！`r`n")
                        $script:StatusLabel.Text = "狀態：一鍵安裝完成"
                        
                        [System.Windows.Forms.MessageBox]::Show("一鍵安裝完成！`n`n已安裝 $packageCount 個套件", "安裝完成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    } else {
                        $script:LogTextBox.AppendText("✗ 一鍵安裝失敗 (退出代碼: $($result.ExitCode))`r`n")
                        $script:StatusLabel.Text = "狀態：一鍵安裝失敗"
                        
                        [System.Windows.Forms.MessageBox]::Show("一鍵安裝失敗！`n請查看日誌了解詳細錯誤資訊。", "安裝失敗", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                    
                    # 重新整理套件狀態
                    Refresh-PackageStatus
                    
                    # 重新啟用按鈕
                    $script:ExportButton.Enabled = $true
                    $script:ImportButton.Enabled = $true
                    $script:InstallButton.Enabled = $true
                    $script:UninstallButton.Enabled = $true
                    $script:RefreshStatusButton.Enabled = $true
                }
            }
            catch {
                throw "無法解析套件配置檔案：$($_.Exception.Message)"
            }
        }
    }
    catch {
        $script:StatusLabel.Text = "狀態：匯入失敗 - $($_.Exception.Message)"
        $script:LogTextBox.AppendText("✗ 匯入失敗：$($_.Exception.Message)`r`n")
        [System.Windows.Forms.MessageBox]::Show("匯入失敗：$($_.Exception.Message)", "錯誤", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        
        # 確保按鈕重新啟用
        $script:ExportButton.Enabled = $true
        $script:ImportButton.Enabled = $true
        $script:InstallButton.Enabled = $true
        $script:UninstallButton.Enabled = $true
        $script:RefreshStatusButton.Enabled = $true
    }
}

# 重新整理套件顯示
function Refresh-PackageDisplay {
    foreach ($tabPage in $script:TabControl.TabPages) {
        $panel = $tabPage.Controls[0]
        if ($panel -is [System.Windows.Forms.Panel]) {
            foreach ($control in $panel.Controls) {
                if ($control -is [System.Windows.Forms.CheckBox] -and $control.Tag -and $control.Tag.Package) {
                    $package = $control.Tag.Package
                    
                    # 更新顯示文字
                    $displayText = $package.DisplayName
                    $isInstalled = $package.IsInstalled -eq $true
                    
                    if ($isInstalled) {
                        $displayText += " (已安裝"
                        if ($package.InstalledVersion) {
                            $displayText += " v$($package.InstalledVersion)"
                        }
                        $displayText += ")"
                        $control.ForeColor = [System.Drawing.Color]::DarkGreen
                    } else {
                        $control.ForeColor = [System.Drawing.Color]::Black    
                    }
                    
                    # 所有套件都可以選擇
                    $control.Enabled = $true
                    $control.BackColor = [System.Drawing.Color]::White
                    
                    # 更新文字（保留描述）
                    $showDescriptions = $script:Manager.PackageConfig -and 
                                       $script:Manager.PackageConfig.settings -and 
                                       $script:Manager.PackageConfig.settings.showPackageDescriptions
                    if ($package.Description -and $showDescriptions) {
                        $control.Text = "$displayText`r`n    $($package.Description)"
                    } else {
                        $control.Text = $displayText
                    }
                }
            }
        }
    }
}

# 建立主表單
function Create-MainForm {
    $script:MainForm = New-Object System.Windows.Forms.Form
    $script:MainForm.Text = "Chocolatey GUI 安裝器"
    $script:MainForm.Size = New-Object System.Drawing.Size(800, 600)
    $script:MainForm.StartPosition = "CenterScreen"
    $script:MainForm.FormBorderStyle = "FixedSingle"
    $script:MainForm.MaximizeBox = $false
}

# 建立控制項
function Create-Controls {
    # Chocolatey安裝按鈕
    $script:InstallChocoButton = New-Object System.Windows.Forms.Button
    $script:InstallChocoButton.Location = New-Object System.Drawing.Point(10, 10)
    $script:InstallChocoButton.Size = New-Object System.Drawing.Size(150, 30)
    $script:InstallChocoButton.Text = "安裝 Chocolatey"
    $script:InstallChocoButton.Add_Click({ Install-Chocolatey })
    $script:MainForm.Controls.Add($script:InstallChocoButton)
    
    # 檢查狀態按鈕
    $checkStatusButton = New-Object System.Windows.Forms.Button
    $checkStatusButton.Location = New-Object System.Drawing.Point(170, 10)
    $checkStatusButton.Size = New-Object System.Drawing.Size(100, 30)
    $checkStatusButton.Text = "檢查狀態"
    $checkStatusButton.Add_Click({ Test-ChocolateyStatus })
    $script:MainForm.Controls.Add($checkStatusButton)
    
    # 套件選擇區域
    $script:TabControl = New-Object System.Windows.Forms.TabControl
    $script:TabControl.Location = New-Object System.Drawing.Point(10, 50)
    $script:TabControl.Size = New-Object System.Drawing.Size(760, 300)
    
    # 為每個分類建立標籤頁
    foreach ($category in $script:Manager.PackageCategories.Keys) {
        Create-CategoryTab $category
    }
    
    $script:MainForm.Controls.Add($script:TabControl)
    
    # 安裝按鈕
    $script:InstallButton = New-Object System.Windows.Forms.Button
    $script:InstallButton.Location = New-Object System.Drawing.Point(10, 360)
    $script:InstallButton.Size = New-Object System.Drawing.Size(150, 35)
    $script:InstallButton.Text = "安裝選定套件"
    $script:InstallButton.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10, [System.Drawing.FontStyle]::Bold)
    $script:InstallButton.Add_Click({ Install-SelectedPackages })
    $script:MainForm.Controls.Add($script:InstallButton)
    
    # 移除套件按鈕
    $script:UninstallButton = New-Object System.Windows.Forms.Button
    $script:UninstallButton.Location = New-Object System.Drawing.Point(170, 360)
    $script:UninstallButton.Size = New-Object System.Drawing.Size(150, 35)
    $script:UninstallButton.Text = "移除選定套件"
    $script:UninstallButton.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10, [System.Drawing.FontStyle]::Bold)
    $script:UninstallButton.BackColor = [System.Drawing.Color]::LightCoral
    $script:UninstallButton.Add_Click({ Uninstall-SelectedPackages })
    $script:MainForm.Controls.Add($script:UninstallButton)
    
    # 重新整理套件狀態按鈕
    $script:RefreshStatusButton = New-Object System.Windows.Forms.Button
    $script:RefreshStatusButton.Location = New-Object System.Drawing.Point(330, 360)
    $script:RefreshStatusButton.Size = New-Object System.Drawing.Size(120, 35)
    $script:RefreshStatusButton.Text = "重新整理狀態"
    $script:RefreshStatusButton.Add_Click({ Refresh-PackageStatus })
    $script:MainForm.Controls.Add($script:RefreshStatusButton)
    
    # 檢查Chocolatey按鈕
    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Location = New-Object System.Drawing.Point(460, 360)
    $refreshButton.Size = New-Object System.Drawing.Size(100, 35)
    $refreshButton.Text = "檢查Choco"
    $refreshButton.Add_Click({ Test-ChocolateyStatus })
    $script:MainForm.Controls.Add($refreshButton)
    
    # 匯出套件清單按鈕
    $script:ExportButton = New-Object System.Windows.Forms.Button
    $script:ExportButton.Location = New-Object System.Drawing.Point(570, 360)
    $script:ExportButton.Size = New-Object System.Drawing.Size(100, 35)
    $script:ExportButton.Text = "匯出清單"
    $script:ExportButton.BackColor = [System.Drawing.Color]::LightBlue
    $script:ExportButton.Add_Click({ Export-InstalledPackages })
    $script:MainForm.Controls.Add($script:ExportButton)
    
    # 匯入清單並一鍵安裝按鈕
    $script:ImportButton = New-Object System.Windows.Forms.Button
    $script:ImportButton.Location = New-Object System.Drawing.Point(680, 360)
    $script:ImportButton.Size = New-Object System.Drawing.Size(100, 35)
    $script:ImportButton.Text = "一鍵安裝"
    $script:ImportButton.BackColor = [System.Drawing.Color]::LightGreen
    $script:ImportButton.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 9, [System.Drawing.FontStyle]::Bold)
    $script:ImportButton.Add_Click({ Import-PackageList })
    $script:MainForm.Controls.Add($script:ImportButton)
    
    # 狀態標籤
    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Location = New-Object System.Drawing.Point(10, 405)
    $script:StatusLabel.Size = New-Object System.Drawing.Size(760, 20)
    $script:StatusLabel.Text = "狀態：就緒"
    $script:MainForm.Controls.Add($script:StatusLabel)
    
    # 日誌輸出區域
    $script:LogTextBox = New-Object System.Windows.Forms.TextBox
    $script:LogTextBox.Location = New-Object System.Drawing.Point(10, 430)
    $script:LogTextBox.Size = New-Object System.Drawing.Size(760, 120)
    $script:LogTextBox.Multiline = $true
    $script:LogTextBox.ScrollBars = "Vertical"
    $script:LogTextBox.ReadOnly = $true
    $script:LogTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:MainForm.Controls.Add($script:LogTextBox)
}

# 建立分類標籤頁
function Create-CategoryTab {
    param([string]$categoryName)
    
    $tabPage = New-Object System.Windows.Forms.TabPage
    $tabPage.Text = $categoryName
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.AutoScroll = $true
    
    $y = 10
    foreach ($package in $script:Manager.PackageCategories[$categoryName]) {
        $y = Create-PackageCheckbox $panel $package $categoryName $y
    }
    
    # 全選/取消全選按鈕
    Create-CategoryButtons $panel $categoryName $y
    
    $tabPage.Controls.Add($panel)
    $script:TabControl.TabPages.Add($tabPage)
}

# 建立套件選擇框
function Create-PackageCheckbox {
    param([object]$panel, [hashtable]$package, [string]$category, [int]$y)
    
    $checkbox = New-Object System.Windows.Forms.CheckBox
    $checkbox.Location = New-Object System.Drawing.Point(10, $y)
    
    # 根據安裝狀態設定顯示文字和樣式
    $displayText = $package.DisplayName
    $isInstalled = $package.IsInstalled -eq $true
    
    if ($isInstalled) {
        $displayText += " (已安裝"
        if ($package.InstalledVersion) {
            $displayText += " v$($package.InstalledVersion)"
        }
        $displayText += ")"
        $checkbox.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $checkbox.ForeColor = [System.Drawing.Color]::Black
    }
    
    # 所有套件都可以選擇
    $checkbox.Enabled = $true
    $checkbox.BackColor = [System.Drawing.Color]::White
    
    # 根據是否有描述調整控制項高度  
    $showDescriptions = $script:Manager.PackageConfig -and 
                       $script:Manager.PackageConfig.settings -and 
                       $script:Manager.PackageConfig.settings.showPackageDescriptions
    $hasDescription = $package.Description -and $package.Description.Length -gt 0 -and $showDescriptions
    
    if ($hasDescription) {
        $checkbox.Size = New-Object System.Drawing.Size(700, 40)
        $checkbox.Text = "$displayText`r`n    $($package.Description)"
        $y += 45
    } else {
        $checkbox.Size = New-Object System.Drawing.Size(700, 20)
        $checkbox.Text = $displayText
        $y += 25
    }
    
    # 設定選擇狀態
    $checkbox.Checked = $package.Selected
    
    $checkbox.Tag = @{Category=$category; Package=$package}
    $checkbox.Add_CheckedChanged({
        $this.Tag.Package.Selected = $this.Checked
    })
    
    $panel.Controls.Add($checkbox)
    return $y
}

# 建立分類按鈕
function Create-CategoryButtons {
    param([object]$panel, [string]$category, [int]$y)
    
    $buttonY = $y + 10
    
    # 全選按鈕
    $selectAllButton = New-Object System.Windows.Forms.Button
    $selectAllButton.Location = New-Object System.Drawing.Point(10, $buttonY)
    $selectAllButton.Size = New-Object System.Drawing.Size(80, 25)
    $selectAllButton.Text = "全選"
    $selectAllButton.Tag = @{Category=$category; Panel=$panel}
    $selectAllButton.Add_Click({
        $cat = $this.Tag.Category
        $panelRef = $this.Tag.Panel
        foreach ($pkg in $script:Manager.PackageCategories[$cat]) {
            $pkg.Selected = $true
        }
        # 更新界面
        foreach ($control in $panelRef.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox]) {
                $control.Checked = $true
            }
        }
    })
    $panel.Controls.Add($selectAllButton)
    
    # 取消全選按鈕
    $deselectAllButton = New-Object System.Windows.Forms.Button
    $deselectAllButton.Location = New-Object System.Drawing.Point(100, $buttonY)
    $deselectAllButton.Size = New-Object System.Drawing.Size(80, 25)
    $deselectAllButton.Text = "取消全選"
    $deselectAllButton.Tag = @{Category=$category; Panel=$panel}
    $deselectAllButton.Add_Click({
        $cat = $this.Tag.Category
        $panelRef = $this.Tag.Panel
        foreach ($pkg in $script:Manager.PackageCategories[$cat]) {
            $pkg.Selected = $false
        }
        # 更新界面
        foreach ($control in $panelRef.Controls) {
            if ($control -is [System.Windows.Forms.CheckBox]) {
                $control.Checked = $false
            }
        }
    })
    $panel.Controls.Add($deselectAllButton)
}

# 主程式
function Main {
    try {
        Write-Host "正在初始化 Chocolatey GUI 安裝器..." -ForegroundColor Green
        
        # 創建管理器實例
        $script:Manager = [ChocolateyManager]::new()
        
        # 建立並顯示主表單
        Create-MainForm
        Create-Controls
        
        # 更新初始狀態
        if ($script:Manager.IsInstalled) {
            $script:InstallChocoButton.Text = "✓ Chocolatey 已安裝"
            $script:InstallChocoButton.Enabled = $false
            $script:StatusLabel.Text = "狀態：就緒 - 套件狀態已更新"
        } else {
            $script:StatusLabel.Text = "狀態：需要先安裝 Chocolatey"
        }
        
        Write-Host "初始化完成，啟動GUI..." -ForegroundColor Green
        
        # 顯示GUI
        [System.Windows.Forms.Application]::Run($script:MainForm)
    }
    catch {
        Write-Host "啟動時發生錯誤：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "錯誤詳情：$($_.Exception.StackTrace)" -ForegroundColor Red
        Read-Host "按 Enter 鍵結束"
    }
}

# 執行主程式
Main