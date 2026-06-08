function Invoke-ExecCippReplacemap {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'CippReplacemap'
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $TenantId = $Request.Query.tenantId ?? $Request.Body.tenantId
    if ($TenantId -eq 'AllTenants') {
        $customerId = $TenantId
    } else {
        # ensure we use a consistent id for the table storage
        $Tenant = Get-Tenants -TenantFilter $TenantId
        $customerId = $Tenant.customerId
    }

    if (!$customerId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'customerId is required'
            })
        return
    }

    switch ($Action) {
        'List' {
            $Variables = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$customerId'" | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'Scope' -NotePropertyValue $(if ($customerId -eq 'AllTenants') { 'Global' } else { 'Tenant' }) -PassThru
            }
            if (!$Variables) {
                $Variables = @()
            }
            $IncludeGlobal = $Request.Query.includeGlobal ?? $Request.Body.includeGlobal
            if ($IncludeGlobal -eq 'true' -and $customerId -ne 'AllTenants') {
                $GlobalVariables = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AllTenants'" | ForEach-Object {
                    $_ | Add-Member -NotePropertyName 'Scope' -NotePropertyValue 'Global' -PassThru
                }
                if ($GlobalVariables) {
                    $TenantVarNames = @($Variables | ForEach-Object { $_.RowKey })
                    $GlobalVariables = @($GlobalVariables | Where-Object { $_.RowKey -notin $TenantVarNames })
                    $Variables = @($Variables) + @($GlobalVariables)
                }
            }
            $Body = @{ Results = @($Variables) }
        }
        'AddEdit' {
            $VariableName = $Request.Body.RowKey
            $VariableValue = $Request.Body.Value
            $VariableDescription = $Request.Body.Description

            $VariableEntity = @{
                PartitionKey = $customerId
                RowKey       = $VariableName
                Value        = $VariableValue
                Description  = $VariableDescription
            }

            Add-CIPPAzDataTableEntity @Table -Entity $VariableEntity -Force
            $Body = @{ Results = "Variable '$VariableName' saved successfully" }
        }
        'Delete' {
            $VariableName = $Request.Body.RowKey

            $VariableEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$customerId' and RowKey eq '$VariableName'"
            if ($VariableEntity) {
                Remove-AzDataTableEntity @Table -Entity $VariableEntity -Force
                $Body = @{ Results = "Variable '$VariableName' deleted successfully" }
            } else {
                $Body = @{ Results = "Variable '$VariableName' not found" }
            }
        }
        default {
            $Body = @{ Results = 'Invalid action' }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
