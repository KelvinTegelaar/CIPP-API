function Invoke-ExecPasswordNeverExpires {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Identity.User.ReadWrite
    #>
    Param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $UserId = $Request.Body.userId
    $UserPrincipalName = $Request.Body.userPrincipalName # Only used for logging
    $PasswordPolicy = $Request.Body.PasswordPolicy.value ?? $Request.Body.PasswordPolicy ?? 'None'
    $PasswordPolicyName = $Request.Body.PasswordPolicy.label ?? $Request.Body.PasswordPolicy.value ?? $Request.Body.PasswordPolicy # Only used for logging

    if ([string]::IsNullOrWhiteSpace($UserId)) { exit }
    try {
        $Body = ConvertTo-Json -InputObject @{ passwordPolicies = $PasswordPolicy } -Depth 5 -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$UserId" -tenantid $TenantFilter -Body $Body -type PATCH
        $Result = "Successfully set PasswordPolicy for user $UserPrincipalName to $PasswordPolicyName"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set PasswordPolicy for user $UserPrincipalName to $PasswordPolicyName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Result) }
        })
}
