# Chocolatey管理器核心類別
class ChocolateyManager {
    [hashtable] $PackageCategories
    [object] $PackageConfig
    [bool] $IsInstalled
    
    ChocolateyManager() {
        $this.PackageCategories = @{}
        $this.PackageConfig = $null
        $this.IsInstalled = $false
        $this.Initialize()
    }
    
    # 初始化管理器
    [void] Initialize() {
        $this.IsInstalled = $this.TestChocolateyInstalled()
        try {
            $this.LoadPackageConfig()
            if ($this.IsInstalled) {
                $this.UpdatePackageInstallationStatus()
            }
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            throw "初始化失敗：$($_.Exception.Message)"
        }
    }
    
    # 檢查 Chocolatey 是否已安裝
    [bool] TestChocolateyInstalled() {
        try {
            $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
            return $null -ne $chocoPath
        }
        catch {
            return $false
        }
    }
    
    # 載入套件配置文件
    [bool] LoadPackageConfig() {
        $configPath = Join-Path $PSScriptRoot "packages-config.json"
        
        if (-not (Test-Path $configPath)) {
            throw "錯誤：找不到必需的配置文件 $configPath"
        }
        
        try {
            $configContent = Get-Content $configPath -Raw -Encoding UTF8
            $this.PackageConfig = $configContent | ConvertFrom-Json
            $this.InitializePackageCategories()
            return $true
        }
        catch {
            throw "錯誤：無法載入配置文件 $configPath - $($_.Exception.Message)"
        }
    }
    
    # 初始化套件分類資料
    [void] InitializePackageCategories() {
        $this.PackageCategories = @{}
        
        foreach ($categoryName in $this.PackageConfig.packageCategories.PSObject.Properties.Name) {
            $categoryData = $this.PackageConfig.packageCategories.$categoryName
            $packages = @()
            
            foreach ($pkg in $categoryData.packages) {
                $packageObj = @{
                    Name = $pkg.name
                    DisplayName = $pkg.displayName
                    Description = if ($pkg.description) { $pkg.description } else { "" }
                    Selected = $false  # 預設不選取
                    IsInstalled = $false
                    InstalledVersion = $null
                }
                
                # 處理額外的安裝參數
                if ($pkg.installArgs) {
                    $packageObj.Extra = $pkg.installArgs
                }
                
                # 處理安裝後執行的命令
                if ($pkg.postInstall) {
                    $packageObj.PostInstall = $pkg.postInstall
                }
                
                $packages += $packageObj
            }
            
            $this.PackageCategories[$categoryName] = $packages
        }
        
        Write-Host "成功載入配置文件，包含 $($this.PackageCategories.Count) 個分類" -ForegroundColor Green
    }
    
    
    # 取得已安裝的套件清單
    [array] GetInstalledPackages() {
        if (-not $this.IsInstalled) {
            return @()
        }
        
        try {
            $result = choco list --limit-output 2>$null
            $installedPackages = @()
            
            if ($result) {
                foreach ($line in $result) {
                    # 使用新格式: packagename|version
                    if ($line -match "^(.+?)\|(.+?)$") {
                        $packageName = $matches[1].Trim()
                        $version = $matches[2].Trim()
                        if ($packageName -ne "chocolatey") {
                            $installedPackages += @{
                                Name = $packageName
                                Version = $version
                            }
                        }
                    }
                }
            }
            
            return $installedPackages
        }
        catch {
            return @()
        }
    }
    
    # 更新套件的安裝狀態
    [void] UpdatePackageInstallationStatus() {
        Write-Host "正在檢查套件安裝狀態..." -ForegroundColor Yellow
        
        $installedPackages = $this.GetInstalledPackages()
        $installedNames = $installedPackages | ForEach-Object { $_.Name }
        
        foreach ($categoryName in $this.PackageCategories.Keys) {
            foreach ($package in $this.PackageCategories[$categoryName]) {
                $isCurrentlyInstalled = $installedNames -contains $package.Name
                $package.IsInstalled = $isCurrentlyInstalled
                
                if ($isCurrentlyInstalled) {
                    $installedPkg = $installedPackages | Where-Object { $_.Name -eq $package.Name }
                    $package.InstalledVersion = $installedPkg.Version
                } else {
                    # 清空未安裝套件的版本資訊
                    $package.InstalledVersion = $null
                }
            }
        }
        
        Write-Host "套件狀態檢查完成" -ForegroundColor Green
    }
    
    # 取得選定的套件
    [array] GetSelectedPackages() {
        $selected = @()
        foreach ($category in $this.PackageCategories.Keys) {
            foreach ($package in $this.PackageCategories[$category]) {
                if ($package.Selected) {
                    $selected += $package
                }
            }
        }
        return $selected
    }
    
    # 檢查特定套件是否已安裝
    [bool] TestPackageInstalled([string]$PackageName) {
        if (-not $this.IsInstalled) {
            return $false
        }
        
        try {
            $result = choco list --limit-output $PackageName 2>$null
            if ($result) {
                # 檢查是否有確切匹配
                foreach ($line in $result) {
                    if ($line -match "^$PackageName\|") {
                        return $true
                    }
                }
            }
            return $false
        }
        catch {
            return $false
        }
    }
    
    # 使用 choco export 匯出已安裝的套件清單
    [bool] ExportInstalledPackagesWithChoco([string]$outputPath, [bool]$includeVersions = $true) {
        if (-not $this.IsInstalled) {
            return $false
        }
        
        try {
            # 建構 choco export 命令
            $chocoArgs = "export --output-file-path=`"$outputPath`""
            if ($includeVersions) {
                $chocoArgs += " --include-version-numbers"
            }
            $chocoArgs += " -y"
            
            # 執行 choco export 命令
            $result = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
            
            return $result.ExitCode -eq 0
        }
        catch {
            return $false
        }
    }
    
    # 從 packages.config 檔案中讀取套件數量
    [int] GetPackageCountFromConfig([string]$configPath) {
        try {
            if (Test-Path $configPath) {
                [xml]$configXml = Get-Content $configPath -Encoding UTF8
                return $configXml.packages.package.Count
            }
            return 0
        }
        catch {
            return 0
        }
    }
}