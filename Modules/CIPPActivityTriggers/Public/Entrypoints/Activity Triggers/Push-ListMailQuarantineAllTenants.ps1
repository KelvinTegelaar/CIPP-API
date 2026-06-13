function Push-ListMailQuarantineAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName cacheQuarantineMessages
    Write-Host "PowerShell queue trigger function processed work item: $($Tenant.defaultDomainName)"

    try {
        $PageSize = 1000
        $quarantineMessages = [System.Collections.Generic.List[object]]::new()
        # Email is available everywhere; SharePointOnline/Teams quarantine requires Defender for Office 365,
        # so fetch each entity type separately and tolerate per-type failures on unlicensed tenants.
        # EXO REST silently ignores -EntityType SharePointOnline; the documented filter for Safe Attachments
        # files is -QuarantineTypes SPOMalware. Email/Teams work fine via -EntityType.
        foreach ($EntityType in @('Email', 'SharePointOnline', 'Teams')) {
            $EntityTypeParams = if ($EntityType -eq 'SharePointOnline') { @{ QuarantineTypes = 'SPOMalware' } } else { @{ EntityType = $EntityType } }
            try {
                $Page = 1
                do {
                    $Results = New-ExoRequest -tenantid $domainName -cmdlet 'Get-QuarantineMessage' -cmdParams (@{ PageSize = $PageSize; Page = $Page } + $EntityTypeParams) | Select-Object -ExcludeProperty *data.type*
                    if ($Results) { $quarantineMessages.AddRange(@($Results)) }
                    $Page++
                } while (@($Results).Count -eq $PageSize)
            } catch {
                if ($EntityType -eq 'Email') { throw }
                Write-Host "Could not get $EntityType quarantine messages for $domainName : $($_.Exception.Message)"
            }
        }
        foreach ($message in $quarantineMessages) {
            Add-CIPPQuarantineMessageProperties -Message $message -Tenant $domainName -CustomerId $Tenant.customerId
            $messageData = @{
                QuarantineMessage = [string]($message | ConvertTo-Json -Depth 10 -Compress)
                RowKey            = [string](New-Guid).Guid
                PartitionKey      = 'QuarantineMessage'
                Tenant            = [string]$domainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
        }
    } catch {
        $errorData = ConvertTo-Json -InputObject @{
            Identity         = $null
            ReceivedTime     = (Get-Date).ToString('s')
            SenderAddress    = 'CIPP Error'
            RecipientAddress = 'N/A'
            Subject          = "Could not connect to Tenant: $($_.Exception.Message)"
            Size             = 0
            Type             = 'Error'
            QuarantineReason = 'ConnectionError'
        }
        $messageData = @{
            QuarantineMessage = [string]$errorData
            RowKey            = [string]$domainName
            PartitionKey      = 'QuarantineMessage'
            Tenant            = [string]$domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
    }
}
