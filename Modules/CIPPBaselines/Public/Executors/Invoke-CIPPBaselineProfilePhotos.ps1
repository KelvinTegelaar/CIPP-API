function Invoke-CIPPBaselineProfilePhotos {
    <#
    .SYNOPSIS
        ProfilePhotos executor: enables or disables user photo changes on both surfaces.
    .DESCRIPTION
        The classic's paired write: the default OWA mailbox policy's SetPhotoEnabled flag,
        and the Graph photo update settings - DELETEd back to default when enabling (an
        absent policy means everyone may change photos), or PATCHed with the admin role ids
        when disabling. Both must move or users keep a side door.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Enabled = "$($Remediate.state)" -eq 'enabled'
    $Uri = 'https://graph.microsoft.com/beta/admin/people/photoUpdateSettings'
    $Identity = "$($Current.owaPolicyIdentity)"
    if ([string]::IsNullOrWhiteSpace($Identity)) { $Identity = 'OwaMailboxPolicy-Default' }

    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-OwaMailboxPolicy' -cmdParams @{ Identity = $Identity; SetPhotoEnabled = $Enabled } -useSystemMailbox $true
    if ($Enabled) {
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -type DELETE -AsApp $true
    } else {
        $Body = @{
            source       = 'cloud'
            allowedRoles = @('fe930be7-5e62-47db-91af-98c3a49a38b1', '62e90394-69f5-4237-9190-012177145e10')
        } | ConvertTo-Json -Depth 5 -Compress
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri $Uri -type PATCH -body $Body -AsApp $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set user profile photo changes to $($Remediate.state)." -Sev 'Info'
}
