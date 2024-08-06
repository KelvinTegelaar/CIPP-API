function Push-UpdatePermissionsQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $DomainRefreshRequired = $false

        if (!$Item.defaultDomainName) {
            $DomainRefreshRequired = $true
        }

        Write-Information "Applying permissions for $($Item.displayName)"
        $Table = Get-CIPPTable -TableName cpvtenants
        $CPVRows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Tenant -EQ $Item.customerId

        if (!$CPVRows -or $ENV:ApplicationID -notin $CPVRows.applicationId) {
            Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message 'A New tenant has been added, or a new CIPP-SAM Application is in use' -Sev 'Warn' -API 'NewTenant'
            Write-Information 'Adding CPV permissions'
            Set-CIPPCPVConsent -Tenantfilter $Item.customerId
            $DomainRefreshRequired = $true
        }
        Write-Information 'Updating permissions'
        Add-CIPPApplicationPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Item.customerId
        Add-CIPPDelegatedPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Item.customerId
        Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Updated permissions for $($Item.displayName)" -Sev 'Info' -API 'UpdatePermissionsQueue'

        Write-Information 'Pushing CIPP-SAM admin roles'
        Set-CIPPSAMAdminRoles -TenantFilter $Item.customerId

        $Table = Get-CIPPTable -TableName cpvtenants
        $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        $GraphRequest = @{
            LastApply     = "$unixtime"
            applicationId = "$($ENV:applicationId)"
            Tenant        = "$($Item.customerId)"
            PartitionKey  = 'Tenant'
            RowKey        = "$($Item.customerId)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force

        if ($DomainRefreshRequired) {
            $UpdatedTenant = Get-Tenants -TenantFilter $Item.customerId -TriggerRefresh
            if ($UpdatedTenant.defaultDomainName) {
                Write-Information "Updated tenant domains $($UpdatedTenant.defaultDomainName)"
            }
        }
    } catch {
        Write-Information "Error updating permissions for $($Item.displayName)"
    }
}
