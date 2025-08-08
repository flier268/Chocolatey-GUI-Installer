using CommunityToolkit.Mvvm.ComponentModel;

namespace ChocolateyGuiAvalonia.Models;

public partial class PackageModel : ObservableObject
{
    [ObservableProperty]
    public partial bool Selected { get; set; }

    [ObservableProperty]
    public partial string Name { get; set; }

    [ObservableProperty]
    public partial string DisplayName { get; set; }

    [ObservableProperty]
    public partial string Description { get; set; }

    [ObservableProperty]
    public partial string Status { get; set; }

    [ObservableProperty]
    public partial string Category { get; set; }
}
