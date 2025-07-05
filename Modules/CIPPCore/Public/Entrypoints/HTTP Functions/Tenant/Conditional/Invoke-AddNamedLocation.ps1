using namespace System.Net

function Invoke-AddNamedLocation {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Input bindings are passed in via param block.
    $Tenants = $Request.Body.selectedTenants.value
    $DisplayName = $Request.Body.policyName
    if ($Tenants -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName }
    $Results = foreach ($Tenant in $Tenants) {
        try {
            $ObjBody = if ($Request.body.Type -eq 'IPLocation') {
                $IPRanges = ($Request.body.Ips -split "`n") | ForEach-Object { if ($_ -ne '') { @{cidrAddress = "$_" } } }
                if (!$IPRanges) { $IPRanges = @(@{cidrAddress = "$($Request.Body.Ips)" }) }
                [pscustomobject]@{
                    '@odata.type' = '#microsoft.graph.ipNamedLocation'
                    displayName   = $DisplayName
                    ipRanges      = @($IPRanges)
                    isTrusted     = $Request.Body.Trusted
                }
            } else {
                [pscustomobject]@{
                    '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                    displayName                       = $DisplayName
                    countriesAndRegions               = @($Request.Body.Countries.value)
                    includeUnknownCountriesAndRegions = $Request.body.includeUnknownCountriesAndRegions
                }
            }
            $Body = ConvertTo-Json -InputObject $ObjBody
            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -body $Body -Type POST -tenantid $Tenant
            "Successfully added Named Location for $($Tenant)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Added Named Location $($DisplayName)" -Sev 'Info'

        } catch {
            "Failed to add Named Location $($Tenant): $($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed adding Named Location$($DisplayName). Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Results) }
    }
}
