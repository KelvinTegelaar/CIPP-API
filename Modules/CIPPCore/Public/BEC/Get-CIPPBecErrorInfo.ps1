function Get-CIPPBecErrorInfo {
    <#
    .SYNOPSIS
        Turns a raw collector error into a concise message and classifies known-benign conditions.
    .DESCRIPTION
        Collectors surface raw Exchange/Graph exception text (e.g. "Ex41BAF5|Microsoft.Exchange...
        ManagementObjectNotFoundException|The specified mailbox ... doesn't exist."). This strips the
        diagnostic prefix and support-reference noise for display, and recognises the conditions that
        are not failures at all - the user has no mailbox, or the tenant has no Intune - returning
        Skipped=$true with a plain-language Requirement so the UI shows "not checked", never a failure
        and never a pass. Anything it does not recognise comes back as a cleaned failure message.
    .PARAMETER Message
        The raw error text from a collector.
    .OUTPUTS
        [pscustomobject] { Message, Skipped, Requirement }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return [pscustomobject]@{ Message = $null; Skipped = $false; Requirement = $null }
    }
    $Raw = [string]$Message

    # No mailbox / not a recipient: the mailbox checks do not apply to this user - it is not a failure.
    if ($Raw -match "(?i)ManagementObjectNotFoundException|couldn't (find .+? as a recipient|be found as a recipient)|specified mailbox.+does(n't| not) exist|object '.+' couldn't be found on|Identity:.+couldn't be found") {
        return [pscustomobject]@{
            Message     = 'This user has no Exchange Online mailbox.'
            Skipped     = $true
            Requirement = 'this user has no Exchange Online mailbox'
        }
    }
    # Intune not licensed: the device service rejects the tenant outright. A licence gap, not a failure.
    if ($Raw -match '(?i)not applicable to (the )?target tenant') {
        return [pscustomobject]@{
            Message     = 'Intune is not licensed for this tenant.'
            Skipped     = $true
            Requirement = 'requires an Intune licence'
        }
    }
    # Intune not provisioned (or a transient service 404): treat as not applicable, with a retry hint.
    if ($Raw -match '(?i)Intune.+(HTTP 404|not.+provision|no.+Intune)') {
        return [pscustomobject]@{
            Message     = "Intune isn't provisioned for this tenant (or a transient service error - rerun to retry)."
            Skipped     = $true
            Requirement = 'Intune, which is not provisioned for this tenant'
        }
    }

    # Otherwise a real failure: strip the Exchange "ExNNNN|Type|" prefix and any support-reference tail.
    $Clean = if ($Raw -match '(?i)Ex[0-9A-F]{4,}\|[^|]*\|(.+)$') { $Matches[1] } else { $Raw }
    $Clean = ($Clean -replace '(?i)\s*Microsoft support reference.*$', '').Trim()
    return [pscustomobject]@{ Message = $Clean; Skipped = $false; Requirement = $null }
}
