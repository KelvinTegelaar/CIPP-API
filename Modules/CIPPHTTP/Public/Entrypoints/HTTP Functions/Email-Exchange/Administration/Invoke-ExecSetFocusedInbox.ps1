function Invoke-ExecSetFocusedInbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Turns Focused Inbox on or off for one mailbox.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Mailbox UPN or address.
    $UserID = $Request.Body.ID
    # True turns Focused Inbox on, false turns it off.
    $FocusedInboxOn = $Request.Body.FocusedInboxOn

    if (-not $UserID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID is required' } })
    }
    if ("$FocusedInboxOn" -notin @('true', 'false')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'FocusedInboxOn must be true or false' } })
    }
    $Enabled = "$FocusedInboxOn" -eq 'true'
    $State = if ($Enabled) { 'on' } else { 'off' }

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-FocusedInbox' -cmdParams @{ Identity = $UserID; FocusedInboxOn = $Enabled }
        $Result = "Turned Focused Inbox $State for $UserID"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to turn Focused Inbox $State for $UserID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
