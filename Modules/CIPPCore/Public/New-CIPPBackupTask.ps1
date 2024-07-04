function New-CIPPBackupTask {
    [CmdletBinding()]
    param (
        $ScheduledBackup,
        $TenantFilter
    )

    $BackupData = switch ($ScheduledBackup) {
        'users' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter
        }
        'groups' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
        }
        'ca' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
        }
        'namedlocations' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
        }
        'authstrengths' {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter
        }
        'intuneconfig' {
            #alert
        }
        'intunecompliance' {}

        'intuneprotection' {}
    
        'CippWebhookAlerts' {
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).fullvalue.defaultDomainName }
        }
        'CippScriptedAlerts' {
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
        }
        'CippStandards' { 
            $Table = Get-CippTable -tablename 'standards'
            $Filter = "PartitionKey eq 'standards' and RowKey eq '$($TenantFilter)'"
            (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        }

    }
    return $BackupData
}

