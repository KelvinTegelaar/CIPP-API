function Invoke-EditTenantOffboardingDefaults {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $customerId = $Request.Body.customerId
    $offboardingDefaults = $Request.Body.offboardingDefaults

    if (!$customerId) {
        $response = @{
            state      = 'error'
            resultText = 'Customer ID is required'
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $response
            })
        return
    }

    $PropertiesTable = Get-CippTable -TableName 'TenantProperties'

    try {
        # Convert the offboarding defaults to JSON string and ensure it's treated as a string
        $jsonValue = [string]($offboardingDefaults | ConvertTo-Json -Compress)

        if ($jsonValue -and $jsonValue -ne '{}' -and $jsonValue -ne 'null' -and $jsonValue -ne '') {
            # Save offboarding defaults
            $offboardingEntity = @{
                PartitionKey = [string]$customerId
                RowKey       = [string]'OffboardingDefaults'
                Value        = [string]$jsonValue
            }
            $null = Add-CIPPAzDataTableEntity @PropertiesTable -Entity $offboardingEntity -Force
            Write-LogMessage -headers $Headers -tenant $customerId -API $APIName -message "Updated tenant offboarding defaults" -Sev 'Info'

            $resultText = 'Tenant offboarding defaults updated successfully'
        } else {
            # Remove offboarding defaults if empty or null
            $Existing = Get-CIPPAzDataTableEntity @PropertiesTable -Filter "PartitionKey eq '$customerId' and RowKey eq 'OffboardingDefaults'"
            if ($Existing) {
                Remove-AzDataTableEntity @PropertiesTable -Entity $Existing
                Write-LogMessage -headers $Headers -tenant $customerId -API $APIName -message "Removed tenant offboarding defaults" -Sev 'Info'
            }

            $resultText = 'Tenant offboarding defaults cleared successfully'
        }

        $response = @{
            state      = 'success'
            resultText = $resultText
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $response
            })
    } catch {
        Write-LogMessage -headers $Headers -tenant $customerId -API $APINAME -message "Edit Tenant Offboarding Defaults failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $response = @{
            state      = 'error'
            resultText = $_.Exception.Message
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = $response
            })
    }
}
