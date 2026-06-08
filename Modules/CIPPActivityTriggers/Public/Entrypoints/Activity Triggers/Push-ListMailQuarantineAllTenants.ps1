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
        $Page = 1
        $PageSize = 1000
        $quarantineMessages = [System.Collections.Generic.List[object]]::new()
        do {
            $Results = New-ExoRequest -tenantid $domainName -cmdlet 'Get-QuarantineMessage' -cmdParams @{ PageSize = $PageSize; Page = $Page } | Select-Object -ExcludeProperty *data.type*
            if ($Results) { $quarantineMessages.AddRange(@($Results)) }
            $Page++
        } while (@($Results).Count -eq $PageSize)
        foreach ($message in $quarantineMessages) {
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
