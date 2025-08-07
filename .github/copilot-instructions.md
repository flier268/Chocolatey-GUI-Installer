# Chocolatey-GUI-Installer AI 指南

## 專案架構
- 主要以 PowerShell 5.1+ 開發，採用 Windows Forms GUI。
- 核心檔案：
  - `Chocolatey-GUI-Installer.ps1`：主程式，負責 GUI、權限檢查、流程控制。
  - `ChocolateyManager.ps1`：類別，負責套件分類、狀態檢查、匯出/匯入等邏輯。
  - `packages-config.json`：所有可安裝軟體的配置，分類明確，支援自訂參數與安裝後命令。
  - `Update-PackageConfig.ps1`：自動補齊配置檔 selected 屬性，確保一致性。
  - `packages-config-guide.md`：配置檔格式與屬性說明。

## 關鍵開發流程
- **執行/測試**：
  - 直接執行 `Chocolatey-GUI-Installer.ps1`，自動檢查管理員權限並提升。
  - 若遇執行策略問題，先執行：
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```
- **配置檔管理**：
  - 所有軟體清單與分類皆在 `packages-config.json`，新增/移除軟體只需編輯此檔。
  - 每個 package 支援 `installArgs`（安裝參數）、`postInstall`（安裝後命令）。
  - 執行 `Update-PackageConfig.ps1` 可自動補齊 selected 屬性。
- **匯出/匯入**：
  - 匯出：GUI 會呼叫 `choco export` 產生標準 `packages.config`（XML），包含所有已安裝套件與版本。
  - 匯入：GUI 會呼叫 `choco install packages.config` 批量安裝。

## 重要設計模式
- **模組化**：所有套件管理邏輯集中於 `ChocolateyManager.ps1` 類別，主程式只負責 UI 與流程。
- **非阻塞 UI**：所有安裝/移除操作皆以異步執行，確保 GUI 響應。
- **狀態同步**：安裝/移除後自動更新狀態，並即時顯示於 UI。
- **錯誤處理**：所有命令執行皆捕獲例外，並於日誌區域顯示詳細錯誤。

## 專案慣例
- 所有 PowerShell 檔案皆以 UTF-8 編碼。
- 配置檔案（JSON/XML）需保持語法正確，建議修改前先備份。
- 軟體分類、描述、顯示名稱皆需明確，利於使用者選擇。
- 主要命令皆透過 `choco` CLI 執行，確保與官方工具相容。

## 典型範例
- 新增套件：
  ```json
  {
    "name": "notepadplusplus",
    "displayName": "Notepad++",
    "description": "功能強大的文字編輯器",
    "selected": false,
    "installArgs": "--ignorechecksum",
    "postInstall": [
      { "command": "echo Done", "description": "安裝完成提示" }
    ]
  }
  ```
- 匯出已安裝套件：
  - 點擊「匯出清單」→ 產生 `packages.config`（XML），格式如下：
    ```xml
    <packages>
      <package id="vscode" version="1.85.1" />
      <package id="git" version="2.43.0" />
    </packages>
    ```

## 外部相依
- 依賴 Chocolatey 官方 CLI 工具（需網路連線）。
- 所有套件皆來自 Chocolatey 官方倉庫。

## 常見問題
- 執行策略錯誤：請先設定執行策略。
- 權限不足：請以管理員身份執行 PowerShell。
- 配置檔錯誤：檢查 JSON/XML 語法與編碼。

---
如有不清楚或遺漏之處，請回饋以便補充完善。
