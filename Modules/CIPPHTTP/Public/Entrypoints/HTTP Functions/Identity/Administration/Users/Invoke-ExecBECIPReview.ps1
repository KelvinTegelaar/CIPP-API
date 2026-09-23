function Invoke-ExecBECIPReview {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Re-judges the IP addresses of a BEC case with the investigator's overrides and chosen accounts.
    .DESCRIPTION
        Validates the request and queues a background re-run of the case's address-dependent sections: the investigator's overrides (an address or CIDR range marked Safe or Compromised, with an optional note) become the case's complete override set, the sign-ins of the chosen accounts are correlated with the case's addresses, the address lists are re-read, and mailbox activity, IP verdicts, attacker activity, delegated mailboxes and the score are recomputed for the original window. Returns a DeploymentId whose per-step progress ListOffboardingProgress returns. To make a verdict permanent for the tenant, add the address to CIPP's IP allow/block list (ExecAddTrustedIP).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = [string]($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)
    # The BEC case (run) to review
    $CaseId = [string]$Request.Body.CaseId

    $StatusCode = [HttpStatusCode]::OK
    $DeploymentId = $null
    $Results = try {
        if (-not $TenantFilter) { $StatusCode = [HttpStatusCode]::BadRequest; throw 'tenantFilter is required' }
        if (-not $CaseId) { $StatusCode = [HttpStatusCode]::BadRequest; throw 'CaseId is required' }
        # The complete set of overrides for the case: an address or CIDR range, Safe or Compromised, and a note. Auto drops the override.
        $Overrides = foreach ($Override in $Request.Body.Overrides) {
            $Verdict = [string]($Override.Verdict.value ?? $Override.Verdict)
            if ($Verdict -eq 'Auto' -or -not $Verdict) { continue }
            if ($Verdict -notin @('Safe', 'Compromised')) { $StatusCode = [HttpStatusCode]::BadRequest; throw "Verdict must be Safe, Compromised or Auto, not '$Verdict'" }
            $Range = try { ConvertTo-CIPPIPRange -Value ([string]$Override.IP) } catch { $StatusCode = [HttpStatusCode]::BadRequest; throw }
            @{ IP = $Range; Verdict = $Verdict; Note = [string]$Override.Note }
        }
        # Object ids of other accounts whose sign-ins to correlate with the case's addresses
        $CorrelateUserIds = foreach ($User in $Request.Body.CorrelateUsers) { [string]($User.value ?? $User) }
        $CorrelateUserIds = @($CorrelateUserIds | Where-Object { $_ } | Select-Object -Unique)
        $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
        if (-not $Run) { $StatusCode = [HttpStatusCode]::NotFound; throw "Case $CaseId was not found in $TenantFilter" }
        if ($Run.Status -ne 'Completed') { $StatusCode = [HttpStatusCode]::BadRequest; throw "Case $CaseId has not completed yet" }
        # Auto is what the case already ran with: a re-run needs at least one address set to Safe or
        # Compromised (or accounts to correlate), and a set that differs from the one already applied.
        if (@($Overrides).Count -eq 0 -and $CorrelateUserIds.Count -eq 0) {
            $StatusCode = [HttpStatusCode]::BadRequest
            throw 'Set at least one address to Safe or Compromised before re-running'
        }
        $Signature = { param($Set) (@($Set | ForEach-Object { "$(ConvertTo-CIPPIPRange -Value ([string]($_.IP ?? $_.Range)))|$($_.Verdict)" }) | Sort-Object) -join ';' }
        if ($CorrelateUserIds.Count -eq 0 -and (& $Signature @($Overrides)) -eq (& $Signature @($Run.Results.IPOverrides | Where-Object { $_ }))) {
            $StatusCode = [HttpStatusCode]::BadRequest
            throw 'Nothing changed: set at least one address to a different verdict before re-running'
        }

        $DeploymentId = Start-CIPPBecIPReviewJob -TenantFilter $TenantFilter -CaseId $CaseId -Overrides @($Overrides) -CorrelateUserIds $CorrelateUserIds -UserPrincipalName ([string]$Run.UserPrincipalName) -Headers $Headers
        [pscustomobject]@{ resultText = "Re-judging the IP addresses of case $CaseId with $(@($Overrides).Count) override(s) and $($CorrelateUserIds.Count) correlated account(s). Progress is shown below."; state = 'info' }
    } catch {
        if ($StatusCode -eq [HttpStatusCode]::OK) { $StatusCode = [HttpStatusCode]::InternalServerError }
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC IP review of case $CaseId was not queued: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        [pscustomobject]@{ resultText = $ErrorMessage.NormalizedError; state = 'error' }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            # DeploymentId is set only when the review was queued: the id to poll with ListOffboardingProgress
            Body       = [pscustomobject]@{ Results = @($Results); DeploymentId = $DeploymentId }
        })
}
