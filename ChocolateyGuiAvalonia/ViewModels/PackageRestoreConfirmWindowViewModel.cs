using System.Collections.Generic;
using ChocolateyGuiAvalonia.Models;

namespace ChocolateyGuiAvalonia.ViewModels;

public class PackageRestoreConfirmWindowViewModel
{
    public IEnumerable<PackageModel> Packages { get; }

    public PackageRestoreConfirmWindowViewModel(IEnumerable<PackageModel> packages)
    {
        Packages = packages;
    }
}
