function Get-CIPPMicrosoftFirstPartyApp {
    <#
    .SYNOPSIS
        Resolves Microsoft first-party application ids to display names.
    .DESCRIPTION
        Single source for the Microsoft first-party application list in Config/MicrosoftFirstPartyApps.json.
        Without -AppId the whole table is returned as a hashtable keyed by lower-case application id. With
        -AppId the display name is returned, or $null when the id is not a known Microsoft application.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$AppId
    )

    if ($null -eq $script:CIPPMicrosoftFirstPartyApps) {
        $Table = @{}
        $Path = Join-Path $env:CIPPRootPath 'Config\MicrosoftFirstPartyApps.json'
        try {
            $Json = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
            foreach ($Property in $Json.PSObject.Properties) { $Table["$($Property.Name)".ToLowerInvariant()] = "$($Property.Value)" }
        } catch {
            Write-Information "Get-CIPPMicrosoftFirstPartyApp: could not load $Path - $($_.Exception.Message)"
        }
        $script:CIPPMicrosoftFirstPartyApps = $Table
    }

    if ($PSBoundParameters.ContainsKey('AppId')) {
        if ([string]::IsNullOrWhiteSpace($AppId)) { return $null }
        return $script:CIPPMicrosoftFirstPartyApps["$AppId".Trim().ToLowerInvariant()]
    }
    $script:CIPPMicrosoftFirstPartyApps
}
