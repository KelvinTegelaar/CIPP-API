function New-CIPPBackupTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter
    )

    $BackupData = switch ($Task) {
        'users' {
            Write-Host "Backup users for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter
        }
        'groups' {
            Write-Host "Backup groups for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
        }
        'ca' {
            Write-Host "Backup Conditional Access Policies for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter
        }
        'namedlocations' {
            Write-Host "Backup Named Locations for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
        }
        'authstrengths' {
            Write-Host "Backup Authentication Strength Policies for $TenantFilter"
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/authenticationStrength/policies' -tenantid $TenantFilter
        }
        'intuneconfig' {
            #alert
        }
        'intunecompliance' {}

        'intuneprotection' {}
    
        'CippWebhookAlerts' {
            Write-Host "Backup Webhook Alerts for $TenantFilter"
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).fullvalue.defaultDomainName }
        }
        'CippScriptedAlerts' {
            Write-Host "Backup Scripted Alerts for $TenantFilter"
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
        }
        'CippStandards' { 
            Write-Host "Backup Standards for $TenantFilter"
            $Table = Get-CippTable -tablename 'standards'
            $Filter = "PartitionKey eq 'standards' and RowKey eq '$($TenantFilter)'"
            (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        }

    }
    return $BackupData
}

