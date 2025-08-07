# 套件配置文件說明

## 📁 文件結構

`packages-config.json` 是軟體清單的配置文件，採用 JSON 格式定義所有可安裝的套件。

## 🔧 配置文件結構

### 基本格式
```json
{
  "packageCategories": {
    "分類名稱": {
      "description": "分類說明",
      "packages": [...]
    }
  },
  "settings": {...}
}
```

### 套件定義
每個套件包含以下屬性：

```json
{
  "name": "套件的Chocolatey名稱",
  "displayName": "顯示在GUI中的名稱",
  "description": "套件說明（選填）",
  "selected": true/false,
  "installArgs": "額外的安裝參數（選填）",
  "postInstall": [
    {
      "command": "要執行的命令",
      "description": "命令說明"
    }
  ]
}
```

## 📝 屬性說明

| 屬性 | 必填 | 說明 | 範例 |
|------|------|------|------|
| `name` | ✅ | Chocolatey套件名稱 | `"notepadplusplus"` |
| `displayName` | ✅ | GUI顯示名稱 | `"Notepad++"` |
| `description` | ❌ | 套件描述 | `"功能強大的文字編輯器"` |
| `selected` | ✅ | 預設是否選取 | `true` or `false` |
| `installArgs` | ❌ | 安裝參數 | `"--ignorechecksum"` |
| `postInstall` | ❌ | 安裝後執行的命令 | 見下方範例 |

## 🔄 PostInstall 範例

```json
{
  "name": "nodejs-lts",
  "displayName": "Node.js LTS",
  "selected": false,
  "postInstall": [
    {
      "command": "npm install -g @angular/cli",
      "description": "安裝Angular CLI"
    },
    {
      "command": "npm install -g typescript",
      "description": "安裝TypeScript"
    }
  ]
}
```

## ⚙️ 設定選項

```json
{
  "settings": {
    "version": "1.0",
    "defaultChocolateyArgs": "-y",
    "refreshEnvAfterInstall": true,
    "showPackageDescriptions": true
  }
}
```

| 設定 | 說明 | 預設值 |
|------|------|--------|
| `version` | 配置文件版本 | `"1.0"` |
| `defaultChocolateyArgs` | 預設Chocolatey參數 | `"-y"` |
| `refreshEnvAfterInstall` | 安裝後重新整理環境變數 | `true` |
| `showPackageDescriptions` | 在GUI中顯示套件描述 | `true` |

## 📂 新增分類

要新增套件分類，在 `packageCategories` 中新增：

```json
"新分類名稱": {
  "description": "分類說明",
  "packages": [
    {
      "name": "套件名稱",
      "displayName": "顯示名稱",
      "selected": false
    }
  ]
}
```

## 📦 新增套件

在現有分類的 `packages` 陣列中新增：

```json
{
  "name": "新套件名稱",
  "displayName": "新套件顯示名稱",
  "description": "套件說明",
  "selected": false
}
```

## 🔍 尋找套件名稱

1. 訪問 [Chocolatey 套件庫](https://community.chocolatey.org/packages)
2. 搜尋您要的軟體
3. 使用套件頁面中的確切名稱

## ⚠️ 注意事項

1. **JSON語法正確性**：確保JSON格式正確，注意逗號和引號
2. **套件名稱**：使用Chocolatey官方的套件名稱
3. **編碼格式**：文件需要使用UTF-8編碼
4. **備份文件**：修改前建議備份原始文件

## 🔄 重新載入配置

修改配置文件後：
1. 重新啟動GUI安裝器
2. 新的配置會自動載入
3. 如果配置文件有錯誤，會使用內建的備用清單

## 💡 最佳實踐

1. **分類明確**：將相關軟體歸類到適當的分類
2. **描述清楚**：提供有意義的套件描述
3. **預設選擇**：常用工具設為預設選取
4. **測試安裝**：新增套件後先測試安裝是否正常

## 🛠️ 故障排除

### 配置文件載入失敗
- 檢查JSON語法是否正確
- 確認文件編碼為UTF-8
- 查看控制台錯誤訊息

### 套件安裝失敗
- 確認套件名稱正確
- 檢查是否需要特殊安裝參數
- 查看Chocolatey官方文檔

### GUI顯示異常
- 確認displayName不包含特殊字元
- 檢查description長度是否過長