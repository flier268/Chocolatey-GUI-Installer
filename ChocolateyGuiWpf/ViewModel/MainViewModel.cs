using System.Collections.ObjectModel;
using ChocolateyGuiWpf.Model;
using System.IO;
using Newtonsoft.Json.Linq;
using System.Linq;

namespace ChocolateyGuiWpf.ViewModel
{
    public class MainViewModel
    {
        public ObservableCollection<string> Categories { get; set; }
        public ObservableCollection<PackageModel> Packages { get; set; }
        public ObservableCollection<PackageModel> FilteredPackages { get; set; }
        public ChocolateyManager Manager { get; set; }

        public MainViewModel()
        {
            Categories = new ObservableCollection<string>();
            Packages = new ObservableCollection<PackageModel>();
            FilteredPackages = new ObservableCollection<PackageModel>();
            Manager = new ChocolateyManager();

            string configPath = "packages-config.json";
            if (File.Exists(configPath))
            {
                var json = JObject.Parse(File.ReadAllText(configPath));
                var categories = json["packageCategories"];
                foreach (var cat in categories)
                {
                    var catName = ((JProperty)cat).Name;
                    Categories.Add(catName);

                    var pkgs = cat.First["packages"];
                    foreach (var pkg in pkgs)
                    {
                        Packages.Add(new PackageModel
                        {
                            Selected = false,
                            Name = pkg["name"]?.ToString(),
                            DisplayName = pkg["displayName"]?.ToString(),
                            Description = pkg["description"]?.ToString(),
                            Status = "",
                            Category = catName
                        });
                    }
                }
            }

            // 查詢安裝狀態與版本
            var names = Packages.Select(p => p.Name).ToList();
            var installedDict = Manager.GetInstalledPackages(names);
            foreach (var pkg in Packages)
            {
                if (installedDict.ContainsKey(pkg.Name) && installedDict[pkg.Name].Item1)
                {
                    pkg.Status = string.IsNullOrEmpty(installedDict[pkg.Name].Item2)
                        ? "已安裝"
                        : $"已安裝 v{installedDict[pkg.Name].Item2}";
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
                // 直接比對 Category 屬性
                if (string.IsNullOrEmpty(category) || pkg.Category == category)
                {
                    FilteredPackages.Add(pkg);
                }
            }
        }
        public void UpdatePackageStatus(string category = null)
        {
            var names = Packages.Select(p => p.Name).ToList();
            var installedDict = Manager.GetInstalledPackages(names);
            foreach (var pkg in Packages)
            {
                if (installedDict.ContainsKey(pkg.Name) && installedDict[pkg.Name].Item1)
                {
                    pkg.Status = string.IsNullOrEmpty(installedDict[pkg.Name].Item2)
                        ? "已安裝"
                        : $"已安裝 v{installedDict[pkg.Name].Item2}";
                }
                else
                {
                    pkg.Status = "未安裝";
                }
            }
            // 重新套用分類篩選，維持原本選取的分類
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
}