using namespace System.Net

Function Invoke-ListRiskySignIns {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.AuditLog.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.Query.TenantFilter
    $Days = $Request.Query.Days ?? 14

    try {
        $filters = if ($Request.Query.Filter) {
            $Request.Query.filter
        } else {
            $ts = (Get-Date).AddDays(-$Days).ToUniversalTime()
            $endTime = $ts.ToString('yyyy-MM-dd')
            "createdDateTime ge $($endTime) and userDisplayName ne 'On-Premises Directory Synchronization Service Account' and riskState ne 'none'"
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Retrieved risky sign in report' -Sev 'Debug' -tenant $TenantFilter

        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=$($filters)" -tenantid $TenantFilter
        $response = $GraphRequest | Select-Object *,
        @{l = 'additionalDetails'; e = { $_.status.additionalDetails } } ,
        @{l = 'errorCode'; e = { $_.status.errorCode } },
        @{l = 'locationcipp'; e = { "$($_.location.city) - $($_.location.countryOrRegion)" } }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($response)
            })
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve Risky Sign In report: $ErrorMessage" -Sev 'Error' -tenant $TenantFilter
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $ErrorMessage
            })
    }
}
