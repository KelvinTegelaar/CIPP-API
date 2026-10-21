function Get-CippExtensionCulture {
    <#
        .SYNOPSIS
        Resolves an extension's locale setting to a culture for date and number formatting.

        .PARAMETER Value
        A LocaleSelect value ({ label; value }) or a culture name. Empty or unknown names fall back to en-GB.
    #>
    param([AllowNull()][object]$Value)
    $Name = if ($null -ne $Value.value) { [string]$Value.value } else { [string]$Value }
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        try { return [cultureinfo]::GetCultureInfo($Name.Trim(), $true) } catch { }
    }
    [cultureinfo]::GetCultureInfo('en-GB')
}
