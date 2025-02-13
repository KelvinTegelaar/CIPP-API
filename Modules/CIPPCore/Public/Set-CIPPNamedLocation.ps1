function Set-CIPPNamedLocation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $NamedLocationId,
        $TenantFilter,
        #$change should be one of 'addip','addlocation','removeip','removelocation'
        [ValidateSet('addip', 'addlocation', 'removeip', 'removelocation')]
        $change,
        $content,
        $APIName = 'Set Named Location',
        $Headers
    )

    try {
        $NamedLocations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations/$NamedLocationId" -Tenantid $tenantfilter
        switch ($change) {
            'addip' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges + @{ cidrAddress = $content; '@odata.type' = '#microsoft.graph.iPv4CidrRange' })
            }
            'addlocation' {
                $NamedLocations.countriesAndRegions = $NamedLocations.countriesAndRegions + $content
            }
            'removeip' {
                $NamedLocations.ipRanges = @($NamedLocations.ipRanges | Where-Object -Property cidrAddress -NE $content)
            }
            'removelocation' {
                $NamedLocations.countriesAndRegions = @($NamedLocations.countriesAndRegions | Where-Object { $_ -NE $content })
            }
        }
        if ($PSCmdlet.ShouldProcess($GroupName, "Assigning Application $ApplicationId")) {
            #Remove unneeded propertie
            if ($change -like '*location*') {
                $NamedLocations = $NamedLocations | Select-Object '@odata.type', 'displayName', 'countriesAndRegions', 'includeUnknownCountriesAndRegions'
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
        return "Failed to edit named location. Error: $($ErrorMessage.NormalizedError)"
    }
}
