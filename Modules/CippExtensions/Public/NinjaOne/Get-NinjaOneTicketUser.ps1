function Get-NinjaOneTicketUser {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Finds the NinjaOne end user or contact for a Microsoft 365 user inside one organisation, by email.
    .DESCRIPTION
        NinjaOne users carry no Entra object id, so email is the only link. Each candidate is tried in
        order against the organisation's users; an end user wins over a contact with the same email.
        Returns the user's uid for requesterUid, or $null when nothing matches.
    #>
    [CmdletBinding()]
    param (
        [string[]]$Emails,
        [Parameter(Mandatory = $true)]$ClientId,
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$Token
    )

    $Instance = $Configuration.Instance -replace '/ws', '' -replace 'https://', ''
    $Headers = @{ Authorization = "Bearer $($Token.access_token)" }

    foreach ($Email in @($Emails | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        $Candidates = try {
            @(Invoke-RestMethod -Uri "https://$Instance/api/v2/ticketing/app-user-contact?clientId=$([int]$ClientId)&searchCriteria=$([System.Uri]::EscapeDataString($Email))&pageSize=50" -Method GET -Headers $Headers -ContentType 'application/json')
        } catch {
            $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-LogMessage -API 'NinjaOneTicket' -message "NinjaOne user search failed for '$Email' in organisation ${ClientId}: $Message" -sev Warning
            @()
        }
        # searchCriteria is a contains-match on names and email, so pin it to an exact email.
        $Match = $Candidates |
            Where-Object { $_.uid -and $_.email -and ($_.email -ieq $Email) -and ([int]$_.clientId -eq [int]$ClientId) } |
            Sort-Object { if ($_.userType -eq 'END_USER') { 0 } else { 1 } } |
            Select-Object -First 1
        if ($Match) {
            return [pscustomobject]@{
                uid         = "$($Match.uid)"
                email       = $Match.email
                displayName = ("$($Match.firstName) $($Match.lastName)").Trim()
                userType    = $Match.userType
            }
        }
    }
    return $null
}
