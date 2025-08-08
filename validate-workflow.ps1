# GitHub Actions Workflow 驗證腳本（Avalonia/.NET 9 AOT Windows x86/x64）

param(
    [string]$TestVersion = "v1.0.0-test",
    [switch]$Verbose,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Continue"
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
    if ($Message) { Write-Host "  └─ $Message" -ForegroundColor Gray }
    $script:TestResults += @{
        Step = $script:StepNumber
        Test = $TestName
        Success = $Success
        Message = $Message
        Details = $Details
    }
    if ($Verbose -and $Details) { Write-Host "  詳情: $Details" -ForegroundColor DarkGray }
}

function Test-YamlSyntax {
    Write-TestHeader "YAML 語法驗證"
    $workflowPath = ".github/workflows/release.yml"
    if (-not (Test-Path $workflowPath)) {
        Write-TestResult "工作流程檔案存在" $false "找不到 $workflowPath"
        return
    }
    Write-TestResult "工作流程檔案存在" $true
    try {
        $content = Get-Content $workflowPath -Raw
        $requiredKeys = @("name", "on", "permissions", "jobs")
        foreach ($key in $requiredKeys) {
            if ($content -match "(?m)^$key\s*:") {
                Write-TestResult "YAML 根節點: $key" $true
            } else {
                Write-TestResult "YAML 根節點: $key" $false "缺少必要的根節點"
            }
        }
        $hasWorkflowDispatch = $content -match "workflow_dispatch"
        $hasPushTags = $content -match "push:\s*\n.*tags:"
        Write-TestResult "手動觸發設定 (workflow_dispatch)" $hasWorkflowDispatch
        Write-TestResult "標籤推送觸發 (push tags)" $hasPushTags
        $hasContentWrite = $content -match "contents:\s*write"
        Write-TestResult "內容寫入權限" $hasContentWrite
    }
    catch {
        Write-TestResult "YAML 語法解析" $false $_.Exception.Message
    }
}

function Test-DotNetBuildSteps {
    Write-TestHeader ".NET 9 AOT Build 步驟測試"
    $publishDirs = @(
        "ChocolateyGuiAvalonia/bin/Release/net9.0/win-x64/publish",
        "ChocolateyGuiAvalonia/bin/Release/net9.0/win-x86/publish"
    )
    foreach ($dir in $publishDirs) {
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # x64
    try {
        dotnet publish ChocolateyGuiAvalonia/ChocolateyGuiAvalonia.csproj -c Release -r win-x64 --self-contained -p:PublishAot=true
        $x64Exists = Test-Path $publishDirs[0]
        Write-TestResult "AOT Build (win-x64)" $x64Exists
    } catch {
        Write-TestResult "AOT Build (win-x64)" $false $_.Exception.Message
    }
    # x86
    try {
        dotnet publish ChocolateyGuiAvalonia/ChocolateyGuiAvalonia.csproj -c Release -r win-x86 --self-contained -p:PublishAot=true
        $x86Exists = Test-Path $publishDirs[1]
        Write-TestResult "AOT Build (win-x86)" $x86Exists
    } catch {
        Write-TestResult "AOT Build (win-x86)" $false $_.Exception.Message
    }
}

function Test-ZipArtifacts {
    Write-TestHeader "AOT Build 壓縮測試"
    $zipFiles = @(
        @{ Source = "ChocolateyGuiAvalonia/bin/Release/net9.0/win-x64/publish/*"; Dest = "avalonia-win-x64.zip" },
        @{ Source = "ChocolateyGuiAvalonia/bin/Release/net9.0/win-x86/publish/*"; Dest = "avalonia-win-x86.zip" }
    )
    foreach ($zip in $zipFiles) {
        try {
            Compress-Archive -Path $zip.Source -DestinationPath $zip.Dest -Force
            $exists = Test-Path $zip.Dest
            Write-TestResult "壓縮: $($zip.Dest)" $exists
        } catch {
            Write-TestResult "壓縮: $($zip.Dest)" $false $_.Exception.Message
        }
    }
}

function Test-GitHubActionsCompatibility {
    Write-TestHeader "GitHub Actions 相容性測試"
    $workflowPath = ".github/workflows/release.yml"
    if (Test-Path $workflowPath) {
        $content = Get-Content $workflowPath -Raw
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
            if ($_.Message) { Write-Host "     $($_.Message)" -ForegroundColor Gray }
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
    Test-DotNetBuildSteps
    Test-ZipArtifacts
    Test-GitHubActionsCompatibility
}

Show-TestSummary

Write-Host "`n驗證完成！" -ForegroundColor Green