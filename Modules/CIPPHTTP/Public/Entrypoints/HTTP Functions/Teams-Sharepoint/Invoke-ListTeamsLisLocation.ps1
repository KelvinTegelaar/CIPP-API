Function Invoke-ListTeamsLisLocation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    .DESCRIPTION
        Lists Teams emergency calling Location Information Service (LIS) locations configured for a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.TenantFilter
    try {
        # Skype.Ncs/locations returns a bare array; the tenant comes from the token, not the path.
        # Property names are mapped to the shape Get-CsOnlineLisLocation returned so the UI contract
        # (Description / LocationId) is unchanged.
        $Locations = New-TeamsRequestV2 -TenantFilter $TenantFilter -Path 'Skype.Ncs/locations'
        $EmergencyLocations = foreach ($Location in @($Locations)) {
            [PSCustomObject]@{
                LocationId               = $Location.id
                CivicAddressId           = $Location.civicAddressId
                TenantId                 = $Location.tenantId
                Description              = $Location.description
                Location                 = $Location.location
                CompanyName              = $Location.companyName
                CompanyTaxId             = $Location.companyId
                PartnerId                = $Location.partnerId
                HouseNumber              = $Location.houseNumber
                HouseNumberSuffix        = $Location.houseNumberSuffix
                PreDirectional           = $Location.preDirectional
                StreetName               = $Location.streetName
                StreetSuffix             = $Location.streetSuffix
                PostDirectional          = $Location.postDirectional
                City                     = $Location.cityOrTown
                CityAlias                = $Location.cityOrTownAlias
                StateOrProvince          = $Location.stateOrProvince
                CountyOrDistrict         = $Location.countyOrDistrict
                PostalCode               = $Location.postalOrZipCode
                CountryOrRegion          = $Location.country
                Latitude                 = $Location.latitude
                Longitude                = $Location.longitude
                Confidence               = $Location.confidence
                Elin                     = $Location.elin
                IsDefault                = $Location.isDefault
                ValidationStatus         = $Location.validationStatus
                # The service returns -1 for these rather than a real count.
                NumberOfVoiceUsers       = $Location.numberOfVoiceUsers
                NumberOfTelephoneNumbers = $Location.numberOfTelephoneNumbers
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $EmergencyLocations = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($EmergencyLocations)
        })

}
