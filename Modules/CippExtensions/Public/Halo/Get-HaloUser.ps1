function Get-HaloUser {
    <#
    .SYNOPSIS
        Look up a HaloPSA user/contact for a Microsoft 365 end-user.
    .DESCRIPTION
        Searches the HaloPSA /Users endpoint scoped to a specific client. Matches first by Azure
        Object ID (HaloPSA contact field 'azureoid'), then falls back to email address. Returns the
        matched HaloPSA user object's id, or $null when no match is found.
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
            Write-LogMessage -API 'HaloPSATicket' -message "Halo user search failed for term '$Term' in client $ClientId: $Message" -sev Warning
            return @()
        }
    }

    if ($AzureOID) {
        $Results = & $TrySearch $AzureOID
        $Match = $Results | Where-Object { $_.azureoid -and ($_.azureoid -eq $AzureOID) } | Select-Object -First 1
        if ($Match) { return $Match.id }
    }

    if ($Email) {
        $Results = & $TrySearch $Email
        $Match = $Results | Where-Object { $_.emailaddress -and ($_.emailaddress -ieq $Email) } | Select-Object -First 1
        if ($Match) { return $Match.id }
    }

    return $null
}
