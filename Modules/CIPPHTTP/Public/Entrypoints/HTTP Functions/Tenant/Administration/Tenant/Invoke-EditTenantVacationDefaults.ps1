function Invoke-EditTenantVacationDefaults {
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
    $defaultDomainName = $Request.Body.defaultDomainName
    $vacationDefaults = $Request.Body.vacationDefaults

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

    # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $customerId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ state = 'error'; resultText = 'Access to this tenant is not allowed' }
            })
    }

    $PropertiesTable = Get-CippTable -TableName 'TenantProperties'

    try {
        # Convert the vacation defaults to JSON string and ensure it's treated as a string
        # PolicyId is an array of objects, so the default depth would truncate it
        $jsonValue = [string]($vacationDefaults | ConvertTo-Json -Compress -Depth 5)

        if ($jsonValue -and $jsonValue -ne '{}' -and $jsonValue -ne 'null' -and $jsonValue -ne '') {
            # Save vacation defaults
            $vacationEntity = @{
                PartitionKey = [string]$customerId
                RowKey       = [string]'VacationDefaults'
                Value        = [string]$jsonValue
            }
            $null = Add-CIPPAzDataTableEntity @PropertiesTable -Entity $vacationEntity -Force
            Write-LogMessage -headers $Headers -tenant $customerId -API $APIName -message "Updated tenant vacation defaults" -Sev 'Info'

            $resultText = 'Tenant vacation defaults updated successfully'
        } else {
            # Remove vacation defaults if empty or null
            $partitionKeys = @($customerId, $defaultDomainName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
            $existingDefaults = Get-CIPPAzDataTableEntity @PropertiesTable -Filter "RowKey eq 'VacationDefaults'"
            $toRemove = $existingDefaults | Where-Object { $_.PartitionKey -in $partitionKeys }
            if ($toRemove) {
                foreach ($Entity in $toRemove) {
                    Remove-CIPPAzDataTableEntity @PropertiesTable -Entity $Entity
                }
                Write-LogMessage -headers $Headers -tenant $customerId -API $APIName -message "Removed tenant vacation defaults for partition keys: $($partitionKeys -join ', ')" -Sev 'Info'
            }

            $resultText = 'Tenant vacation defaults cleared successfully'
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
        Write-LogMessage -headers $Headers -tenant $customerId -API $APINAME -message "Edit Tenant Vacation Defaults failed. The error is: $($_.Exception.Message)" -Sev 'Error'
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
