using System.Collections.Generic;
using System.Linq;
using System.Security.Principal;
using System.Windows;
using System.Windows.Documents;

namespace ChocolateyGuiWpf
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            this.DataContext = new ViewModel.MainViewModel();

            if (!IsAdministrator())
            {
                var exeName = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
                var psi = new System.Diagnostics.ProcessStartInfo(exeName)
                {
                    UseShellExecute = true,
                    Verb = "runas"
                };
                try
                {
                    System.Diagnostics.Process.Start(psi);
                }
                catch
                {
                    MessageBox.Show("無法自動提升權限，請手動以管理員執行。", "權限不足", MessageBoxButton.OK, MessageBoxImage.Error);
                }
                Application.Current.Shutdown();
            }
        }

        private bool IsAdministrator()
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        private void CategoryListBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            var vm = this.DataContext as ViewModel.MainViewModel;
            var selectedCategory = (string)(CategoryListBox.SelectedItem ?? "");
            vm.FilterByCategory(selectedCategory);
        }

        private async void InstallButton_Click(object sender, RoutedEventArgs e)
        {
            var vm = this.DataContext as ViewModel.MainViewModel;
            var selectedPkgs = vm.Packages.Where(p => p.Selected).ToList();
            if (selectedPkgs.Count == 0)
            {
                MessageBox.Show("請先勾選要安裝的套件！", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            int total = selectedPkgs.Count;
            InstallProgressBar.Value = 0;
            for (int i = 0; i < total; i++)
            {
                var pkg = selectedPkgs[i];
                string args = $"install {pkg.Name} -y";
                await RunChocoCommandAsync(args, $"安裝 {pkg.DisplayName} ({i + 1}/{total})...", i + 1, total);
            }
            // 安裝後更新狀態
            var selectedCategory = (string)(CategoryListBox.SelectedItem ?? "");
            vm.UpdatePackageStatus(selectedCategory);
        }

        private async void RemoveButton_Click(object sender, RoutedEventArgs e)
        {
            var vm = this.DataContext as ViewModel.MainViewModel;
            var selectedPkgs = vm.Packages.Where(p => p.Selected).ToList();
            if (selectedPkgs.Count == 0)
            {
                MessageBox.Show("請先勾選要移除的套件！", "提示", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            int total = selectedPkgs.Count;
            InstallProgressBar.Value = 0;
            for (int i = 0; i < total; i++)
            {
                var pkg = selectedPkgs[i];
                string args = $"uninstall {pkg.Name} -x -y";
                await RunChocoCommandAsync(args, $"移除 {pkg.DisplayName} ({i + 1}/{total})...", i + 1, total);
            }
        }

        private async System.Threading.Tasks.Task RunChocoCommandAsync(string args, string logPrefix, int current, int total)
        {
            await System.Threading.Tasks.Task.Run(() =>
            {
                var psi = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "choco",
                    Arguments = args,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var process = System.Diagnostics.Process.Start(psi);
                while (!process.StandardOutput.EndOfStream)
                {
                    var line = process.StandardOutput.ReadLine();
                    Dispatcher.Invoke(() =>
                    {
                        LogTextBox.AppendText($"{line}\n");
                        LogTextBox.ScrollToEnd();
                    });
                }
                while (!process.StandardError.EndOfStream)
                {
                    var line = process.StandardError.ReadLine();
                    Dispatcher.Invoke(() =>
                    {
                        LogTextBox.AppendText($"{line}\n");
                        LogTextBox.ScrollToEnd();
                    });
                }
                process.WaitForExit();
                Dispatcher.Invoke(() =>
                {
                    LogTextBox.AppendText($"{logPrefix} 完成\n");
                    LogTextBox.ScrollToEnd();
                    InstallProgressBar.Value = (current * 100) / total;
                });
            });
            // 狀態即時更新
            var vm = this.DataContext as ViewModel.MainViewModel;
            var selectedCategory = (string)(CategoryListBox.SelectedItem ?? "");
            vm.UpdatePackageStatus(selectedCategory);
        }
        // 手動更新狀態
        private void RefreshStatusButton_Click(object sender, RoutedEventArgs e)
        {
            var vm = this.DataContext as ViewModel.MainViewModel;
            var selectedCategory = (string)(CategoryListBox.SelectedItem ?? "");
            vm.UpdatePackageStatus(selectedCategory);
        }

        // 備份
        private async void BackupButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new Microsoft.Win32.SaveFileDialog
            {
                Filter = "Chocolatey 套件配置 (*.config)|*.config",
                FileName = $"packages-{System.DateTime.Now:yyyyMMdd-HHmmss}.config"
            };
            if (dialog.ShowDialog() == true)
            {
                LogTextBox.AppendText($"開始備份到 {dialog.FileName}\n");
                LogTextBox.ScrollToEnd();
                await RunChocoCommandAsync($"export \"{dialog.FileName}\"", $"備份", 1, 1);
                MessageBox.Show("備份完成", "備份", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        // 還原
        private async void RestoreButton_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Filter = "Chocolatey 套件配置 (*.config)|*.config"
            };
            if (dialog.ShowDialog() == true)
            {
                var configPath = dialog.FileName;
                List<string> pkgs = new List<string>();
                try
                {
                    var xml = System.Xml.Linq.XDocument.Load(configPath);
                    pkgs = xml.Descendants("package").Select(x => x.Attribute("id")?.Value).Where(x => !string.IsNullOrEmpty(x)).ToList();
                }
                catch
                {
                    pkgs.Clear();
                }
                var confirmWindow = new PackageRestoreConfirmWindow(pkgs);
                confirmWindow.Owner = this;
                var result = confirmWindow.ShowDialog();
                if (result == true && confirmWindow.IsConfirmed)
                {
                    LogTextBox.AppendText($"開始還原自 {configPath}\n");
                    LogTextBox.ScrollToEnd();
                    await RunChocoCommandAsync($"install \"{configPath}\" -y", $"還原", 1, 1);
                    MessageBox.Show("還原完成", "還原", MessageBoxButton.OK, MessageBoxImage.Information);
                    var vm = this.DataContext as ViewModel.MainViewModel;
                    var selectedCategory = (string)(CategoryListBox.SelectedItem ?? "");
                    vm.UpdatePackageStatus(selectedCategory);
                }
            }
        }
    }
}