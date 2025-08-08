using System.Collections.Generic;
using System.Windows;

namespace ChocolateyGuiWpf
{
    public partial class PackageRestoreConfirmWindow : Window
    {
        public bool IsConfirmed { get; private set; } = false;

        public PackageRestoreConfirmWindow(IEnumerable<string> packageNames)
        {
            InitializeComponent();
            PackageDataGrid.ItemsSource = packageNames;
            ConfirmButton.Click += (s, e) => { IsConfirmed = true; this.DialogResult = true; };
            CancelButton.Click += (s, e) => { IsConfirmed = false; this.DialogResult = false; };
        }
    }
}