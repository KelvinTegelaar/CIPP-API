function Invoke-ListGSARemoteNetworks {
    <#
    .SYNOPSIS
        Lists a tenant's Global Secure Access remote networks
    .DESCRIPTION
        Returns the tenant's remote networks (branch sites), read live, with the traffic forwarding
        profiles each one uses and its device links. Device links are returned without their tunnel
        configuration, which holds the VPN pre-shared key.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    try {
        if ((New-GraphGetRequest -uri "$Graph/tenantStatus" -tenantid $TenantFilter -AsApp $true).onboardingStatus -ne 'onboarded') {
            throw [System.ArgumentException]::new('This tenant is not onboarded to Global Secure Access')
        }
        $Body = @(foreach ($Network in @(New-GraphGetRequest -uri "$Graph/connectivity/remoteNetworks?`$expand=forwardingProfiles(`$select=id,name,trafficForwardingType)" -tenantid $TenantFilter -AsApp $true).Where({ $_.id })) {
                $DeviceLinks = $null
                try {
                    $DeviceLinks = @(@(New-GraphGetRequest -uri "$Graph/connectivity/remoteNetworks/$($Network.id)/deviceLinks" -tenantid $TenantFilter -AsApp $true).Where({ $_ }).ForEach({
                                [pscustomobject]@{ name = $_.name; ipAddress = $_.ipAddress; deviceVendor = $_.deviceVendor; bandwidthCapacityInMbps = $_.bandwidthCapacityInMbps; asn = $_.bgpConfiguration.asn }
                            }))
                } catch {
                    Write-Information "Could not read the device links of remote network '$($Network.name)': $($_.Exception.Message)"
                }
                [pscustomobject]@{
                    id          = $Network.id
                    name        = $Network.name
                    region      = $Network.region
                    profiles    = @(@($Network.forwardingProfiles).Where({ $_ }).ForEach({ [pscustomobject]@{ id = $_.id; name = $_.name; trafficForwardingType = $_.trafficForwardingType } }))
                    deviceLinks = $DeviceLinks
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list remote networks: $(Get-NormalizedError -Message $_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
}
