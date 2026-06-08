function Invoke-ExecRemoveEnrollmentProfile {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    .DESCRIPTION
        Deletes an Apple ADE or Android Enterprise enrollment profile.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $ProfileId = $Request.Body.profileId ?? $Request.Body.id
    $ProfileType = $Request.Body.profileType ?? 'apple'
    $TokenId = $Request.Body.tokenId
    $DisplayName = $Request.Body.displayName ?? $ProfileId

    try {
        if ([string]::IsNullOrWhiteSpace($ProfileId)) { throw 'No profile id was supplied.' }

        if ($ProfileType -eq 'android') {
            $Uri = "https://graph.microsoft.com/beta/deviceManagement/androidDeviceOwnerEnrollmentProfiles/$ProfileId"
        } else {
            if ([string]::IsNullOrWhiteSpace($TokenId)) { throw 'No Apple ADE token id was supplied.' }
            $Uri = "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings/$TokenId/enrollmentProfiles/$ProfileId"
        }

        $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type DELETE
        $Result = "Deleted enrollment profile $DisplayName"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete enrollment profile ${DisplayName}: $($ErrorMessage.NormalizedMessage)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
