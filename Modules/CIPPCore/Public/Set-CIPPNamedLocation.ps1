function Set-CIPPNamedLocation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $NamedLocationId,
        $TenantFilter,
        #$Change should be one of 'addIp','addLocation','removeIp','removeLocation','rename','setTrusted','setUntrusted','delete'
        [ValidateSet('addIp', 'addLocation', 'removeIp', 'removeLocation', 'rename', 'setTrusted', 'setUntrusted', 'delete')]
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
                $ActionDescription = "Adding IP $Content to named location"
            }
            'addLocation' {
                $NamedLocations.countriesAndRegions = $NamedLocations.countriesAndRegions + $Content
                $ActionDescription = "Adding location $Content to named location"
            }
            'removeIp' {
                $IpsToRemove = @($Content)
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges | Where-Object { $_.cidrAddress -notin $IpsToRemove })
                $ActionDescription = "Removing IP(s) $($IpsToRemove -join ', ') from named location"
            }
            'removeLocation' {
                $LocationsToRemove = @($Content)
                $NamedLocations.countriesAndRegions = @($NamedLocations.countriesAndRegions | Where-Object { $_ -notin $LocationsToRemove })
                $ActionDescription = "Removing location(s) $($LocationsToRemove -join ', ') from named location"
            }
            'rename' {
                $NamedLocations.displayName = $Content
                $ActionDescription = "Renaming named location to: $Content"
            }
            'setTrusted' {
                $NamedLocations.isTrusted = $true
                $ActionDescription = 'Setting named location as trusted'
            }
            'setUntrusted' {
                $NamedLocations.isTrusted = $false
                $ActionDescription = 'Setting named location as untrusted'
            }
            'delete' {
                $ActionDescription = 'Deleting named location'
            }
        }

        if ($PSCmdlet.ShouldProcess($NamedLocations.displayName, $ActionDescription)) {
            if ($Change -eq 'delete') {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -tenantid $TenantFilter -type DELETE
                $Result = "Deleted named location: $($NamedLocations.displayName)"
            } else {
                # PATCH operations - remove unneeded properties
                if ($NamedLocations.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') {
                    $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'countriesAndRegions', 'includeUnknownCountriesAndRegions'
                } elseif ($NamedLocations.'@odata.type' -eq '#microsoft.graph.ipNamedLocation') {
                    $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'ipRanges', 'isTrusted'
                }

                $JsonBody = ConvertTo-Json -InputObject $NamedLocations -Compress -Depth 10
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -tenantid $TenantFilter -type PATCH -body $JsonBody
                $Result = "Edited named location: $($NamedLocations.displayName). Change: $Change$(if ($Content) { " with content $Content" })"
            }

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
