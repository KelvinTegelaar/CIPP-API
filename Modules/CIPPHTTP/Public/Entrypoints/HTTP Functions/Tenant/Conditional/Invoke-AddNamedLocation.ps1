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
    try {
        # Input bindings are passed in via param block.
        $Tenants = $request.body.selectedTenants.value
        if ($Tenants -eq 'AllTenants') { $Tenants = (Get-Tenants).defaultDomainName }

        # AnyTenant: narrow to the caller's allowed tenants (same as Invoke-AddTransportRule)
        $AllowedTenants = Test-CippAccess -Request $Request -TenantList
        if ('AllTenants' -notin $AllowedTenants) {
            $AllTenants = Get-Tenants -IncludeErrors
            $AllowedTenantList = $AllTenants | Where-Object { $_.customerId -in $AllowedTenants }
            $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
        }

        # An empty Results array renders nothing in the UI, so say why nothing was created
        if (-not $Tenants) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = [pscustomobject]@{ Results = @('No tenants selected, or none of the selected tenants are in your allowed scope.') }
                })
        }

        $Failed = 0
        $results = foreach ($Tenant in $tenants) {
            try {
                $ObjBody = if ($Request.body.Type -eq 'IPLocation') {
                    $IPRanges = ($Request.body.Ips -split "`n") | ForEach-Object { if ($_.Trim() -ne '') { @{cidrAddress = $_.Trim() } } }
                    if (!$IPRanges) { $IPRanges = @(@{cidrAddress = "$($Request.Body.Ips)" }) }
                    [pscustomobject]@{
                        '@odata.type' = '#microsoft.graph.ipNamedLocation'
                        displayName   = $request.body.policyName
                        ipRanges      = @($IPRanges)
                        isTrusted     = $Request.body.Trusted
                    }
                } else {
                    [pscustomobject]@{
                        '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                        displayName                       = $request.body.policyName
                        countriesAndRegions               = @($Request.Body.Countries.value)
                        includeUnknownCountriesAndRegions = $Request.body.includeUnknownCountriesAndRegions
                    }
                }
                $Body = ConvertTo-Json -InputObject $ObjBody -Depth 10
                # The helper reports a refused tenant with a non-terminating Write-Error (and a caller's
                # ErrorActionPreference doesn't reach into its module), so pull it off the error stream
                # and throw, instead of reporting a false "Successfully added"
                $GraphErrors = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -body $body -Type POST -tenantid $tenant 2>&1 |
                    Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
                if ($GraphErrors) { throw @($GraphErrors)[0].Exception }
                "Successfully added Named Location for $($Tenant)"
                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenant -message "Added Named Location $($Request.Body.policyName)" -Sev 'Info'

            } catch {
                $Failed++
                "Failed to add Named Location $($Tenant): $($_.Exception.Message)"
                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $tenant -message "Failed adding Named Location $($Request.Body.policyName). Error: $($_.Exception.Message)" -Sev 'Error'
                continue
            }
        }

        $StatusCode = Get-CippBulkStatusCode -Total @($Tenants).Count -Failed $Failed
        $body = [pscustomobject]@{'Results' = @($results) }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $body = [pscustomobject]@{'Results' = @("Failed to add Named Location: $($_.Exception.Message)") }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed adding Named Location $($Request.Body.policyName). Error: $($_.Exception.Message)" -Sev 'Error'
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
