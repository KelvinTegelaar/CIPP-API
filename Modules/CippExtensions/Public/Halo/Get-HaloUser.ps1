function Get-HaloUser {
    <#
    .SYNOPSIS
        Look up a HaloPSA user/contact for a Microsoft 365 end-user.
    .DESCRIPTION
        Searches the HaloPSA /Users endpoint scoped to a specific client. Matches first by Azure
        Object ID (against the HaloPSA contact fields 'azureoid' and 'aaduserid'), then falls back
        to the user's email/UPN (against 'emailaddress', 'networklogin' and 'aaduserid' - Halo's
        AD-sync contacts often store the UPN in any of these). Returns a small object containing
        the matched user's id and site_id (Halo requires both when a specific user is set on a
        ticket), or $null when no match is found.
    .PARAMETER AzureOID
        The Microsoft Entra (Azure AD) Object ID of the user to match. Preferred when present.
    .PARAMETER Email
        The user's email address (typically the UPN). Used as a fallback when AzureOID is missing
        or returns no match.
    .PARAMETER ClientId
        The HaloPSA client id to scope the search to.
    .PARAMETER Configuration
        The HaloPSA extension configuration object (already extracted from Extensionsconfig).
    .PARAMETER Token
        A valid Halo OAuth token object as returned by Get-HaloToken.
    #>
    [CmdletBinding()]
    param (
        [string]$AzureOID,
        [string]$Email,
        [Parameter(Mandatory = $true)]
        $ClientId,
        [Parameter(Mandatory = $true)]
        $Configuration,
        [Parameter(Mandatory = $true)]
        $Token
    )

    $Headers = @{ Authorization = "Bearer $($Token.access_token)" }
    $BaseUri = "$($Configuration.ResourceURL)/Users?client_id=$ClientId&includeinactive=false&pageinate=false"

    $BuildResult = {
        param($MatchedUser)
        # Cast to [int] so PowerShell's default [double] deserialisation of JSON numbers
        # doesn't serialise back as e.g. "95.0", which Halo rejects.
        [pscustomobject]@{
            id      = [int]$MatchedUser.id
            site_id = [int]$MatchedUser.site_id
        }
    }

    # Halo's basic ?search= parameter only searches a fixed set of indexed fields (name, email,
    # logins...) and notably NOT azureoid. Use ?advanced_search= with filter_type=2 (=) for an
    # exact-match query against a specific field.
    $TryAdvancedSearch = {
        param($FilterName, $FilterValue)
        try {
            $Filter = ConvertTo-Json -Compress -InputObject @(@{
                filter_name  = $FilterName
                filter_type  = 2  # 2 = exact equality
                filter_value = $FilterValue
            })
            $EncodedFilter = [System.Uri]::EscapeDataString($Filter)
            $Response = Invoke-RestMethod -Uri "$BaseUri&advanced_search=$EncodedFilter" -ContentType 'application/json' -Method GET -Headers $Headers
            if ($Response.users) { return $Response.users }
            return $Response
        } catch {
            $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
            # Some Halo instances don't whitelist these fields for advanced_search even though they
            # exist on the user record. That's expected - the email-search fallback handles it. Only
            # log unexpected failures.
            if ($Message -notmatch 'Invalid advanced search parameter') {
                Write-LogMessage -API 'HaloPSATicket' -message "Halo advanced_search failed for $FilterName='$FilterValue' in client ${ClientId}: $Message" -sev Warning
            }
            return @()
        }
    }

    $TrySearch = {
        param($Term)
        try {
            $EncodedTerm = [System.Uri]::EscapeDataString($Term)
            $Response = Invoke-RestMethod -Uri "$BaseUri&search=$EncodedTerm" -ContentType 'application/json' -Method GET -Headers $Headers
            if ($Response.users) { return $Response.users }
            return $Response
        } catch {
            $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-LogMessage -API 'HaloPSATicket' -message "Halo user search failed for term '$Term' in client ${ClientId}: $Message" -sev Warning
            return @()
        }
    }

    # HaloPSA contacts can carry the user identity in several fields depending on how AD/Azure AD
    # sync is set up. Match against all known candidates so partial integrations still resolve.
    $AzureIdFields = @('azureoid', 'aaduserid')
    $EmailFields   = @('emailaddress', 'networklogin', 'aaduserid')

    # Try AzureOID first via advanced_search - exact-match on each AD identifier field, returning
    # the first hit. This is the most reliable path because Halo's azureoid field is the cleanest
    # link back to the Entra user.
    if ($AzureOID) {
        foreach ($Field in $AzureIdFields) {
            $Match = (& $TryAdvancedSearch $Field $AzureOID) | Where-Object { $_.id } | Select-Object -First 1
            if ($Match) { return & $BuildResult $Match }
        }
    }

    # Fall back to email: the basic search indexes email-shaped fields and returns candidates;
    # filter client-side against any of the email-bearing fields, and also re-check the AzureOID
    # against returned records (handy when a contact has azureoid set but blank email fields).
    if ($Email) {
        $Results = & $TrySearch $Email
        foreach ($User in $Results) {
            if ($AzureOID) {
                foreach ($Field in $AzureIdFields) {
                    $Value = $User.$Field
                    if ($Value -and ($Value -ieq $AzureOID)) { return & $BuildResult $User }
                }
            }
            foreach ($Field in $EmailFields) {
                $Value = $User.$Field
                if ($Value -and ($Value -ieq $Email)) { return & $BuildResult $User }
            }
        }
    }

    return $null
}
