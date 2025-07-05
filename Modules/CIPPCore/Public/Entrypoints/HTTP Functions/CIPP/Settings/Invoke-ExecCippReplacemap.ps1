function Invoke-ExecCippReplacemap {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CippTable -tablename 'CippReplacemap'
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $customerId = $Request.Query.tenantId ?? $Request.Body.tenantId

    if (!$customerId) {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'customerId is required'
        }
    }

    switch ($Action) {
        'List' {
            $Variables = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$customerId'"
            if (!$Variables) {
                $Variables = @()
            }
            $Body = @{ Results = @($Variables) }
        }
        'AddEdit' {
            $VariableName = $Request.Body.RowKey
            $VariableValue = $Request.Body.Value

            $VariableEntity = @{
                PartitionKey = $customerId
                RowKey       = $VariableName
                Value        = $VariableValue
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

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
