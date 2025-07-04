using namespace System.Net

function Invoke-ListDefenderTVM {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -tenantid $TenantFilter -uri "https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesByMachine?`$top=999" -scope 'https://api.securitycenter.microsoft.com/.default' | Group-Object cveId
        $GroupObj = foreach ($cve in $GraphRequest) {
            # Start with base properties
            $obj = [ordered]@{
                customerId           = $TenantFilter
                affectedDevicesCount = $cve.count
                cveId                = $cve.name
            }

            # Get all unique property names from the group
            $allProperties = $cve.group | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name | Sort-Object -Unique

            # Add all properties from the group with appropriate processing
            foreach ($property in $allProperties) {
                if ($property -eq 'deviceName') {
                    # Special handling for deviceName - join with comma
                    $obj['affectedDevices'] = ($cve.group.$property -join ', ')
                } else {
                    # For all other properties, get unique values
                    $obj[$property] = ($cve.group.$property | Sort-Object -Unique) | Select-Object -First 1
                }
            }

            # Convert and output as PSCustomObject. Not really needed, but hey, why not.
            [pscustomobject]$obj
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $GroupObj = $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($GroupObj)
    }
}
