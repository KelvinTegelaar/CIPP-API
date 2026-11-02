function Push-ExecAlertsListAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cachealertsandincidents'

    try {
        $Alerts = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/alerts_v2' -tenantid $domainName
        foreach ($Alert in $Alerts) {
            $GUID = (New-Guid).Guid
            $alertJson = $Alert | ConvertTo-Json -Depth 10
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
            Title                 = "Could not connect to tenant to retrieve data: $($_.Exception.Message)"
            Id                    = ''
            Category              = ''
            firstActivityDateTime = ''
            Severity              = ''
            Status                = ''
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
