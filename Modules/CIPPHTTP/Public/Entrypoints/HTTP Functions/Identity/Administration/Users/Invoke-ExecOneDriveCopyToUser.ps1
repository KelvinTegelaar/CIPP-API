function Invoke-ExecOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.ReadWrite
    .SYNOPSIS
        Copy a leaver's OneDrive to other users
    .DESCRIPTION
        Copies a leaver's OneDrive root contents into a folder named after the leaver's UPN at the root of each recipient's OneDrive and/or in a SharePoint document library, without overwriting anything already there (KeepBoth on name conflicts). The leaver must already be blocked from signing in. The leaver and recipients must be in tenantFilter; each recipient needs a OneDrive licence, a provisioned OneDrive and enough free space. Returns 202 with an OperationId; check ListOneDriveCopyToUser with it until State is Completed before removing the leaver's licences. CIPP does not copy the files itself: it starts SharePoint copy jobs and reports what SharePoint returns, so the copy's speed and any file SharePoint fails to copy are outside CIPP's control. Shortcuts to other people's files are not copied.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # One tenant (default domain or tenant id); the leaver and every recipient are looked up in it.
    $TenantFilter = $Request.Body.tenantFilter
    # UPN or object id of the user whose OneDrive is copied. The account must already be blocked from signing in.
    $Leaver = $Request.Body.leaver.value ?? $Request.Body.leaver
    # UPNs or object ids of up to 10 member users who receive the copy, as strings or {label, value} objects.
    $Recipients = @(foreach ($Recipient in $Request.Body.recipients) {
            $Value = $Recipient.value ?? $Recipient
            if ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) { $Value.Trim() }
        })
    # A SharePoint document library to copy into as well as, or instead of, recipients.
    $LibraryInput = $Request.Body.library
    $Library = @{
        # URL of the SharePoint site or subsite holding the library.
        site    = $LibraryInput.site.value ?? $LibraryInput.site
        # List id of the document library.
        library = $LibraryInput.library.value ?? $LibraryInput.library
        # Optional existing folder in the library, e.g. Leavers/2026; the copy goes in a folder named after the leaver inside it.
        folder  = $LibraryInput.folder
    }
    # Copy every version of each file. Off by default; when on, the free-space check counts the version history too.
    $IncludeVersionHistory = [bool]$Request.Body.includeVersionHistory

    if (-not $Request.Body.tenantFilter) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if (-not $Request.Body.leaver) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'leaver is required (UPN or object id).' } })
    }
    if ($Recipients.Count -eq 0 -and -not $Library.library) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Give recipients (UPNs or object ids), a document library, or both.' } })
    }
    if ($TenantFilter -eq 'AllTenants' -or $Leaver -isnot [string]) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name one tenant, and leaver must be a UPN or object id.' } })
    }

    try {
        $Result = Start-CIPPOneDriveCopyToUser -TenantFilter $TenantFilter -Leaver $Leaver -Recipients $Recipients -Library $Library -IncludeVersionHistory $IncludeVersionHistory -Headers $Headers -APIName $APIName
        $Problems = @(@(@($Result.Recipients).Where({ $_.State -eq 'Failed' }) | ForEach-Object { "$($_.UserPrincipalName): $($_.Message)" }) + @($Result.Warnings).Where({ $_ }))
        $Result | Add-Member -NotePropertyName resultText -NotePropertyValue ((@($Result.Message) + $Problems) -join ' ')
        $Result | Add-Member -NotePropertyName state -NotePropertyValue $(if ($Problems.Count -gt 0) { 'warning' } else { 'success' })
        $StatusCode = [HttpStatusCode]::Accepted
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start the OneDrive copy. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
