function Get-CIPPBaselineSpoofWarnState {
    <#
    .SYNOPSIS
        Prepare hook for SpoofWarn: the external sender warning and its allow list.
    .DESCRIPTION
        The allow list is add-only, matching the classic and the remediation (an Add edit):
        every configured entry must be present, and entries added outside the baseline are
        left alone. Current carries only the configured entries the tenant actually has, so a
        missing one grades as drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Config = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoExternalInOutlook')[0]
    if (-not $Config) { return @{ Current = $null } }

    $Configured = @(@($Item.Variables.allowListAdd) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
    $Present = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($Config.AllowList) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)

    @{
        Expected = [PSCustomObject]@{
            Enabled   = [bool]($Item.Variables.externalWarningEnabled -eq $true)
            AllowList = $Configured
        }
        Current  = [PSCustomObject]@{
            Enabled   = [bool]$Config.Enabled
            AllowList = @($Configured.Where({ $Present.Contains($_) }))
        }
    }
}
