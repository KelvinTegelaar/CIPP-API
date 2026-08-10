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
        'New-CIPPCertificateAssertion'
        'Get-ClassicAPIToken'
        'Get-CIPPAzIdentityToken'
        'Get-CIPPAuthentication'
        'New-CIPPAzServiceSAS'
        'New-GraphPOSTRequest'
        'New-GraphGetRequest'
        'New-GraphBulkRequest'
        'New-ExoRequest'
        'New-ExoBulkRequest'
        'New-TeamsRequestV2'
        'New-ClassicAPIGetRequest'
        'Invoke-CIPPRestMethod'
        'Invoke-GitHubApiRequest'
        'New-CIPPAzStorageRequest'
        'New-CippCoreRequest'
        'New-CIPPDbRequest'
        'New-DeviceLogin'
        'Clear-CippTokenCache'
        'Remove-CIPPDirectTenantToken'

        # Env
        'Set-CIPPEnvVarBackup'

        # Az Functions cmdlet
        'Get-CIPPAzFunctionAppSetting'
        'Get-CIPPAzFunctionAppSubId'
        'Update-CIPPAzFunctionAppSetting'
        'New-CIPPAzRestRequest'

        # Extension authentication tokens
        'Get-GradientToken'
        'Get-HaloToken'
        'Get-NinjaOneToken'
        'Get-SherwebAuthentication'
        'Get-HIBPAuth'

        # Secret & key material
        'Get-CippKeyVaultSecret'
        'Set-CippKeyVaultSecret'
        'Remove-CippKeyVaultSecret'
        'Get-CIPPSAMCertificate'
        'New-CIPPSAMCertificate'
        'Set-CIPPSAMCertificate'
        'Update-CIPPSAMCertificate'
        'Get-ExtensionAPIKey'
        'Set-ExtensionAPIKey'
        'Remove-ExtensionAPIKey'
        'Get-CIPPOmaSettingDecryptedValue'

        # End-tenant secret material - recovery keys & admin passwords, PostExecution would exfiltrate them
        'Get-CIPPLAPSPassword'
        'Get-CIPPBitlockerKey'
        'Search-CIPPBitlockerKeys'
        'Get-CIPPFileVaultKey'
        'Get-CIPPBiosPassword'

        # SAM/CPV & app registration configuration - privilege escalation / token theft vectors
        'Set-CIPPCPVConsent'
        'Add-CIPPApplicationPermission'
        'Add-CIPPDelegatedPermission'
        'Update-CippSamPermissions'
        'Set-CIPPSAMAdminRoles'
        'Update-CIPPSAMRedirectUri'
        'Update-CIPPSAMCertificateEnvCache'
        'Add-CIPPSSOAppSecret'
        'Set-CIPPSSOEasyAuth'
        'Set-CIPPSSOStoredCredentials'
        'Update-CIPPSSORedirectUri'
        'New-CIPPAPIConfig'
        'Get-CippApiAuth'
        'Set-CippApiAuth'
        'Repair-CippApiIdentifierUri'

        # CIPP RBAC - would allow privilege escalation within CIPP
        'Get-CIPPAccessRole'
        'Set-CIPPAccessRole'

        # Tenant enumeration - would reveal full tenant list
        'Get-Tenants'

        # SAM permission enumeration - exposes which permissions the SAM app holds
        'Get-CippSamPermissions'
        'Get-CIPPRolePermissions'

        # Direct storage access - bypasses CIPP data access controls
        'Get-CIPPTable'
        'Get-CIPPAzDataTableEntity'
        'Get-AzDataTableEntity'
        'Get-AzDataTable'
        'Add-CIPPAzDataTableEntity'
        'Add-AzDataTableEntity'
        'Update-AzDataTableEntity'
        'Remove-CIPPAzDataTableEntity'
        'Remove-AzDataTable'
        'Get-CIPPAzStorageContainer'
        'Remove-CIPPAzStorageContainer'
        'Get-CIPPAzStorageQueue'
        'Get-CIPPAzStorageQueueMessage'
        'Get-CIPPAzStorageQueueAnalysis'
        'Clear-CIPPAzStorageQueue'

        # Infrastructure control - denial of service
        'Request-CIPPRestart'

        # Backup & restore
        'Get-CIPPBackup'

        # Queueing functions - would allow attackers to create new scheduled tasks with blocked commands
        'Add-CippQueueMessage'
        'New-CippQueueEntry'
        'Set-CippQueueTask'
        'Update-CippQueueEntry'
        'Add-CIPPScheduledTask'
    )
}
