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
        try {
            $null = Test-CIPPAccessPermissions -TenantFilter $env:TenantID -APIName 'Permissions Check'
        } catch {
            Write-LogMessage -API 'Permissions Check' -message "Scheduled permissions check failed: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        }
    }
}
