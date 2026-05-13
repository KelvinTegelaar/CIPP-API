function Invoke-ListStandardsCurrentState {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter

    if (-not $TenantFilter) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'tenantFilter is required' }
        }
    }

    try {
        $Table = Get-CIPPTable -TableName 'CippStandardsReports'
        $Filter = "PartitionKey eq '$TenantFilter'"
        $Standards = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)

        $Results = foreach ($Standard in $Standards) {
            $CurrentValue = if ($Standard.CurrentValue -and (Test-Json -Json $Standard.CurrentValue -ErrorAction SilentlyContinue)) {
                ConvertFrom-Json -InputObject $Standard.CurrentValue -ErrorAction SilentlyContinue
            } else {
                $Standard.CurrentValue
            }

            $ExpectedValue = if ($Standard.ExpectedValue -and (Test-Json -Json $Standard.ExpectedValue -ErrorAction SilentlyContinue)) {
                ConvertFrom-Json -InputObject $Standard.ExpectedValue -ErrorAction SilentlyContinue
            } else {
                $Standard.ExpectedValue
            }

            $FieldValue = $Standard.Value
            if ($FieldValue -is [System.Boolean]) {
                $FieldValue = [bool]$FieldValue
            } elseif ($FieldValue -and (Test-Json -Json "$FieldValue" -ErrorAction SilentlyContinue)) {
                $FieldValue = ConvertFrom-Json -InputObject $FieldValue -ErrorAction SilentlyContinue
            }

            $IsCompliant = ($FieldValue -eq $true) -or ($Standard.CurrentValue -and $Standard.CurrentValue -eq $Standard.ExpectedValue)

            [PSCustomObject]@{
                StandardName     = $Standard.RowKey
                Compliant        = $IsCompliant
                CurrentValue     = $CurrentValue
                ExpectedValue    = $ExpectedValue
                Value            = $FieldValue
                LicenseAvailable = $Standard.LicenseAvailable
                LastRefresh      = if ($Standard.TimeStamp) { $Standard.TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            }
        }

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to get standards current state: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }
}
