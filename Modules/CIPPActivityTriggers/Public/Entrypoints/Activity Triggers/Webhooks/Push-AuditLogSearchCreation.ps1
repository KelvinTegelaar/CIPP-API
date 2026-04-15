function Push-AuditLogSearchCreation {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Item)

    # Get params from batch item
    $Tenant = $Item.Tenant
    $StartTime = $Item.StartTime
    $EndTime = $Item.EndTime
    $ServiceFilters = @($Item.ServiceFilters)

    try {
        $LogSearch = @{
            StartTime         = $StartTime
            EndTime           = $EndTime
            ServiceFilters    = $ServiceFilters
            TenantFilter      = $Tenant.defaultDomainName
            ProcessLogs       = $true
            RecordTypeFilters = @(
                'exchangeAdmin',
                'azureActiveDirectory',
                'azureActiveDirectoryAccountLogon',
                'azureActiveDirectoryStsLogon'
            )
        }
        if ($PSCmdlet.ShouldProcess('Push-AuditLogSearchCreation', 'Creating Audit Log Search')) {
            $NewSearch = New-CippAuditLogSearch @LogSearch
            if ($NewSearch.id) {
                Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
            } elseif ($NewSearch.status -eq 'AuditingDisabledTenant') {
                Write-Information "Skipping audit log search $($Tenant.defaultDomainName) because unified auditing is disabled for this tenant"
                Write-LogMessage -API 'Audit Logs' -Message "Skipped audit log search creation for tenant $($Tenant.defaultDomainName) because unified auditing is disabled" -Sev Warning -tenant $Tenant.defaultDomainName
            } else {
                Write-Information "Audit log search creation returned no query id for tenant $($Tenant.defaultDomainName)"
                Write-LogMessage -API 'Audit Logs' -Message "Audit log search creation returned no query id for tenant $($Tenant.defaultDomainName)" -Sev Warning -tenant $Tenant.defaultDomainName
            }
        }
    } catch {
        Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-LogMessage -API 'Audit Logs' -tenant $Tenant.defaultDomainName -Message "Error creating audit log search for tenant $($Tenant.defaultDomainName): $($_.Exception.Message)" -Sev Error -LogData (Get-CippException -Exception $_)
    }
    return $true
}
