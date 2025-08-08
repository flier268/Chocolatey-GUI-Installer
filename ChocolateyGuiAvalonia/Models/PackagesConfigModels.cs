using System.Collections.Generic;

namespace ChocolateyGuiAvalonia.Models;

public class PackagesConfigRoot
{
    public Dictionary<string, PackageCategory> PackageCategories { get; set; } = [];

    public PackagesConfigSettings Settings { get; set; } = new();
}

public class PackageCategory
{
    public string Description { get; set; } = string.Empty;

    public List<PackageModel> Packages { get; set; } = [];
}

public class PackagesConfigSettings
{
    public string Version { get; set; } = "1.0";

    public string DefaultChocolateyArgs { get; set; } = string.Empty;

    public bool RefreshEnvAfterInstall { get; set; }

    public bool ShowPackageDescriptions { get; set; }
}
