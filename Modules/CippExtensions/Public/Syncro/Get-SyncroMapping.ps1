function Get-SyncroMapping {
    <#
    .SYNOPSIS
        Returns the Syncro customer list and the current tenant-to-customer mappings for the
        Tenant Mapping tab.
    .PARAMETER CIPPMapping
        The CippMapping table context from Get-CIPPTable.
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Syncro'
    $Tenants = Get-Tenants -IncludeErrors

    $Mappings = foreach ($Mapping in $ExtensionMappings) {
        $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }
        if ($Tenant) {
            [PSCustomObject]@{
                TenantId        = $Tenant.customerId
                Tenant          = $Tenant.displayName
                TenantDomain    = $Tenant.defaultDomainName
                IntegrationId   = $Mapping.IntegrationId
                IntegrationName = $Mapping.IntegrationName
            }
        }
    }

    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction Stop).Syncro
        $SyncroCustomers = Get-SyncroCustomer -Configuration $Configuration | ForEach-Object {
            [PSCustomObject]@{
                # business_then_name is the business name, or the contact's full name for a
                # residential customer with no business - the same label Syncro shows in its UI.
                name  = if ($_.business_then_name) { $_.business_then_name } elseif ($_.business_name) { $_.business_name } else { $_.fullname }
                value = "$($_.id)"
            }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }

        Write-LogMessage -Message "Could not get Syncro customers, error: $Message" -Level Error -tenant 'CIPP' -API 'SyncroMapping'
        $SyncroCustomers = @(@{ name = "Could not get Syncro customers, error: $Message"; value = '-1' })
    }

    $MappingObj = [PSCustomObject]@{
        Companies = @($SyncroCustomers)
        Mappings  = @($Mappings)
    }

    return $MappingObj
}
