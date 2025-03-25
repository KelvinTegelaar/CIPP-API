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

    $APINAME = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Days = $Request.Query.Days ?? 7
    $FailedLogonsOnly = $Request.Query.failedLogonsOnly
    $FailureThreshold = $Request.Query.FailureThreshold
    $Filter = $Request.Query.Filter

    try {
        if ($FailedLogonsOnly -eq 'true' -or $FailedLogonsOnly -eq $true) {
            $FailedLogons = ' and (status/errorCode eq 50126)'
        }

        $Filters = if ($Filter) {
            $Filter
        } else {
            $ts = (Get-Date).AddDays(-$Days).ToUniversalTime()
            $endTime = $ts.ToString('yyyy-MM-dd')
            "createdDateTime ge $($endTime) and userDisplayName ne 'On-Premises Directory Synchronization Service Account' $FailedLogons"
        }
        Write-Host $Filters
        Write-LogMessage -headers $Headers -API $APINAME -message 'Retrieved sign in report' -Sev 'Debug' -tenant $TenantFilter

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=$($Filters)" -tenantid $TenantFilter -ErrorAction Stop
        $response = $GraphRequest | Select-Object *,
        @{l = 'additionalDetails'; e = { $_.status.additionalDetails } } ,
        @{l = 'errorCode'; e = { $_.status.errorCode } },
        @{l = 'locationcipp'; e = { "$($_.location.city) - $($_.location.countryOrRegion)" } }

        if ($FailedLogonsOnly -and $FailureThreshold -and $FailureThreshold -gt 0) {
            $response = $response | Group-Object -Property userPrincipalName | Where-Object { $_.Count -ge $FailureThreshold } | Select-Object -ExpandProperty Group
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
