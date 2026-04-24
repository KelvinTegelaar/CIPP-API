function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {

        $Conditions = $Request.Body.conditions
        Write-Information "Received request to add alert with conditions: $($Conditions | ConvertTo-Json -Compress -Depth 10)"

        # Validate conditions to prevent code injection via operator/property fields
        $AllowedOperators = @('eq', 'ne', 'like', 'notlike', 'match', 'notmatch', 'gt', 'lt', 'ge', 'le', 'in', 'notin', 'contains', 'notcontains')
        $SafePropertyRegex = [regex]'^[a-zA-Z0-9_.]+$'
        foreach ($condition in $Conditions) {
            if ($condition.Operator.value -and $condition.Operator.value.ToLower() -notin $AllowedOperators) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "Invalid operator: $($condition.Operator.value)" }
                    })
            }
            if ($condition.Property.label -and -not $SafePropertyRegex.IsMatch($condition.Property.label)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "Invalid property name: $($condition.Property.label)" }
                    })
            }
        }

        $Tenants = $Request.Body.tenantFilter
        $Conditions = $Request.Body.conditions | ConvertTo-Json -Compress -Depth 10 | Out-String
        $TenantsJson = $Tenants | ConvertTo-Json -Compress -Depth 10 | Out-String
        $excludedTenantsJson = $Request.Body.excludedTenants | ConvertTo-Json -Compress -Depth 10 | Out-String
        $Actions = $Request.Body.actions | ConvertTo-Json -Compress -Depth 10 | Out-String
        $RowKey = $Request.Body.RowKey ? $Request.Body.RowKey : (New-Guid).ToString()
        $CompleteObject = @{
            Tenants         = [string]$TenantsJson
            excludedTenants = [string]$excludedTenantsJson
            Conditions      = [string]$Conditions
            Actions         = [string]$Actions
            type            = $Request.Body.logbook.value
            RowKey          = $RowKey
            PartitionKey    = 'Webhookv2'
            AlertComment    = [string]$Request.Body.AlertComment
            CustomSubject   = [string]$Request.Body.CustomSubject
        }
        $WebhookTable = Get-CippTable -TableName 'WebhookRules'
        Add-CIPPAzDataTableEntity @WebhookTable -Entity $CompleteObject -Force
        $Results = "Added Audit Log Alert for $($Tenants.count) tenants. It may take up to four hours before Microsoft starts delivering these alerts."
        Write-LogMessage -API 'AddAlert' -message $Results -sev Info -LogData $CompleteObject -headers $Request.Headers

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ 'Results' = @($Results) }
            })
    } catch {
        Write-LogMessage -API 'AddAlert' -message "Error adding alert: $_" -sev Error -headers $Request.Headers
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to add alert: $_" }
            })
    }
}
