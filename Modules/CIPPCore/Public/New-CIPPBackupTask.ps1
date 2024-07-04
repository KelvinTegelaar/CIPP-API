function New-CIPPBackupTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter
    )

    $BackupData = switch ($Task) {
        'users' {
            $BackupData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter
        }
        'groups' {
            $BackupData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
        }
        'ca' {
            $BackupData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
        }
        'namedlocations' {
            $BackupData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
        }
        'authstrengths' {
            $BackupData = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter
        }
        'intuneconfig' {
            #alert
        }
        'intunecompliance' {}

        'intuneprotection' {}
    
        'CippWebhookAlerts' {
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            $BackupData = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).fullvalue.defaultDomainName }
        }
        'CippScriptedAlerts' {
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            $BackupData = Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
        }
        'CippStandards' { 
            $Table = Get-CippTable -tablename 'standards'
            $Filter = "PartitionKey eq 'standards' and RowKey eq '$($TenantFilter)'"
            $BackupData = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        }

    }
    return $BackupData
}

