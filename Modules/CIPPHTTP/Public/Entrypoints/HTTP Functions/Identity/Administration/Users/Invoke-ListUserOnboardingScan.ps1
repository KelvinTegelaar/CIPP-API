function Invoke-ListUserOnboardingScan {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Scan an existing user for settings an offboarding left behind
    .DESCRIPTION
        Checks the account, mailbox, delegated access and entitlements of a returning user and returns one finding per
        setting an offboarding left behind, each with the fix the onboarding job can run, plus the licences, groups,
        roles and manager saved when the user was offboarded. A check that fails is listed under Errors and the others
        still return. A deleted user returns a single finding asking for the account to be restored first.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Object id or userPrincipalName of the user to scan
    $UserId = $Request.Query.UserId
    if (-not $UserId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'UserId is required' } })
    }

    try {
        $Scan = Get-CIPPUserOnboardingScan -TenantFilter $TenantFilter -UserId $UserId -Headers $Request.Headers
        # Fix parameters nest deeper than the default serialisation depth.
        $Body = ConvertTo-Json -Depth 10 -Compress -InputObject @{ Results = $Scan }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to scan $UserId`: $($ErrorMessage.NormalizedError)" }
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message $Body.Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
