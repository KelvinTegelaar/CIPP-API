using namespace System.Net

Function Invoke-EditTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $customerId = $Request.Body.customerId
    $tenantAlias = $Request.Body.Alias
    $tenantGroups = $Request.Body.Groups

    $PropertiesTable = Get-CippTable -TableName 'TenantProperties'
    $Existing = Get-CIPPAzDataTableEntity @PropertiesTable -Filter "PartitionKey eq '$customerId'"
    $Tenant = Get-Tenants -TenantFilter $customerId
    $TenantTable = Get-CippTable -TableName 'Tenants'

    try {
        $AliasEntity = $Existing | Where-Object { $_.RowKey -eq 'Alias' }
        if (!$tenantAlias) {
            if ($AliasEntity) {
                Write-Host 'Removing alias'
                Remove-AzDataTableEntity @PropertiesTable -Entity $AliasEntity
                $null = Get-Tenants -TenantFilter $customerId -TriggerRefresh
            }
        } else {
            $aliasEntity = @{
                PartitionKey = $customerId
                RowKey       = 'Alias'
                Value        = $tenantAlias
            }
            Add-CIPPAzDataTableEntity @PropertiesTable -Entity $aliasEntity -Force
            Write-Host "Setting alias to $tenantAlias"
            $Tenant.displayName = $tenantAlias
            $null = Add-CIPPAzDataTableEntity @TenantTable -Entity $Tenant -Force
        }

        <## Update tenant groups
        $groupsEntity = @{
            PartitionKey = $customerId
            RowKey       = 'tenantGroups'
            Value        = ($tenantGroups | ConvertTo-Json)
        }
        Set-CIPPAzDataTableEntity -Context $context -Entity $groupsEntity
        #>

        $response = @{
            state      = 'success'
            resultText = 'Tenant details updated successfully'
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $response
            })
    } catch {
        Write-LogMessage -headers $Request.Headers -tenant $customerId -API $APINAME -message "Edit Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $response = @{
            state      = 'error'
            resultText = $_.Exception.Message
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $response
            })
    }
}
