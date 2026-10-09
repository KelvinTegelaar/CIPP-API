Function Invoke-ExecOneDriveShortCut {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Creates a OneDrive shortcut to a SharePoint library for one or more users.
    .DESCRIPTION
        Accepts one { username, userid, siteUrl, destination, tenantFilter } object or an array of them (the Users table bulk action). Every user is attempted: a failure for one user (for example a shortcut that already exists) is reported in its place and does not stop the remaining users, so a bulk rollout never has to be re-run to find out where it got to. The response is one result per user plus a summary line, and only returns an error status when no user succeeded.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    # One object from the user page, or an array of them from the Users table bulk action
    $Entries = @($Request.Body | Where-Object { $_ })
    $Results = [System.Collections.Generic.List[object]]::new()
    $Add = { param($Text, $State) $Results.Add([pscustomobject]@{ resultText = $Text; state = $State }) }

    if ($Entries.Count -eq 0) {
        & $Add 'No users were supplied to create a OneDrive shortcut for.' 'error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = $Results.ToArray() }
            })
    }

    $Failed = 0
    foreach ($Entry in $Entries) {
        $TenantFilter = $Entry.tenantFilter
        $Username = $Entry.username
        $UserId = $Entry.userid
        $URL = if ($Entry.siteUrl -is [psobject] -and $Entry.siteUrl.PSObject.Properties['value']) { $Entry.siteUrl.value } else { $Entry.siteUrl }
        $Destination = $Entry.destination
        if ($Destination -is [psobject] -and $Destination.PSObject.Properties['value']) {
            $Destination = $Destination.value
        }
        if ([string]::IsNullOrWhiteSpace([string]$Destination)) {
            $Destination = 'root'
        }

        try {
            $Message = New-CIPPOneDriveShortCut -Username $Username -UserId $UserId -TenantFilter $TenantFilter -URL $URL -Destination $Destination -Headers $Headers
            & $Add $Message 'success'
        } catch {
            # New-CIPPOneDriveShortCut has already logged the failure; record it and carry on with the next user
            $Failed++
            & $Add $_.Exception.Message 'error'
        }
    }

    if ($Entries.Count -gt 1) {
        $Succeeded = $Entries.Count - $Failed
        $SummaryState = if ($Failed -eq 0) { 'success' } elseif ($Succeeded -eq 0) { 'error' } else { 'warning' }
        & $Add "Created OneDrive shortcuts for $Succeeded of $($Entries.Count) users. $Failed failed; see the entries above for the users to address manually." $SummaryState
    }

    $StatusCode = Get-CippBulkStatusCode -Total $Entries.Count -Failed $Failed

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results.ToArray() }
        })
}
