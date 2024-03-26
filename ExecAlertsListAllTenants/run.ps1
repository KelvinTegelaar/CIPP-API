# Input bindings are passed in via param block.
param( $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"

Get-Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    Import-Module CippCore
    $Table = Get-CIPPTable -TableName 'cachealertsandincidents'

    try {
        $Alerts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/alerts' -tenantid $domainName 
        foreach ($Alert in $Alerts) {
            $GUID = (New-Guid).Guid
            $alertJson = $Alert | ConvertTo-Json
            $GraphRequest = @{
                Alert        = [string]$alertJson
                RowKey       = [string]$GUID
                Tenant       = $domainName
                PartitionKey = 'alert'
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null

        }

    } catch {
        $GUID = (New-Guid).Guid
        $AlertText = ConvertTo-Json -InputObject @{
            Title             = "Could not connect to tenant to retrieve data: $($_.Exception.Message)" 
            Id                = ''
            Category          = ''
            EventDateTime     = ''
            Severity          = ''
            Status            = ''
            userStates        = @('None')
            vendorInformation = @{
                vendor   = 'CIPP'
                provider = 'CIPP'
            }
        }
        $GraphRequest = @{
            Alert        = [string]$AlertText 
            RowKey       = [string]$GUID
            PartitionKey = 'alert'
            Tenant       = $domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null


    }
}