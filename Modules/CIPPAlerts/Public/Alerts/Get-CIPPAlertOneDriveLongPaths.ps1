function Get-CIPPAlertOneDriveLongPaths {
    <#
    .FUNCTIONALITY
        Entrypoint
    .SYNOPSIS
        Alert on OneDrive accounts with over-long path counts from the Report DB cache.

    .DESCRIPTION
        Reads OneDriveLongPaths cache only (no live crawl). Requires a prior
        ExecCIPPDBCache?Name=OneDriveLongPaths run. Alert text includes owner UPN and
        counts only — never file or folder names.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $HasSharePoint = Test-CIPPStandardLicense -StandardName 'OneDriveLongPaths' -TenantFilter $TenantFilter -Preset SharePoint
    if (-not $HasSharePoint) {
        return
    }

    try {
        $MinCount = 1
        if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
            $Raw = $InputValue.OneDriveLongPaths ?? $InputValue.MinCount ?? $InputValue
            if ($null -ne $Raw -and "$Raw" -ne '') {
                $Parsed = 0
                if ([int]::TryParse("$Raw", [ref]$Parsed) -and $Parsed -gt 0) {
                    $MinCount = $Parsed
                }
            }
        } elseif ($null -ne $InputValue -and "$InputValue" -ne '') {
            $Parsed = 0
            if ([int]::TryParse("$InputValue", [ref]$Parsed) -and $Parsed -gt 0) {
                $MinCount = $Parsed
            }
        }

        $Rows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OneDriveLongPaths')
        if (-not $Rows) {
            return
        }

        $AlertData = foreach ($Row in $Rows) {
            $Upn = [string]($Row.ownerPrincipalName ?? $Row.id)
            if ([string]::IsNullOrWhiteSpace($Upn)) { continue }

            $Count260 = 0
            $Count400 = 0
            if ($null -ne $Row.countOver260) { [void][int]::TryParse("$($Row.countOver260)", [ref]$Count260) }
            if ($null -ne $Row.countOver400) { [void][int]::TryParse("$($Row.countOver400)", [ref]$Count400) }

            if ($Count260 -lt $MinCount) { continue }

            [PSCustomObject]@{
                Message              = "${Upn}: $Count260 OneDrive paths may exceed Windows 260-character path limit when synced ($Count400 over cloud 400 limit)."
                Id                   = $Upn
                ownerPrincipalName   = $Upn
                countOver260         = $Count260
                countOver400         = $Count400
                Tenant               = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "OneDrive long paths alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
