# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)
Write-Host "Applying permissions for $($QueueItem.defaultDomainName)"
$Table = Get-CIPPTable -TableName cpvtenants
$CPVRows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Tenant -EQ $QueueItem.customerId
if (!$CPVRows -or $ENV:ApplicationID -notin $CPVRows.applicationId) {
    Write-LogMessage -tenant $queueitem.defaultDomainName -tenantId $queueitem.customerId -message "A New tenant has been added, or a new CIPP-SAM Application is in use" -Sev "Warn" -API "NewTenant"
    Write-Host "Adding CPV permissions"
    Set-CIPPCPVConsent -Tenantfilter $QueueItem.defaultDomainName
}

Add-CIPPApplicationPermission -RequiredResourceAccess "CippDefaults" -ApplicationId $ENV:ApplicationID -tenantfilter $QueueItem.defaultDomainName
Add-CIPPDelegatedPermission -RequiredResourceAccess "CippDefaults" -ApplicationId $ENV:ApplicationID -tenantfilter $QueueItem.defaultDomainName

Write-LogMessage -tenant $QueueItem.defaultDomainName -tenantId $queueitem.customerId -message "Updated permissions for $($QueueItem.defaultDomainName)" -Sev "Info" -API "UpdatePermissionsQueue"