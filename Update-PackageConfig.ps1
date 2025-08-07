# 配置檔案更新工具
# 確保所有套件都有預設的 selected 屬性設為 false

param(
    [string]$ConfigPath = "packages-config.json"
)

function Update-PackageConfig {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "配置文件不存在：$Path" -ForegroundColor Red
        return
    }
    
    try {
        # 讀取配置文件
        $configContent = Get-Content $Path -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json
        
        $updated = $false
        
        # 檢查每個分類的套件
        foreach ($categoryName in $config.packageCategories.PSObject.Properties.Name) {
            $category = $config.packageCategories.$categoryName
            
            foreach ($package in $category.packages) {
                # 如果沒有 selected 屬性，添加並設為 false
                if (-not ($package.PSObject.Properties.Name -contains "selected")) {
                    $package | Add-Member -MemberType NoteProperty -Name "selected" -Value $false
                    $updated = $true
                    Write-Host "為套件 $($package.name) 添加 selected 屬性" -ForegroundColor Yellow
                }
            }
        }
        
        if ($updated) {
            # 儲存更新後的配置
            $updatedJson = $config | ConvertTo-Json -Depth 10
            Set-Content $Path -Value $updatedJson -Encoding UTF8
            Write-Host "配置文件已更新：$Path" -ForegroundColor Green
        } else {
            Write-Host "配置文件無需更新" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "更新配置文件時發生錯誤：$($_.Exception.Message)" -ForegroundColor Red
    }
}

# 執行更新
$fullPath = Join-Path $PSScriptRoot $ConfigPath
Update-PackageConfig -Path $fullPath