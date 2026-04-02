function Push-ListTeamsActivityAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheTeamsActivity'

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getTeamsUserActivityUserDetail(period='D30')" -tenantid $DomainName | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
        @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
        @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
        @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
        @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

        foreach ($Activity in $GraphRequest) {
            $GUID = (New-Guid).Guid
            $PolicyData = @{
                UPN          = $Activity.UPN
                LastActive   = $Activity.LastActive
                TeamsChat    = $Activity.TeamsChat
                CallCount    = $Activity.CallCount
                MeetingCount = $Activity.MeetingCount
                Tenant       = $DomainName
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'TeamsActivity'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant      = $DomainName
            displayName = "Could not connect to Tenant: $($_.Exception.Message)"
            id          = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'TeamsActivity'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
