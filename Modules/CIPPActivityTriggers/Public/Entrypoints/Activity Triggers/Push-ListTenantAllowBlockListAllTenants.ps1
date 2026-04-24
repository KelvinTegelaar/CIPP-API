function Push-ListTenantAllowBlockListAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName 'cacheTenantAllowBlockList'
    $ListTypes = 'Sender', 'Url', 'FileHash', 'IP'

    try {
        foreach ($ListType in $ListTypes) {
            $Entries = New-ExoRequest -tenantid $domainName -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ ListType = $ListType }
            foreach ($Entry in $Entries) {
                $CleanEntry = $Entry | Select-Object -ExcludeProperty *'@data.type'*, *'(DateTime])'*
                $CleanEntry | Add-Member -MemberType NoteProperty -Name Tenant -Value $domainName -Force
                $CleanEntry | Add-Member -MemberType NoteProperty -Name ListType -Value $ListType -Force
                $Entity = @{
                    Entry        = [string]($CleanEntry | ConvertTo-Json -Depth 10 -Compress)
                    RowKey       = [string](New-Guid).Guid
                    PartitionKey = 'TenantAllowBlockList'
                    Tenant       = [string]$domainName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
            }
        }
    } catch {
        $ErrorEntry = [pscustomobject]@{
            Tenant      = $domainName
            ListType    = 'Error'
            Identity    = 'Error'
            DisplayName = "Could not retrieve tenant allow/block list: $($_.Exception.Message)"
            Timestamp   = (Get-Date).ToString('s')
        }
        $Entity = @{
            Entry        = [string]($ErrorEntry | ConvertTo-Json -Depth 10 -Compress)
            RowKey       = [string](New-Guid).Guid
            PartitionKey = 'TenantAllowBlockList'
            Tenant       = [string]$domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
