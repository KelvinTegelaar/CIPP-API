function Set-CIPPNamedLocation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $NamedLocationId,
        $TenantFilter,
        #$Change should be one of 'addIp','addLocation','removeIp','removeLocation','rename','setTrusted','setUntrusted'
        [ValidateSet('addIp', 'addLocation', 'removeIp', 'removeLocation', 'rename', 'setTrusted', 'setUntrusted')]
        $Change,
        $Content,
        $APIName = 'Set Named Location',
        $Headers
    )

    try {
        $NamedLocations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -Tenantid $TenantFilter
        switch ($Change) {
            'addIp' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges + @{ cidrAddress = $Content; '@odata.type' = '#microsoft.graph.iPv4CidrRange' })
            }
            'addLocation' {
                $NamedLocations.countriesAndRegions = $NamedLocations.countriesAndRegions + $Content
            }
            'removeIp' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges | Where-Object -Property cidrAddress -NE $Content)
            }
            'removeLocation' {
                $NamedLocations.countriesAndRegions = @($NamedLocations.countriesAndRegions | Where-Object { $_ -NE $Content })
            }
            'rename' {
                $NamedLocations.displayName = $Content
            }
            'setTrusted' {
                $NamedLocations.isTrusted = $true
            }
            'setUntrusted' {
                $NamedLocations.isTrusted = $false
            }
        }
        if ($PSCmdlet.ShouldProcess($NamedLocations.displayName, "Editing named location: $($NamedLocations.displayName). Change: $Change with content $($Content)")) {
            #Remove unneeded properties
            if ($NamedLocations.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') {
                $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'countriesAndRegions', 'includeUnknownCountriesAndRegions'
            } elseif ($NamedLocations.'@odata.type' -eq '#microsoft.graph.ipNamedLocation') {
                $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'ipRanges', 'isTrusted'
            }

            $JsonBody = ConvertTo-Json -InputObject $NamedLocations -Compress -Depth 10
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -tenantid $TenantFilter -type PATCH -body $JsonBody
            $Result = "Edited named location: $($NamedLocations.displayName). Change: $Change with content $($Content)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        }
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to edit named location: $($NamedLocations.displayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
