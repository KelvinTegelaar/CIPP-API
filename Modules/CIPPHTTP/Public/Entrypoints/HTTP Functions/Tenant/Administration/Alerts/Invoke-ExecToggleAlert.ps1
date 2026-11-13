Function Invoke-ExecToggleAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    .DESCRIPTION
        Enables or disables an alert rule without deleting it. Works for both audit log alerts and scheduled alert tasks.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with the query or body of the request
    $EventType = $Request.Query.EventType ?? $Request.Body.EventType
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $Disabled = [System.Convert]::ToBoolean($Request.Query.Disabled ?? $Request.Body.Disabled)

    if ($EventType -eq 'Audit log Alert') {
        $Table = 'WebhookRules'
    } else {
        $Table = 'ScheduledTasks'
    }

    $Table = Get-CIPPTable -TableName $Table
    try {
        $Filter = "RowKey eq '{0}'" -f (ConvertTo-CIPPODataFilterValue -Value $ID)
        $Alert = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, Tenant, Tenants
        # Audit log alerts store a selector list in Tenants; scheduled tasks store one tenant (or AllTenants) in Tenant
        $AlertTenants = $EventType -eq 'Audit log Alert' ? ($Alert.Tenants | ConvertFrom-Json -ErrorAction SilentlyContinue) : $Alert.Tenant
        if ($Alert -and -not (Test-CippTenantInScope -Tenant $AlertTenants)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'Access to this alert is not allowed' }
                })
        }
        if (!$Alert) {
            throw "No alert found with ID $ID"
        }
        $null = Update-AzDataTableEntity -Force @Table -Entity @{
            PartitionKey = $Alert.PartitionKey
            RowKey       = $Alert.RowKey
            Disabled     = [bool]$Disabled
        }
        $State = $Disabled ? 'disabled' : 'enabled'
        $Result = "Successfully $State alert $ID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to toggle alert $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}
