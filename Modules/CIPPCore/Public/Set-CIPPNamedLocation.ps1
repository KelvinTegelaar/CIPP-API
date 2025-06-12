function Set-CIPPNamedLocation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $NamedLocationId,
        $TenantFilter,
        #$Change should be one of 'addIp','addLocation','removeIp','removeLocation','rename'
        [ValidateSet('addIp', 'addLocation', 'removeIp', 'removeLocation', 'rename')]
        $Change,
        $Content,
        $APIName = 'Set Named Location',
        $Headers
    )

    try {
        $NamedLocations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -Tenantid $tenantfilter
        switch ($change) {
            'addIp' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges + @{ cidrAddress = $content; '@odata.type' = '#microsoft.graph.iPv4CidrRange' })
            }
            'addLocation' {
                $NamedLocations.countriesAndRegions = $NamedLocations.countriesAndRegions + $content
            }
            'removeIp' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges | Where-Object -Property cidrAddress -NE $content)
            }
            'removeLocation' {
                $NamedLocations.countriesAndRegions = @($NamedLocations.countriesAndRegions | Where-Object { $_ -NE $content })
            }
            'rename' {
                $NamedLocations.displayName = $content
            }
        }
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning Application $ApplicationId")) {
            #Remove unneeded properties
            if ($change -like '*location*') {
                $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'countriesAndRegions', 'includeUnknownCountriesAndRegions'
            } elseif ($change -eq 'rename') {
                # For rename, only include the basic properties needed
                if ($NamedLocations.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') {
                    $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'countriesAndRegions', 'includeUnknownCountriesAndRegions'
                } else {
                    $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'ipRanges', 'isTrusted'
                }
            } else {
                $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'ipRanges', 'isTrusted'
            }

            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -tenantid $TenantFilter -type PATCH -body $($NamedLocations | ConvertTo-Json -Compress -Depth 10)
            Write-LogMessage -headers $Headers -API $APIName -message "Edited named location. Change: $change with content $($content)" -Sev 'Info' -tenant $TenantFilter
        }
        return "Edited named location. Change: $change with content $($content)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to edit named location: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Failed to edit named location. Error: $($ErrorMessage.NormalizedError)"
    }
}
