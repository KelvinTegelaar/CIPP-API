function Get-CIPPBaselineExpiryPolicy {
    <#
    .SYNOPSIS
        The instance-wide expiry policy for accepted deviations and tenant overrides.
    .DESCRIPTION
        defaultDays pre-fills the expiry of a new acceptance or override; maxDays is the furthest
        away an expiry may be. 0 means no default or no maximum.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Table = Get-CIPPTable -TableName Config
    $Settings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'BaselineExpiry' and RowKey eq 'Settings'"
    [PSCustomObject]@{
        defaultDays = [int]($Settings.defaultDays -as [int])
        maxDays     = [int]($Settings.maxDays -as [int])
    }
}
