using namespace System.Net

Function Invoke-ListSignIns {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.AuditLog.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Days = $Request.Query.Days ?? 7

    try {
        if ($Request.Query.failedLogonsOnly -eq 'true' -or $Request.Query.failedLogonsOnly -eq $true) {
            $FailedLogons = ' and (status/errorCode eq 50126)'
        }

        $filters = if ($Request.Query.Filter) {
            $Request.Query.filter
        } else {
            $ts = (Get-Date).AddDays(-$Days).ToUniversalTime()
            $endTime = $ts.ToString('yyyy-MM-dd')
            "createdDateTime ge $($endTime) and userDisplayName ne 'On-Premises Directory Synchronization Service Account' $FailedLogons"
        }
        Write-Host $Filters
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Retrieved sign in report' -Sev 'Debug' -tenant $TenantFilter

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=$($filters)" -tenantid $TenantFilter -erroraction stop
        $response = $GraphRequest | Select-Object *,
        @{l = 'additionalDetails'; e = { $_.status.additionalDetails } } ,
        @{l = 'errorCode'; e = { $_.status.errorCode } },
        @{l = 'locationcipp'; e = { "$($_.location.city) - $($_.location.countryOrRegion)" } }

        if ($Request.Query.failedLogonsOnly -and $Request.Query.FailureThreshold -and $Request.Query.FailureThreshold -gt 0) {
            $response = $response | Group-Object -Property userPrincipalName | Where-Object { $_.Count -ge $Request.Query.FailureThreshold } | Select-Object -ExpandProperty Group
        }

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($response)
            })
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to retrieve Sign In report: $($_.Exception.message) " -Sev 'Error' -tenant $TenantFilter
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $(Get-NormalizedError -message $_.Exception.message)
            })
    }

}
