function Invoke-ExecOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.ReadWrite
    .SYNOPSIS
        Copy a leaver's OneDrive to other users
    .DESCRIPTION
        Copies a leaver's OneDrive root contents into a folder named after the leaver's UPN at the root of each recipient's OneDrive, without overwriting anything already there (KeepBoth on name conflicts). The leaver must already be blocked from signing in. The leaver and recipients must be in tenantFilter; each recipient needs a OneDrive licence, a provisioned OneDrive and enough free space. Returns 202 with an OperationId; check ListOneDriveCopyToUser with it until State is Completed before removing the leaver's licences.
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
    # Copy every version of each file. Off by default: only current versions count towards the free-space check.
    $IncludeVersionHistory = [bool]$Request.Body.includeVersionHistory

    if (-not $Request.Body.tenantFilter) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if (-not $Request.Body.leaver) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'leaver is required (UPN or object id).' } })
    }
    if (-not $Request.Body.recipients) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'recipients is required (one or more UPNs or object ids).' } })
    }
    if ($TenantFilter -eq 'AllTenants' -or $Leaver -isnot [string] -or $Recipients.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name one tenant, and leaver and recipients must be UPNs or object ids.' } })
    }

    try {
        $Result = Start-CIPPOneDriveCopyToUser -TenantFilter $TenantFilter -Leaver $Leaver -Recipients $Recipients -IncludeVersionHistory $IncludeVersionHistory -Headers $Headers -APIName $APIName
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
