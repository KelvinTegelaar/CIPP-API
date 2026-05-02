function Invoke-ListMDEOnboarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    if ($TenantFilter -eq 'AllTenants') {
        $UseReportDB = 'true'
    }

    try {
        if ($UseReportDB -eq 'true') {
            try {
                $GraphRequest = Get-CIPPMDEOnboardingReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving MDE onboarding status from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        $ConnectorId = 'fc780465-2017-40d4-a0c5-307022471b92'
        $ConnectorUri = "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/$ConnectorId"
        try {
            $ConnectorState = New-GraphGetRequest -uri $ConnectorUri -tenantid $TenantFilter
            $GraphRequest = $ConnectorState | Select-Object -ExcludeProperty '@odata.context'
            $GraphRequest | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
        } catch {
            $GraphRequest = [PSCustomObject]@{
                Tenant       = $TenantFilter
                partnerState = 'unavailable'
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
