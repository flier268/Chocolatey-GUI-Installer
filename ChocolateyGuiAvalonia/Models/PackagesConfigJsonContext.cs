using System.Text.Json.Serialization;

namespace ChocolateyGuiAvalonia.Models;

[JsonSerializable(typeof(PackagesConfigRoot))]
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNameCaseInsensitive = true)]
public partial class PackagesConfigJsonContext : JsonSerializerContext { }
