function ConvertTo-CippPermissionRules {
    <#
    .SYNOPSIS
        Convert a legacy flat permission map to include/exclude rules.
    .DESCRIPTION
        A concrete permission string is a -like pattern that matches only itself, so
        Include = the explicit non-None values is a behavior-preserving conversion.
    .PARAMETER Permissions
        The stored Permissions value: JSON string or object map of key -> 'Cat.Obj.Level'.
    .EXAMPLE
        ConvertTo-CippPermissionRules -Permissions $Role.Permissions
    #>
    [CmdletBinding()]
    param($Permissions)

    if ($Permissions -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Permissions)) {
            $Permissions = $null
        } else {
            try {
                $Permissions = $Permissions | ConvertFrom-Json
            } catch {
                Write-Warning "ConvertTo-CippPermissionRules: could not parse permissions: $($_.Exception.Message)"
                $Permissions = $null
            }
        }
    }

    $Include = [System.Collections.Generic.List[string]]::new()
    if ($Permissions) {
        foreach ($Value in $Permissions.PSObject.Properties.Value) {
            if ($Value -is [string] -and $Value -ne '' -and $Value -notmatch '\.None$' -and $Include -notcontains $Value) {
                $Include.Add($Value)
            }
        }
    }

    [PSCustomObject]@{
        Include = @($Include | Sort-Object)
        Exclude = @()
    }
}
