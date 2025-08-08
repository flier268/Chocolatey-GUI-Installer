using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Threading;
using ChocolateyGuiAvalonia.ViewModels;

namespace ChocolateyGuiAvalonia.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }

    private void CategoryListBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var vm = DataContext as MainWindowViewModel;
        var selectedCategory = CategoryListBox?.SelectedItem as string ?? "";
        vm?.FilterByCategory(selectedCategory);
    }

    private async void InstallButton_Click(object sender, RoutedEventArgs e)
    {
        var vm = DataContext as MainWindowViewModel;
        var pkgs = vm?.Packages.Where(p => p.Selected).ToList();
        if (pkgs == null || pkgs.Count == 0)
        {
            await ShowMessageAsync("請先勾選要安裝的套件！");
            return;
        }
        var progressBar = this.FindControl<ProgressBar>("InstallProgressBar");
        var logBox = this.FindControl<TextBox>("LogTextBox");
        if (logBox == null || progressBar == null)
        {
            await ShowMessageAsync("無法找到日誌或進度條控件！");
            return;
        }
        int total = pkgs.Count;
        progressBar.Value = 0;
        for (int i = 0; i < total; i++)
        {
            var pkg = pkgs[i];
            await RunChocoCommandAsync(
                $"install {pkg.Name} -y",
                $"安裝 {pkg.DisplayName} ({i + 1}/{total})...",
                i + 1,
                total,
                logBox,
                progressBar
            );
        }
        var listBox = this.FindControl<ListBox>("CategoryListBox");
        var selectedCategory = listBox?.SelectedItem as string ?? "";
        vm?.UpdatePackageStatus(selectedCategory);
    }

    private async void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        var vm = DataContext as MainWindowViewModel;
        var pkgs = vm?.Packages.Where(p => p.Selected).ToList();
        if (pkgs == null || pkgs.Count == 0)
        {
            await ShowMessageAsync("請先勾選要移除的套件！");
            return;
        }
        var progressBar = this.FindControl<ProgressBar>("InstallProgressBar");
        var logBox = this.FindControl<TextBox>("LogTextBox");
        if (progressBar == null || logBox == null)
        {
            await ShowMessageAsync("無法找到日誌或進度條控件！");
            return;
        }
        int total = pkgs.Count;
        progressBar.Value = 0;
        for (int i = 0; i < total; i++)
        {
            var pkg = pkgs[i];
            await RunChocoCommandAsync(
                $"uninstall {pkg.Name} -x -y",
                $"移除 {pkg.DisplayName} ({i + 1}/{total})...",
                i + 1,
                total,
                logBox,
                progressBar
            );
        }
        var listBox = this.FindControl<ListBox>("CategoryListBox");
        var selectedCategory = listBox?.SelectedItem as string ?? "";
        vm?.UpdatePackageStatus(selectedCategory);
    }

    private void RefreshStatusButton_Click(object sender, RoutedEventArgs e)
    {
        var vm = DataContext as MainWindowViewModel;
        var selectedCategory = CategoryListBox?.SelectedItem as string ?? "";
        vm?.UpdatePackageStatus(selectedCategory);
    }

    private async void BackupButton_Click(object sender, RoutedEventArgs e)
    {
        var filePath = await StorageProvider.SaveFilePickerAsync(
            new Avalonia.Platform.Storage.FilePickerSaveOptions()
            {
                FileTypeChoices =
                [
                    new Avalonia.Platform.Storage.FilePickerFileType("Chocolatey 套件配置")
                    {
                        Patterns = ["*.config"],
                    },
                ],
            }
        );
        if (filePath is not null)
        {
            var logBox = this.FindControl<TextBox>("LogTextBox");
            if (logBox == null)
            {
                await ShowMessageAsync("無法找到日誌控件！");
                return;
            }
            logBox.Text += $"開始備份到 {filePath.Path.AbsolutePath}\n";
            await RunChocoCommandAsync(
                $"export \"{filePath.Path.AbsolutePath}\"",
                $"備份",
                1,
                1,
                logBox,
                null
            );
            await ShowMessageAsync("備份完成");
        }
    }

    private async void RestoreButton_Click(object sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(
            new Avalonia.Platform.Storage.FilePickerOpenOptions()
            {
                FileTypeFilter =
                [
                    new Avalonia.Platform.Storage.FilePickerFileType("Chocolatey 套件配置")
                    {
                        Patterns = ["*.config"],
                    },
                ],
                AllowMultiple = false,
            }
        );
        if (files != null && files.Count > 0)
        {
            var configPath = files[0];
            // 讀取 config 取得套件名稱
            var packageNames = new List<string>();
            using var reader = new StreamReader(await configPath.OpenReadAsync());
            while (!reader.EndOfStream)
            {
                var line = reader.ReadLine();
                if (line is null)
                    continue;

                var trimmed = line.Trim();
                if (trimmed.StartsWith("<package "))
                {
                    var nameAttr = "id=\"";
                    var start = trimmed.IndexOf(nameAttr);
                    if (start >= 0)
                    {
                        start += nameAttr.Length;
                        var end = trimmed.IndexOf("\"", start);
                        if (end > start)
                        {
                            var name = trimmed.Substring(start, end - start);
                            if (!string.IsNullOrEmpty(name))
                                packageNames.Add(name);
                        }
                    }
                }
            }
            reader.Close();

            var packageModels = packageNames
                .Select(n => new ChocolateyGuiAvalonia.Models.PackageModel { Name = n })
                .ToList();
            var confirmWindow = new PackageRestoreConfirmWindow(packageModels);
            var result = await confirmWindow.ShowDialog<bool>(this);
            if (result)
            {
                var logBox = this.FindControl<TextBox>("LogTextBox")!;
                logBox.Text += $"開始還原自 {configPath.Path.AbsolutePath}\n";
                await RunChocoCommandAsync(
                    $"install \"{configPath.Path.AbsolutePath}\" -y",
                    $"還原",
                    1,
                    1,
                    logBox,
                    null
                );
                await ShowMessageAsync("還原完成");
                var vm = DataContext as MainWindowViewModel;
                var selectedCategory = CategoryListBox?.SelectedItem as string ?? "";
                vm?.UpdatePackageStatus(selectedCategory);
            }
        }
    }

    private async Task RunChocoCommandAsync(
        string args,
        string logPrefix,
        int current,
        int total,
        TextBox logBox,
        ProgressBar? progressBar
    )
    {
        await Task.Run(async () =>
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "choco",
                Arguments = args,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            var process = System.Diagnostics.Process.Start(psi);
            if (process == null)
            {
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    logBox.Text += $"{logPrefix} 執行失敗，請確認 Chocolatey 是否已安裝。\n";
                    logBox.CaretIndex = logBox.Text.Length;
                });
                return;
            }

            // 非同步讀取標準輸出
            string? lastLog = string.Empty;
            while (!process.StandardOutput.EndOfStream)
            {
                var line = await process.StandardOutput.ReadLineAsync();
                if (lastLog != line)
                {
                    lastLog = line;
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        logBox.Text += $"{line}\n";
                        logBox.CaretIndex = logBox.Text.Length;
                    });
                }
            }
            // 非同步讀取標準錯誤
            while (!process.StandardError.EndOfStream)
            {
                var line = await process.StandardError.ReadLineAsync();
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    logBox.Text += $"{line}\n";
                    logBox.CaretIndex = logBox.Text.Length;
                });
            }
            process.WaitForExit();
            await Dispatcher.UIThread.InvokeAsync(() =>
            {
                logBox.Text += $"{logPrefix} 完成\n";
                logBox.CaretIndex = logBox.Text.Length;
                if (progressBar != null)
                    progressBar.Value = (current * 100) / total;
            });
        });
    }

    private async Task ShowMessageAsync(string message)
    {
        var dialog = new Window
        {
            Width = 300,
            Height = 150,
            Content = new TextBlock
            {
                Text = message,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
            },
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
        };
        await dialog.ShowDialog(this);
    }
}
