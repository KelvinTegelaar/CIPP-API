function Invoke-CIPPBaselineMFAPushApps {
    <#
    .SYNOPSIS
        MFAPushApps executor: enables or disables the Azure Multi-Factor Auth Client and
        Connector service principals.
    .DESCRIPTION
        One PATCH per app against the appId-addressed upsert endpoint with
        'Prefer: create-if-missing', so a principal that never existed is created in the
        configured state.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Enabled = [bool]($Remediate.enabled -eq $true)
    $Body = @{ accountEnabled = $Enabled } | ConvertTo-Json -Compress
    foreach ($AppId in @('981f26a1-7f43-403b-a875-f8b09b8cd720', '1f5530b3-261a-47a9-b357-ded261e17918')) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$AppId')" -body $Body -tenantid $TenantFilter -type PATCH -AddedHeaders @{ 'Prefer' = 'create-if-missing' }
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the Azure MFA push notification apps to $(if ($Enabled) { 'enabled' } else { 'disabled' })." -Sev 'Info'
}
