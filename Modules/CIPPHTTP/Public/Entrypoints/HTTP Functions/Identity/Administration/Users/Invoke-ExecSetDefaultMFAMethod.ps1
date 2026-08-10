function Invoke-ExecSetDefaultMFAMethod {
    <#
    .FUNCTIONALITY
    Entrypoint

    .ROLE
    Identity.User.ReadWrite

    .DESCRIPTION
    Sets the default second factor a user is prompted with, by patching signInPreferences.
    Note this is ignored at sign-in while system-preferred MFA is enabled for the user.
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    $UserId = $Request.Body.ID
    $MethodType = $Request.Body.MethodType.value ? $Request.Body.MethodType.value : $Request.Body.MethodType

    # Graph only accepts these six values for userPreferredMethodForSecondaryAuthentication.
    $ValidMethods = @('push', 'oath', 'voiceMobile', 'voiceAlternateMobile', 'voiceOffice', 'sms')

    if (-not $UserId -or -not $TenantFilter -or -not $MethodType) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = @('tenantFilter, ID and MethodType are required') }
            })
    }

    if ($MethodType -notin $ValidMethods) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = @("'$MethodType' is not a valid default MFA method. Valid values are: $($ValidMethods -join ', ')") }
            })
    }

    try {
        # signInPreferences only exists on the beta endpoint.
        # Guest UPNs contain '#EXT#'; unencoded, the '#' starts a URI fragment and truncates the Graph path.
        $Uri = 'https://graph.microsoft.com/beta/users/{0}/authentication/signInPreferences' -f [System.Uri]::EscapeDataString($UserId)
        $Body = @{ userPreferredMethodForSecondaryAuthentication = $MethodType } | ConvertTo-Json -Compress
        $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true

        $Result = "Successfully set the default MFA method to $MethodType for user $UserId"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set the default MFA method for user $UserId. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Result) }
        })
}
