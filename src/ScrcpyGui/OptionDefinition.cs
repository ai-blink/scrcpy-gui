namespace ScrcpyGui;

public enum OptionKind
{
    Check,
    Text,
    Combo,
    EditableCombo,
    PhonePreference,
    Path,
}

public sealed record OptionDefinition(
    string Group,
    string Key,
    string Label,
    OptionKind Kind,
    string Argument = "",
    string DefaultText = "",
    bool DefaultChecked = false,
    IReadOnlyList<string>? Items = null,
    string Hint = "",
    string? SettingNamespace = null,
    string? SettingKey = null);
