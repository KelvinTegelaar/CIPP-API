function Push-ExecMdoAlertsListAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cachealertsandincidents'

    try {
        # Get MDO alerts using the specific endpoint and filter
        $Alerts = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/alerts_v2?`$filter=serviceSource eq 'microsoftDefenderForOffice365'" -tenantid $domainName

        foreach ($Alert in $Alerts) {
            $GUID = (New-Guid).Guid
            $GraphRequest = @{
                MdoAlert     = [string]($Alert | ConvertTo-Json -Depth 10)
                RowKey       = [string]$GUID
                PartitionKey = 'MdoAlert'
                Tenant       = [string]$domainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $AlertText = ConvertTo-Json -InputObject @{
            Tenant          = $domainName
            displayName     = "Could not connect to Tenant: $($_.Exception.Message)"
            id              = ''
            severity        = 'CIPP'
            status          = 'Failed'
            createdDateTime = (Get-Date).ToString('s')
            category        = 'Unknown'
            description     = 'Could not connect'
            serviceSource   = 'microsoftDefenderForOffice365'
        }
        $GraphRequest = @{
            MdoAlert     = [string]$AlertText
            RowKey       = [string]$GUID
            PartitionKey = 'MdoAlert'
            Tenant       = [string]$domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
    }
}
