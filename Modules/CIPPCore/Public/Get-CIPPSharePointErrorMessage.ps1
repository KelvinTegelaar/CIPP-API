function Get-CIPPSharePointErrorMessage {
    <#
    .SYNOPSIS
    Turn a raw SharePoint REST error into something an admin can act on

    .DESCRIPTION
    The SharePoint REST API returns failures as an OData JSON envelope, so surfacing
    $_.Exception.Message directly puts a wall of JSON in front of the admin:

        {"odata.error":{"code":"-2146232832, Microsoft.SharePoint.SPException","message":{
        "lang":"en-US","value":"The specified user i:0#.f|membership|someone@contoso.com
        could not be found."}}}

    This unwraps that envelope to the human-readable value, and replaces the failures whose
    real cause is not what the message says with an explanation of what actually went wrong.

    The important one is 'could not be found' (-2146232832) on ensureuser. SharePoint reports
    it as a missing user, but for a member account it almost always means the account has no
    SharePoint Online licence: SharePoint will not materialise a site user for someone who
    cannot use SharePoint. Guests resolve fine without a licence, which is why this only bites
    on internal accounts. The same error is also returned briefly for a group created moments
    ago that has not replicated from Entra yet, hence the -IsGroup wording.

    Returns the explanation on its own, without naming the principal, so callers keep control
    of the surrounding sentence. Several of them are parsed by their caller in turn (the
    SharePoint template deploy checks results for 'Failed for'), so the prefix has to stay
    with the caller rather than move in here.

    .PARAMETER ErrorMessage
    The raw exception message from the SharePoint REST call

    .PARAMETER IsGroup
    Treat the principal as a group, which changes the likely cause of a resolution failure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ErrorMessage,

        [switch]$IsGroup
    )

    if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { return 'Unknown error.' }

    # Unwrap the OData envelope when there is one; otherwise keep the message as-is.
    $Detail = $ErrorMessage
    if ($ErrorMessage -match '"odata\.error"') {
        try {
            $Parsed = $ErrorMessage | ConvertFrom-Json -ErrorAction Stop
            $Value = $Parsed.'odata.error'.message.value
            if ($Value) { $Detail = [string]$Value }
        } catch {
            # Not valid JSON after all (truncated, or wrapped in other text). Pull the value
            # out with a pattern instead so the admin still gets the readable part.
            if ($ErrorMessage -match '"value"\s*:\s*"((?:[^"\\]|\\.)*)"') {
                $Detail = $Matches[1] -replace '\\"', '"' -replace '\\\\', '\'
            }
        }
    }

    # ensureuser could not resolve the principal.
    if ($Detail -match 'could not be found' -or $ErrorMessage -match '-2146232832') {
        if ($IsGroup.IsPresent) {
            return 'could not be resolved in SharePoint. If the group was just created it may not have replicated from Entra yet, so waiting a few minutes and retrying usually resolves it.'
        }
        return 'could not be resolved in SharePoint. This normally means the account has no SharePoint Online licence, which SharePoint reports as the user not existing. Assign a licence that includes SharePoint and try again. Guest accounts do not need one.'
    }

    # Failures worth naming rather than passing through raw.
    if ($Detail -match 'Access denied|not have permission') {
        return 'access denied. The CIPP application needs the SharePoint application permission consented for this tenant, and the site must not be locked read-only.'
    }
    if ($Detail -match 'does not exist|List does not exist') {
        return 'the site or library no longer exists. It may have been deleted or renamed since the list was loaded.'
    }

    return $Detail
}
