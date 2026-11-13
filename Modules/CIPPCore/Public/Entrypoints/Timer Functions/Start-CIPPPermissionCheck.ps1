function Start-CIPPPermissionCheck {
    <#
    .SYNOPSIS
        Run the CIPP permissions check on a schedule.
    .DESCRIPTION
        The permissions check only ran when someone opened the permissions page, so an instance
        that needed new consent stayed that way until a human happened to look. Running it on a
        timer means Test-CIPPAccessPermissions raises its alert on its own, and the page's cached
        result stays current as a side effect.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-CIPPPermissionCheck', 'Check for permissions that need to be applied')) {
        # One check per configured partner so every partner's cached result stays fresh and a
        # broken secondary partner alerts without anyone opening the permissions page.
        foreach ($Partner in @(Get-CIPPPartnerTenant)) {
            try {
                $null = Test-CIPPAccessPermissions -TenantFilter $Partner.RowKey -PartnerTenantId $Partner.RowKey -APIName 'Permissions Check'
            } catch {
                Write-LogMessage -API 'Permissions Check' -message "Scheduled permissions check failed for partner $($Partner.RowKey): $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
            }
        }
    }
}
