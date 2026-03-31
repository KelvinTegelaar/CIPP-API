function Push-ListSharedMailboxAccountEnabledAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheSharedMailboxAccountEnabled

    try {
        $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($DomainName)/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $DomainName -scope ExchangeOnline)
        $AllUsersInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,userPrincipalName,accountEnabled,displayName,givenName,surname,onPremisesSyncEnabled,assignedLicenses' -tenantid $DomainName

        foreach ($SharedMailbox in $SharedMailboxList) {
            $User = $AllUsersInfo | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1

            if ($User.accountEnabled) {
                $GUID = (New-Guid).Guid
                $PolicyData = [PSCustomObject]@{
                    UserPrincipalName     = $User.userPrincipalName
                    displayName           = $User.displayName
                    givenName             = $User.givenName
                    surname               = $User.surname
                    accountEnabled        = $User.accountEnabled
                    assignedLicenses      = $User.assignedLicenses
                    id                    = $User.id
                    onPremisesSyncEnabled = $User.onPremisesSyncEnabled
                    Tenant                = $DomainName
                }
                $Entity = @{
                    Policy       = [string]($PolicyData | ConvertTo-Json -Depth 10 -Compress)
                    RowKey       = [string]$GUID
                    PartitionKey = 'SharedMailboxAccountEnabled'
                    Tenant       = [string]$DomainName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
            }
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
            PartitionKey = 'SharedMailboxAccountEnabled'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    }
}
