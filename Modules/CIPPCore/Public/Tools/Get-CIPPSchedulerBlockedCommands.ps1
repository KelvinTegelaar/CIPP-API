function Get-CIPPSchedulerBlockedCommands {
    <#
    .SYNOPSIS
        Returns the list of commands that are blocked from execution via the CIPP scheduler.
    .DESCRIPTION
        Prevents privilege escalation and credential exfiltration by blocking functions that
        return tokens, secrets, keys, credentials, tenant lists, or perform SAM/CPV configuration
        from being executed as user-scheduled tasks.
    #>
    [CmdletBinding()]
    param()

    return @(
        # Token & authentication functions - would exfiltrate access/refresh tokens
        'Get-GraphToken'
        'Get-GraphTokenFromCert'
        'Get-ClassicAPIToken'
        'Get-CIPPAzIdentityToken'
        'Get-CIPPAuthentication'
        'New-CIPPAzServiceSAS'

        # Extension authentication tokens
        'Get-GradientToken'
        'Get-HaloToken'
        'Get-NinjaOneToken'
        'Get-SherwebAuthentication'
        'Get-HIBPAuth'

        # Secret & key material
        'Get-CippKeyVaultSecret'
        'Remove-CippKeyVaultSecret'
        'Get-ExtensionAPIKey'
        'Set-ExtensionAPIKey'
        'Remove-ExtensionAPIKey'

        # Tenant enumeration - would reveal full tenant list
        'Get-Tenants'

        # SAM permission enumeration - exposes which permissions the SAM app holds
        'Get-CippSamPermissions'

        # Direct storage access - bypasses CIPP data access controls
        'Get-CIPPTable'
        'Get-CIPPAzDataTableEntity'
        'Get-AzDataTableEntity'
        'Get-AzDataTable'
        'Add-CIPPAzDataTableEntity'
        'Add-AzDataTableEntity'
        'Update-AzDataTableEntity'
        'Remove-AzDataTableEntity'
        'Remove-AzDataTable'

        # Backup & restore
        'Get-CIPPBackup'
    )
}
