function Push-ListIntuneReusableSettingsAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheIntuneReusableSettings'

    try {
        $selectFields = @(
            'id'
            'settingInstance'
            'displayName'
            'description'
            'settingDefinitionId'
            'version'
            'referencingConfigurationPolicyCount'
            'createdDateTime'
            'lastModifiedDateTime'
        )
        $selectQuery = '?$select=' + ($selectFields -join ',')
        $uri = "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings$selectQuery"

        $Settings = New-GraphGetRequest -uri $uri -tenantid $DomainName
        if (-not $Settings) { $Settings = @() }

        foreach ($setting in @($Settings)) {
            if (-not $setting) { continue }

            $GUID = (New-Guid).Guid
            $PolicyData = @{
                id                   = $setting.id
                displayName          = $setting.displayName
                description          = $setting.description
                Tenant               = $DomainName
                version              = $setting.version
                createdDateTime      = $(if (![string]::IsNullOrEmpty($setting.createdDateTime)) { $setting.createdDateTime } else { '' })
                lastModifiedDateTime = $(if (![string]::IsNullOrEmpty($setting.lastModifiedDateTime)) { $setting.lastModifiedDateTime } else { '' })
            }
            $Entity = @{
                Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                RowKey       = [string]$GUID
                PartitionKey = 'IntuneReusableSetting'
                Tenant       = [string]$DomainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorPolicy = ConvertTo-Json -InputObject @{
            Tenant               = $DomainName
            displayName          = "Could not connect to Tenant: $($_.Exception.Message)"
            description          = 'Error'
            lastModifiedDateTime = (Get-Date).ToString('s')
            id                   = 'Error'
        } -Compress
        $Entity = @{
            Policy       = [string]$ErrorPolicy
            RowKey       = [string]$GUID
            PartitionKey = 'IntuneReusableSetting'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
