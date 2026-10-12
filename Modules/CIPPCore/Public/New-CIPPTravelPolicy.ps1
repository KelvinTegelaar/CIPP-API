function New-CIPPTravelPolicy {
    <#
    .SYNOPSIS
    Creates a temporary travel conditional access policy and named location for vacation mode.

    .DESCRIPTION
    Builds a template-style policy JSON and hands it to New-CIPPCAPolicy, which creates the country
    named location from LocationInfo, waits for it to propagate, replaces the display name reference
    with the location ID and retries policy creation on propagation errors. The resulting policy blocks
    sign-ins for the included users from all locations except the travel destination. Entra ID has no
    standalone 'allow' control, so restricting sign-ins to the travel destination is achieved by blocking
    every other location. The policy and named location share the same display name so that
    Remove-CIPPTravelPolicy can remove both when the vacation ends.

    .PARAMETER Headers
    The headers to include in the request, typically containing authentication tokens. Supplied automatically by the API.

    .PARAMETER TenantFilter
    The tenant identifier to filter the request.

    .PARAMETER Users
    An array of user principal names or object IDs of the users travelling.

    .PARAMETER Countries
    An array of ISO 3166-1 alpha-2 country codes for the travel destination(s).

    .PARAMETER PolicyName
    The display name used for both the conditional access policy and the named location.

    .PARAMETER ExistingLocations
    Optional IDs of existing named locations that should also be allowed (excluded from the block),
    for example the home country or office IP ranges. These locations are referenced only and are
    never modified or deleted by Remove-CIPPTravelPolicy.

    .PARAMETER AllowTrusted
    Also allow sign-ins from all locations marked as trusted in the tenant ('AllTrusted').

    .PARAMETER APIName
    The name of the API operation being performed. Defaults to 'New-CIPPTravelPolicy'.
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string[]]$Users,
        [Parameter(Mandatory = $true)][string[]]$Countries,
        [Parameter(Mandatory = $true)][string]$PolicyName,
        [string[]]$ExistingLocations,
        [bool]$AllowTrusted = $false,
        [string]$APIName = 'New-CIPPTravelPolicy'
    )
    try {
        $GuidRegex = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
        $UserIds = foreach ($User in $Users) {
            if ($User -match $GuidRegex) {
                $User
            } else {
                (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$([System.Web.HttpUtility]::UrlEncode($User))?`$select=id" -tenantid $TenantFilter -asApp $true).id
            }
        }

        # Existing named locations are passed as IDs. New-CIPPCAPolicy only replaces display names found
        # in LocationInfo, so GUIDs are left untouched and referenced as-is.
        $ExcludeLocations = [System.Collections.Generic.List[string]]::new()
        $ExcludeLocations.Add($PolicyName)
        foreach ($LocationId in @($ExistingLocations | Where-Object { $_ })) {
            if ($LocationId -notmatch $GuidRegex) {
                throw "Existing named location '$LocationId' is not a valid named location ID."
            }
            if (-not $ExcludeLocations.Contains($LocationId)) { $ExcludeLocations.Add($LocationId) }
        }
        if ($AllowTrusted) { $ExcludeLocations.Add('AllTrusted') }

        $RawJSON = ConvertTo-Json -Depth 10 -InputObject @{
            displayName   = $PolicyName
            state         = 'enabled'
            conditions    = @{
                users          = @{ includeUsers = @($UserIds) }
                applications   = @{ includeApplications = @('All') }
                clientAppTypes = @('all')
                locations      = @{
                    includeLocations = @('All')
                    excludeLocations = @($ExcludeLocations)
                }
            }
            grantControls = @{
                operator        = 'OR'
                builtInControls = @('block')
            }
            LocationInfo  = @(
                @{
                    '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                    displayName                       = $PolicyName
                    countriesAndRegions               = @($Countries)
                    includeUnknownCountriesAndRegions = $false
                }
            )
        }
        $null = New-CIPPCAPolicy -RawJSON $RawJSON -TenantFilter $TenantFilter -Overwrite $true -ReplacePattern 'none' -APIName $APIName -Headers $Headers
        $AlsoAllowed = @()
        if (@($ExistingLocations | Where-Object { $_ }).Count -gt 0) { $AlsoAllowed += "$(@($ExistingLocations | Where-Object { $_ }).Count) existing named location(s)" }
        if ($AllowTrusted) { $AlsoAllowed += 'all trusted locations' }
        $Result = "Created temporary travel policy '$PolicyName' allowing sign-ins from $($Countries -join ', ')$(if ($AlsoAllowed) { ' and ' + ($AlsoAllowed -join ', ') }) only."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create temporary travel policy '$PolicyName': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
