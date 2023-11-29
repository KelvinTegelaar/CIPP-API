# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"


Write-Information "Item: $QueueItem"
Write-Information ($TriggerMetadata | ConvertTo-Json)

try {
    Update-CippQueueEntry -RowKey $QueueItem -Status 'Running'

    $GraphRequest = Get-Tenants | ForEach-Object -Parallel { 
        $domainName = $_.defaultDomainName
        Import-Module '.\modules\CippCore'
        $Table = Get-CIPPTable -TableName cachemfa
        Try {
            $GraphRequest = Get-CIPPMFAState -TenantFilter $domainName -ErrorAction Stop
        }
        catch { 
            $GraphRequest = $null 
        }
        if (!$GraphRequest) {
            $GraphRequest = @{
                Tenant          = [string]$tenantName
                UPN             = [string]$domainName
                AccountEnabled  = 'none'
                PerUser         = [string]'Could not connect to tenant'
                MFARegistration = 'none'
                CoveredByCA     = [string]'Could not connect to tenant'
                CoveredBySD     = 'none'
                RowKey          = [string]"$domainName"
                PartitionKey    = 'users'
            }
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    }
}
catch {
    $Table = Get-CIPPTable -TableName cachemfa
    $GraphRequest = @{
        Tenant          = [string]$tenantName
        UPN             = [string]$domainName
        AccountEnabled  = 'none'
        PerUser         = [string]'Could not connect to tenant'
        MFARegistration = 'none'
        CoveredByCA     = [string]'Could not connect to tenant'
        CoveredBySD     = 'none'
        RowKey          = [string]"$domainName"
        PartitionKey    = 'users'
    }
    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
}
finally {
    Update-CippQueueEntry -RowKey $QueueItem -Status "Completed"
}
