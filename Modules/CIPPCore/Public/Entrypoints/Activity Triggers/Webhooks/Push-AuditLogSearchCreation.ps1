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
            Write-Information "Created audit log search $($Tenant.defaultDomainName) - $($NewSearch.displayName)"
        }
    } catch {
        Write-Information "Error creating audit log search $($Tenant.defaultDomainName) - $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-LogMessage -API 'Audit Logs' -Message "Error creating audit log search for tenant $($Tenant.defaultDomainName): $($_.Exception.Message)" -Sev Error -LogData (Get-CippException -Exception $_)
    }
    return $true
}
