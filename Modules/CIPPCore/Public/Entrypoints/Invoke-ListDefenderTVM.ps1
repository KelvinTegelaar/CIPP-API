using namespace System.Net

Function Invoke-ListDefenderTVM {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    try {
        $GraphRequest = New-GraphgetRequest -tenantid $TenantFilter -uri "https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine?`$top=999" -scope 'https://api.securitycenter.microsoft.com/.default' | Group-Object cveid
        $GroupObj = foreach ($cve in $GraphRequest) {
            [pscustomobject]@{
                customerId                 = $TenantFilter
                affectedDevicesCount       = $cve.count
                cveId                      = $cve.name
                affectedDevices            = ($cve.group.deviceName -join ', ')
                osPlatform                 = ($cve.group.osplatform | Sort-Object -Unique)
                softwareVendor             = ($cve.group.softwareVendor | Sort-Object -Unique)
                softwareName               = ($cve.group.softwareName | Sort-Object -Unique)
                vulnerabilitySeverityLevel = ($cve.group.vulnerabilitySeverityLevel | Sort-Object -Unique)
                cvssScore                  = ($cve.group.cvssScore | Sort-Object -Unique)
                securityUpdateAvailable    = ($cve.group.securityUpdateAvailable | Sort-Object -Unique)
                exploitabilityLevel        = ($cve.group.exploitabilityLevel | Sort-Object -Unique)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GroupObj = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GroupObj)
        })

}
