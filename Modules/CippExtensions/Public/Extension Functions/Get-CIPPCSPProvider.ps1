function Get-CIPPCSPProvider {
    <#
    .FUNCTIONALITY
        Internal
    .DESCRIPTION
        Returns which CSP integration serves licence purchases: 'ExternalCSP' when it is enabled and its
        feature flag is on, otherwise 'Sherweb'. Saving the extension config refuses to enable both.
    #>
    [CmdletBinding()]
    param()
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Config = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json
    if ($Config.ExternalCSP.Enabled -eq $true -and (Get-CIPPFeatureFlag -Id 'ExternalCSP').Enabled -eq $true) { 'ExternalCSP' } else { 'Sherweb' }
}
