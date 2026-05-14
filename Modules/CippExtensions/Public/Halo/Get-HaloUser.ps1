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

    $BuildResult = {
        param($MatchedUser)
        # Cast to [int] so PowerShell's default [double] deserialisation of JSON numbers
        # doesn't serialise back as e.g. "95.0", which Halo rejects.
        [pscustomobject]@{
            id      = [int]$MatchedUser.id
            site_id = [int]$MatchedUser.site_id
        }
    }

    # HaloPSA contacts can carry the user identity in several fields depending on how AD/Azure AD
    # sync is set up. Match against all known candidates so partial integrations still resolve.
    $AzureIdFields = @('azureoid', 'aaduserid')
    $EmailFields   = @('emailaddress', 'networklogin', 'aaduserid')

    # Halo's /Users?search= parameter doesn't search the azureoid field, so a search by Object ID
    # alone returns zero rows even when a contact has that exact OID set. Strategy:
    # 1. Run a search per supplied term and combine the results into a deduped candidate pool.
    # 2. Filter the pool client-side, preferring AzureOID matches (most reliable) over email.
    $Candidates = @{}
    foreach ($Term in @($AzureOID, $Email) | Where-Object { $_ }) {
        foreach ($Result in (& $TrySearch $Term)) {
            if ($Result.id -and -not $Candidates.ContainsKey([string]$Result.id)) {
                $Candidates[[string]$Result.id] = $Result
            }
        }
    }

    $MatchOnAnyField = {
        param($User, $Term, $Fields)
        foreach ($Field in $Fields) {
            $Value = $User.$Field
            if ($Value -and ($Value -ieq $Term)) { return $true }
        }
        return $false
    }

    if ($AzureOID) {
        foreach ($User in $Candidates.Values) {
            if (& $MatchOnAnyField $User $AzureOID $AzureIdFields) {
                return & $BuildResult $User
            }
        }
    }

    if ($Email) {
        foreach ($User in $Candidates.Values) {
            if (& $MatchOnAnyField $User $Email $EmailFields) {
                return & $BuildResult $User
            }
        }
    }

    return $null
}
