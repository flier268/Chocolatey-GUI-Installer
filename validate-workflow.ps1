# GitHub Actions Workflow 驗證腳本
# 模擬並測試 release.yml 中的每個步驟

param(
    [string]$TestVersion = "v1.0.0-test",
    [switch]$Verbose,
    [switch]$SkipInstall,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Continue" # 繼續執行以收集所有錯誤

# 記錄和報告
$script:TestResults = @()
$script:StepNumber = 0

function Write-TestHeader($StepName) {
    $script:StepNumber++
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "步驟 $script:StepNumber : $StepName" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-TestResult($TestName, $Success, $Message = "", $Details = "") {
    $status = if ($Success) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "$status $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  └─ $Message" -ForegroundColor Gray
    }
    
    $script:TestResults += @{
        Step = $script:StepNumber
        Test = $TestName
        Success = $Success
        Message = $Message
        Details = $Details
    }
    
    if ($Verbose -and $Details) {
        Write-Host "  詳情: $Details" -ForegroundColor DarkGray
    }
}

function Test-YamlSyntax {
    Write-TestHeader "YAML 語法驗證"
    
    $workflowPath = ".github/workflows/release.yml"
    
    # 檢查檔案存在
    if (-not (Test-Path $workflowPath)) {
        Write-TestResult "工作流程檔案存在" $false "找不到 $workflowPath"
        return
    }
    Write-TestResult "工作流程檔案存在" $true
    
    # 基本 YAML 結構檢查
    try {
        $content = Get-Content $workflowPath -Raw
        
        # 檢查必要的根節點
        $requiredKeys = @("name", "on", "permissions", "jobs")
        foreach ($key in $requiredKeys) {
            if ($content -match "(?m)^$key\s*:") {
                Write-TestResult "YAML 根節點: $key" $true
            } else {
                Write-TestResult "YAML 根節點: $key" $false "缺少必要的根節點"
            }
        }
        
        # 檢查觸發條件
        $hasWorkflowDispatch = $content -match "workflow_dispatch"
        $hasPushTags = $content -match "push:\s*\n.*tags:"
        
        Write-TestResult "手動觸發設定 (workflow_dispatch)" $hasWorkflowDispatch
        Write-TestResult "標籤推送觸發 (push tags)" $hasPushTags
        
        # 檢查權限設定
        $hasContentWrite = $content -match "contents:\s*write"
        Write-TestResult "內容寫入權限" $hasContentWrite
        
    }
    catch {
        Write-TestResult "YAML 語法解析" $false $_.Exception.Message
    }
}

function Test-PowerShellSteps {
    Write-TestHeader "PowerShell 步驟測試"
    
    # 清理之前的測試檔案
    $testDirs = @("build", "scripts-only", "executables-only")
    foreach ($dir in $testDirs) {
        if (Test-Path $dir) {
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -Path "." -Filter "*.zip" | Remove-Item -Force -ErrorAction SilentlyContinue
    
    # 步驟 1: 模擬 Checkout
    Write-TestResult "代碼檢出 (Checkout)" $true "本地檔案已存在"
    
    # 步驟 2: 測試 ps2exe 模組安裝
    if (-not $SkipInstall) {
        try {
            Write-Host "  正在檢查 ps2exe 模組..." -ForegroundColor Yellow
            
            if (-not (Get-Module -ListAvailable -Name ps2exe)) {
                Write-Host "  安裝 ps2exe 模組..." -ForegroundColor Yellow
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
                Install-Module -Name ps2exe -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            }
            
            Import-Module ps2exe -Force -ErrorAction Stop
            
            if (Get-Command ps2exe -ErrorAction SilentlyContinue) {
                $version = (Get-Module ps2exe).Version
                Write-TestResult "ps2exe 模組安裝" $true "版本: $version"
            } else {
                Write-TestResult "ps2exe 模組安裝" $false "命令不可用"
            }
        }
        catch {
            Write-TestResult "ps2exe 模組安裝" $false $_.Exception.Message
        }
    } else {
        Write-TestResult "ps2exe 模組安裝" $true "跳過安裝檢查"
    }
    
    # 步驟 3: 測試目錄建立
    try {
        $directories = @("build", "scripts-only", "executables-only")
        $allCreated = $true
        
        foreach ($dir in $directories) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            if (Test-Path $dir) {
                Write-TestResult "建立目錄: $dir" $true
            } else {
                Write-TestResult "建立目錄: $dir" $false
                $allCreated = $false
            }
        }
        
        Write-TestResult "目錄建立步驟" $allCreated
    }
    catch {
        Write-TestResult "目錄建立步驟" $false $_.Exception.Message
    }
    
    # 步驟 4: 測試檔案複製
    try {
        $sourceFiles = @{
            "*.ps1" = "PowerShell 腳本"
            "*.json" = "JSON 設定檔"
            "*.md" = "Markdown 文件"
        }
        
        $copySuccess = $true
        foreach ($pattern in $sourceFiles.Keys) {
            $files = Get-ChildItem -Path "." -Filter $pattern -File
            if ($files.Count -gt 0) {
                Copy-Item $pattern -Destination "build/" -ErrorAction SilentlyContinue
                $copiedFiles = Get-ChildItem -Path "build/" -Filter $pattern
                Write-TestResult "複製 $($sourceFiles[$pattern])" ($copiedFiles.Count -eq $files.Count) "$($copiedFiles.Count)/$($files.Count) 檔案"
            } else {
                Write-TestResult "複製 $($sourceFiles[$pattern])" $true "無檔案需要複製"
            }
        }
        
        if (Test-Path "LICENSE") {
            Copy-Item "LICENSE" -Destination "build/" -ErrorAction SilentlyContinue
            Write-TestResult "複製授權檔案" (Test-Path "build/LICENSE")
        }
        
    }
    catch {
        Write-TestResult "檔案複製步驟" $false $_.Exception.Message
    }
}

function Test-ExecutableBuild {
    Write-TestHeader "執行檔編譯測試"
    
    $scriptsToTest = @(
        @{
            Name = "Chocolatey-GUI-Installer.ps1"
            Output = "build/Chocolatey-GUI-Installer.exe"
            RequireAdmin = $true
            NoConsole = $true
            Description = "主要 GUI 安裝程式 (包含 ChocolateyManager 依賴)"
        },
        @{
            Name = "Update-PackageConfig.ps1"
            Output = "build/Update-PackageConfig.exe"
            RequireAdmin = $false
            NoConsole = $false
            Description = "獨立的配置更新工具"
        }
    )
    
    $ps2exeAvailable = $false
    try {
        $ps2exeAvailable = (Get-Command ps2exe -ErrorAction SilentlyContinue) -ne $null
    }
    catch { }
    
    if (-not $ps2exeAvailable) {
        Write-TestResult "ps2exe 可用性" $false "ps2exe 命令不可用，跳過編譯測試"
        return
    }
    
    Write-TestResult "ps2exe 可用性" $true
    
    foreach ($script in $scriptsToTest) {
        if (Test-Path $script.Name) {
            try {
                Write-Host "  編譯: $($script.Name) - $($script.Description)" -ForegroundColor Yellow
                
                # For main installer, ensure dependency is available
                if ($script.Name -eq "Chocolatey-GUI-Installer.ps1" -and (Test-Path "ChocolateyManager.ps1")) {
                    Copy-Item "ChocolateyManager.ps1" -Destination "build/" -ErrorAction SilentlyContinue
                    Write-Host "    └─ 已複製依賴檔案: ChocolateyManager.ps1" -ForegroundColor Gray
                }
                
                $ps2exeParams = @{
                    inputFile = $script.Name
                    outputFile = $script.Output  
                    title = "Test Build"
                    description = $script.Description
                    company = "Test"
                    version = "1.0.0.0"
                    STA = $true
                    supportOS = $true
                    longPaths = $true
                }
                
                if ($script.RequireAdmin) { $ps2exeParams.requireAdmin = $true }
                # 保留控制台輸出以便調試
                # if ($script.NoConsole) { $ps2exeParams.noConsole = $true }
                
                Invoke-ps2exe @ps2exeParams 2>$null
                
                if (Test-Path $script.Output) {
                    $size = [math]::Round((Get-Item $script.Output).Length / 1KB, 1)
                    Write-TestResult "編譯: $($script.Name)" $true "輸出: $size KB"
                } else {
                    Write-TestResult "編譯: $($script.Name)" $false "未產生輸出檔案"
                }
            }
            catch {
                Write-TestResult "編譯: $($script.Name)" $false $_.Exception.Message
            }
        } else {
            Write-TestResult "編譯: $($script.Name)" $false "原始檔案不存在"
        }
    }
}

function Test-PackageCreation {
    Write-TestHeader "發布套件建立測試"
    
    try {
        # 準備 scripts-only 套件
        Write-Host "  準備 PowerShell 腳本套件..." -ForegroundColor Yellow
        Copy-Item "*.ps1" -Destination "scripts-only/" -ErrorAction SilentlyContinue
        Copy-Item "*.json" -Destination "scripts-only/" -ErrorAction SilentlyContinue
        Copy-Item "*.md" -Destination "scripts-only/" -ErrorAction SilentlyContinue
        if (Test-Path "LICENSE") { Copy-Item "LICENSE" -Destination "scripts-only/" }
        
        $scriptsCount = (Get-ChildItem "scripts-only/" -ErrorAction SilentlyContinue).Count
        Write-TestResult "準備腳本套件" ($scriptsCount -gt 0) "$scriptsCount 個檔案"
        
        # 準備 executables-only 套件
        Write-Host "  準備執行檔套件..." -ForegroundColor Yellow
        Copy-Item "build/*.exe" -Destination "executables-only/" -ErrorAction SilentlyContinue
        # 重要：複製 ChocolateyManager.ps1 依賴檔案到執行檔目錄
        Copy-Item "build/ChocolateyManager.ps1" -Destination "executables-only/" -ErrorAction SilentlyContinue
        Copy-Item "*.json" -Destination "executables-only/" -ErrorAction SilentlyContinue
        Copy-Item "README.md" -Destination "executables-only/" -ErrorAction SilentlyContinue
        Copy-Item "使用說明.md" -Destination "executables-only/" -ErrorAction SilentlyContinue
        
        $exeCount = (Get-ChildItem "executables-only/" -ErrorAction SilentlyContinue).Count
        Write-TestResult "準備執行檔套件" ($exeCount -gt 0) "$exeCount 個檔案"
        
        # 建立壓縮檔
        Write-Host "  建立壓縮檔..." -ForegroundColor Yellow
        $zipFiles = @{
            "chocolatey-gui-installer-complete.zip" = "build/*"
            "chocolatey-gui-installer-scripts.zip" = "scripts-only/*"  
            "chocolatey-gui-installer-executables.zip" = "executables-only/*"
        }
        
        foreach ($zipName in $zipFiles.Keys) {
            $sourcePath = $zipFiles[$zipName]
            try {
                Compress-Archive -Path $sourcePath -DestinationPath $zipName -Force -ErrorAction Stop
                if (Test-Path $zipName) {
                    $zipSize = [math]::Round((Get-Item $zipName).Length / 1KB, 1)
                    Write-TestResult "建立: $zipName" $true "$zipSize KB"
                } else {
                    Write-TestResult "建立: $zipName" $false "壓縮檔未建立"
                }
            }
            catch {
                Write-TestResult "建立: $zipName" $false $_.Exception.Message
            }
        }
        
    }
    catch {
        Write-TestResult "套件建立步驟" $false $_.Exception.Message
    }
}

function Test-ReleaseNotesGeneration {
    Write-TestHeader "發布說明產生測試"
    
    try {
        $version = $TestVersion
        $releaseNotes = @"
# Chocolatey GUI Installer $version

## 📦 下載檔案
測試內容...
"@
        
        $releaseNotes | Out-File -FilePath "release_notes.md" -Encoding UTF8
        
        if (Test-Path "release_notes.md") {
            $noteSize = (Get-Item "release_notes.md").Length
            Write-TestResult "發布說明檔案建立" $true "$noteSize bytes"
            
            # 檢查內容
            $content = Get-Content "release_notes.md" -Raw
            $hasVersion = $content -match $version
            Write-TestResult "發布說明包含版本號" $hasVersion
            
        } else {
            Write-TestResult "發布說明檔案建立" $false
        }
    }
    catch {
        Write-TestResult "發布說明產生" $false $_.Exception.Message
    }
}

function Test-GitHubActionsCompatibility {
    Write-TestHeader "GitHub Actions 相容性測試"
    
    # 測試環境變數模擬
    try {
        $env:GITHUB_OUTPUT = "test_output.txt"
        echo "tag=$TestVersion" >> $env:GITHUB_OUTPUT
        
        if (Test-Path $env:GITHUB_OUTPUT) {
            $content = Get-Content $env:GITHUB_OUTPUT -Raw
            $hasTag = $content -match "tag="
            Write-TestResult "GITHUB_OUTPUT 寫入" $hasTag
            Remove-Item $env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-TestResult "GITHUB_OUTPUT 寫入" $false $_.Exception.Message
    }
    
    # 測試 actions 語法
    $workflowPath = ".github/workflows/release.yml"
    if (Test-Path $workflowPath) {
        $content = Get-Content $workflowPath -Raw
        
        # 檢查 actions 版本
        $actionsVersions = @{
            "actions/checkout@v4" = $content -match "actions/checkout@v4"
            "softprops/action-gh-release@v1" = $content -match "softprops/action-gh-release@v1"
            "actions/upload-artifact@v4" = $content -match "actions/upload-artifact@v4"
        }
        
        foreach ($action in $actionsVersions.Keys) {
            Write-TestResult "Action 版本: $action" $actionsVersions[$action]
        }
    }
}

function Show-TestSummary {
    Write-TestHeader "測試結果摘要"
    
    $totalTests = $script:TestResults.Count
    $passedTests = ($script:TestResults | Where-Object { $_.Success }).Count
    $failedTests = $totalTests - $passedTests
    $successRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
    
    Write-Host "總測試數量: $totalTests" -ForegroundColor Cyan
    Write-Host "通過測試: $passedTests" -ForegroundColor Green  
    Write-Host "失敗測試: $failedTests" -ForegroundColor Red
    Write-Host "成功率: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { 'Green' } else { 'Yellow' })
    
    if ($failedTests -gt 0) {
        Write-Host "`n失敗的測試:" -ForegroundColor Red
        $script:TestResults | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Host "  ❌ 步驟 $($_.Step): $($_.Test)" -ForegroundColor Red
            if ($_.Message) {
                Write-Host "     $($_.Message)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`n建議:" -ForegroundColor Yellow
    if ($successRate -lt 80) {
        Write-Host "- 解決失敗的測試項目後再部署到 GitHub" -ForegroundColor Gray
    }
    Write-Host "- 在 GitHub 上測試手動觸發工作流程" -ForegroundColor Gray
    Write-Host "- 檢查 GitHub 儲存庫的 Actions 權限設定" -ForegroundColor Gray
}

# 主要執行流程
Write-Host "GitHub Actions Workflow 驗證開始" -ForegroundColor Green
Write-Host "測試版本: $TestVersion" -ForegroundColor Yellow
Write-Host "驗證模式: $(if ($ValidateOnly) { '僅驗證' } else { '完整測試' })" -ForegroundColor Yellow

if ($ValidateOnly) {
    Test-YamlSyntax
    Test-GitHubActionsCompatibility
} else {
    Test-YamlSyntax
    Test-PowerShellSteps  
    Test-ExecutableBuild
    Test-PackageCreation
    Test-ReleaseNotesGeneration
    Test-GitHubActionsCompatibility
}

Show-TestSummary

Write-Host "`n驗證完成！" -ForegroundColor Green