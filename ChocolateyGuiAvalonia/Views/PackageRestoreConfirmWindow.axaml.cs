using System.Collections.Generic;
using Avalonia.Controls;
using Avalonia.Interactivity;
using ChocolateyGuiAvalonia.Models;
using ChocolateyGuiAvalonia.ViewModels;

namespace ChocolateyGuiAvalonia.Views;

public partial class PackageRestoreConfirmWindow : Window
{
    public bool IsConfirmed { get; private set; } = false;

    public PackageRestoreConfirmWindow()
    {
        InitializeComponent();
    }

    public PackageRestoreConfirmWindow(IEnumerable<PackageModel> packageNames)
        : this()
    {
        DataContext = new PackageRestoreConfirmWindowViewModel(packageNames);
        var confirmButton = this.FindControl<Button>("ConfirmButton");
        if (confirmButton is not null)
        {
            confirmButton.Click += Confirm_Click;
        }
        var cancelButton = this.FindControl<Button>("CancelButton");
        if (cancelButton is not null)
        {
            cancelButton.Click += Cancel_Click;
        }
    }

    private void Confirm_Click(object? sender, RoutedEventArgs e)
    {
        IsConfirmed = true;
        Close(true);
    }

    private void Cancel_Click(object? sender, RoutedEventArgs e)
    {
        IsConfirmed = false;
        Close(false);
    }
}
