function Invoke-ExecBECRelease {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Releases a user from the containment run on a BEC case.
    .DESCRIPTION
        Reverses the lockouts the case's containment placed on the user (see the Release field of ListBECRemediationActions): re-enables sign-in, restores the mailbox protocol settings, unblocks the mobile devices containment blocked, re-enables disabled registered devices and removes the targeted Conditional Access policy. Attacker cleanup is left in place and actions that cannot be undone are listed. Confirmation must equal the user's UPN. The release is recorded on the case.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    # the BEC case whose containment is released
    $CaseId = [string]$Request.Body.CaseId
    # reversible action ids to release; empty releases every one the containment ran
    $Actions = @($Request.Body.Actions | ForEach-Object { if ($_ -and $_.PSObject.Properties['value']) { $_.value } else { $_ } } | Where-Object { $_ })
    # must equal the user's UPN
    $Confirmation = [string]$Request.Body.Confirmation

    if (-not $TenantFilter -or -not $CaseId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{ Results = @([pscustomobject]@{ resultText = 'tenantFilter and CaseId are required'; state = 'error' }) }
            })
    }

    $StatusCode = [HttpStatusCode]::OK
    $Results = try {
        $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId
        if (-not $Run) {
            $StatusCode = [HttpStatusCode]::NotFound
            throw "BEC case $CaseId was not found"
        }
        $Username = [string]$Run.UserPrincipalName
        if (-not $Confirmation -or $Confirmation.Trim() -ine $Username.Trim()) {
            $StatusCode = [HttpStatusCode]::BadRequest
            throw "Type the user's UPN ($Username) to confirm releasing them from containment"
        }
        @(Invoke-CIPPBecRelease -TenantFilter $TenantFilter -CaseId $CaseId -Actions $Actions -Headers $Headers -APIName $APIName)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($StatusCode -eq [HttpStatusCode]::OK) { $StatusCode = [HttpStatusCode]::InternalServerError }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC release for case $CaseId was not executed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        @([pscustomobject]@{ resultText = $ErrorMessage.NormalizedError; state = 'error' })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ Results = @($Results) }
        })
}
