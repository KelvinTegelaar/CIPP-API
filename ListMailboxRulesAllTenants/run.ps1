# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
$Tenants = if ($QueueItem -ne "AllTenants") {
    [PSCustomObject]@{
        defaultDomainName = $QueueItem
    }
}
else {
    Get-Tenants
}
$Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    Import-Module '.\GraphHelper.psm1'
    Import-Module '.\Modules\CIPPcore'
    try {
        
        $Rules = New-ExoRequest -tenantid $domainName -cmdlet "Get-Mailbox" | ForEach-Object -Parallel {
            New-ExoRequest -Anchor $_.UserPrincipalName -tenantid $domainName -cmdlet "Get-InboxRule" -cmdParams @{Mailbox = $_.GUID }
        }
        foreach ($Rule in $Rules) {
            $GraphRequest = @{
                Rules        = [string]($Rule | ConvertTo-Json)
                RowKey       = [string](New-Guid).guid
                Tenant       = [string]$domainName
                PartitionKey = 'mailboxrules'
            }
            $Table = Get-CIPPTable -TableName cachembxrules
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
        }
    }
    catch {
        $Rules = @{
            Name = "Could not connect to tenant $($_.Exception.message)"
        } | ConvertTo-Json
        $GraphRequest = @{
            Rules        = [string]$Rules
            RowKey       = [string]$domainName
            Tenant       = [string]$domainName

            PartitionKey = 'mailboxrules'
        }
        $Table = Get-CIPPTable -TableName cachembxrules
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    }
}



$Table = Get-CIPPTable -TableName cachembxrules
Write-Host "$($GraphRequest.RowKey) - $($GraphRequest.tenant)"
Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
