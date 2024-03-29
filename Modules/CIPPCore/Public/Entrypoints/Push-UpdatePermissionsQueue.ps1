function Push-UpdatePermissionsQueue {
    # Input bindings are passed in via param block.
    param($Item)
    Write-Host "Applying permissions for $($Item.defaultDomainName)"
    $Table = Get-CIPPTable -TableName cpvtenants
    $CPVRows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Tenant -EQ $Item.customerId
    if (!$CPVRows -or $ENV:ApplicationID -notin $CPVRows.applicationId) {
        Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message 'A New tenant has been added, or a new CIPP-SAM Application is in use' -Sev 'Warn' -API 'NewTenant'
        Write-Host 'Adding CPV permissions'
        Set-CIPPCPVConsent -Tenantfilter $Item.customerId
    }

    Add-CIPPApplicationPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Item.customerId
    Add-CIPPDelegatedPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Item.customerId

    Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Updated permissions for $($Item.displayName)" -Sev 'Info' -API 'UpdatePermissionsQueue'
}