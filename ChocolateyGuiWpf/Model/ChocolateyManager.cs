using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace ChocolateyGuiWpf.Model
{
    public class ChocolateyManager
    {
        public bool IsInstalled => TestChocolateyInstalled();

        public bool TestChocolateyInstalled()
        {
            var psi = new ProcessStartInfo
            {
                FileName = "choco",
                Arguments = "--version",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            try
            {
                var process = Process.Start(psi);
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                return !string.IsNullOrWhiteSpace(output);
            }
            catch
            {
                return false;
            }
        }

        public bool InstallChocolatey(Action<string> log)
        {
            try
            {
                log("開始安裝 Chocolatey...");
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))\"",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var process = Process.Start(psi);
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                log(output);
                log(error);
                return TestChocolateyInstalled();
            }
            catch (Exception ex)
            {
                log($"安裝失敗：{ex.Message}");
                return false;
            }
        }

        public Dictionary<string, (bool Installed, string Version)> GetInstalledPackages(List<string> packageNames)
        {
            var result = new Dictionary<string, (bool, string)>();
            var psi = new ProcessStartInfo
            {
                FileName = "choco",
                Arguments = $"list",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            try
            {
                var process = Process.Start(psi);
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                var lines = output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                foreach (var name in packageNames)
                {
                    var found = lines.FirstOrDefault(l => l.StartsWith(name + " ", StringComparison.OrdinalIgnoreCase));
                    if (found != null)
                    {
                        var parts = found.Split(' ');
                        result[name] = (true, parts.Length > 1 ? parts[1] : "");
                    }
                    else
                    {
                        result[name] = (false, "");
                    }
                }
            }
            catch
            {
                foreach (var name in packageNames)
                {
                    result[name] = (false, "");
                }
            }
            return result;
        }

        public bool InstallPackage(string name, string extraArgs, Action<string> log)
        {
            string args = $"install {name} -y {extraArgs}".Trim();
            return RunChoco(args, log);
        }

        public bool UninstallPackage(string name, string extraArgs, Action<string> log)
        {
            string args = $"uninstall {name} -x -y {extraArgs}".Trim();
            return RunChoco(args, log);
        }

        public bool UpgradePackage(string name, string extraArgs, Action<string> log)
        {
            string args = $"upgrade {name} -y {extraArgs}".Trim();
            return RunChoco(args, log);
        }

        public bool ExportPackages(string filePath, Action<string> log)
        {
            string args = $"export \"{filePath}\"";
            return RunChoco(args, log);
        }

        public bool ImportPackages(string filePath, Action<string> log)
        {
            string args = $"install \"{filePath}\" -y";
            return RunChoco(args, log);
        }

        private bool RunChoco(string args, Action<string> log)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "choco",
                    Arguments = args,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var process = Process.Start(psi);
                string output = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                log(output);
                log(error);
                return process.ExitCode == 0;
            }
            catch (Exception ex)
            {
                log($"choco 指令失敗：{ex.Message}");
                return false;
            }
        }
    }
}