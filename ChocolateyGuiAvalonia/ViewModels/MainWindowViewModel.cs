using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using ChocolateyGuiAvalonia.Models;

namespace ChocolateyGuiAvalonia.ViewModels;

public class MainWindowViewModel : ViewModelBase
{
    public ObservableCollection<string> Categories { get; set; }
    public ObservableCollection<PackageModel> Packages { get; set; }
    public ObservableCollection<PackageModel> FilteredPackages { get; set; }
    public ChocolateyManager Manager { get; set; }

    public MainWindowViewModel()
    {
        Categories = [];
        Packages = [];
        FilteredPackages = [];
        Manager = new ChocolateyManager();

        string configPath = "packages-config.json";
        if (File.Exists(configPath))
        {
            var jsonText = File.ReadAllText(configPath);
            var configRoot = System.Text.Json.JsonSerializer.Deserialize(
                jsonText,
                PackagesConfigJsonContext.Default.PackagesConfigRoot
            );

            if (configRoot?.PackageCategories != null)
            {
                foreach (var kv in configRoot.PackageCategories)
                {
                    var catName = kv.Key;
                    Categories.Add(catName);

                    var pkgs = kv.Value.Packages;
                    foreach (var pkg in pkgs)
                    {
                        Packages.Add(
                            new PackageModel
                            {
                                Selected = false,
                                Name = pkg.Name,
                                DisplayName = pkg.DisplayName,
                                Description = pkg.Description,
                                Status = "",
                                Category = catName,
                            }
                        );
                    }
                }
            }
        }

        // 查詢安裝狀態與版本
        var names = Packages.Select(p => p.Name).ToList();
        var installedDict = Manager.GetInstalledPackages(names);
        foreach (var pkg in Packages)
        {
            if (installedDict.ContainsKey(pkg.Name) && installedDict[pkg.Name].Installed)
            {
                pkg.Status = string.IsNullOrEmpty(installedDict[pkg.Name].Version)
                    ? "已安裝"
                    : $"已安裝 v{installedDict[pkg.Name].Version}";
            }
            else
            {
                pkg.Status = "未安裝";
            }
        }

        // 預設顯示第一分類
        if (Categories.Count > 0)
        {
            FilterByCategory(Categories[0]);
        }
    }

    public void FilterByCategory(string category)
    {
        FilteredPackages.Clear();
        foreach (var pkg in Packages)
        {
            if (string.IsNullOrEmpty(category) || pkg.Category == category)
            {
                FilteredPackages.Add(pkg);
            }
        }
    }

    public void UpdatePackageStatus(string? category = null)
    {
        var names = Packages.Select(p => p.Name).ToList();
        var installedDict = Manager.GetInstalledPackages(names);
        foreach (var pkg in Packages)
        {
            if (installedDict.ContainsKey(pkg.Name) && installedDict[pkg.Name].Installed)
            {
                pkg.Status = string.IsNullOrEmpty(installedDict[pkg.Name].Version)
                    ? "已安裝"
                    : $"已安裝 v{installedDict[pkg.Name].Version}";
            }
            else
            {
                pkg.Status = "未安裝";
            }
        }
        if (!string.IsNullOrEmpty(category))
        {
            FilterByCategory(category);
        }
        else if (Categories.Count > 0)
        {
            FilterByCategory(Categories[0]);
        }
    }
}
