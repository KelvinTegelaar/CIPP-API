function Invoke-ExecCaCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Runs a Conditional Access "what if" evaluation, reporting which policies would apply to a sign-in with the given user, application, device platform, device compliance, location, client app type, authentication flow and risk levels. Evaluation only - no sign-in occurs and no policy is changed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Tenant = $Request.Body.tenantFilter
    $UserID = $Request.Body.userID.value ?? $Request.Body.userID
    $Results = try {
        $Conditions = @{}
        if ($Request.Body.UserRiskLevel) { $Conditions.userRiskLevel = $Request.Body.UserRiskLevel.value ?? $Request.Body.UserRiskLevel }
        if ($Request.Body.SignInRiskLevel) { $Conditions.signInRiskLevel = $Request.Body.SignInRiskLevel.value ?? $Request.Body.SignInRiskLevel }
        if ($Request.Body.InsiderRiskLevel) { $Conditions.insiderRiskLevel = $Request.Body.InsiderRiskLevel.value ?? $Request.Body.InsiderRiskLevel }
        if ($Request.Body.ClientAppType) { $Conditions.clientAppType = $Request.Body.ClientAppType.value ?? $Request.Body.ClientAppType }
        if ($Request.Body.DevicePlatform) { $Conditions.devicePlatform = $Request.Body.DevicePlatform.value ?? $Request.Body.DevicePlatform }
        if ($Request.Body.Country) { $Conditions.country = $Request.Body.Country.value ?? $Request.Body.Country }
        if ($Request.Body.IpAddress) { $Conditions.ipAddress = $Request.Body.IpAddress }
        if ($Request.Body.authenticationFlow) { $Conditions.authenticationFlow = $Request.Body.authenticationFlow.value ?? $Request.Body.authenticationFlow }
        if ($null -ne $Request.Body.DeviceCompliant) {
            $Compliant = $Request.Body.DeviceCompliant.value ?? $Request.Body.DeviceCompliant
            if ("$Compliant" -in @('true', 'false')) { $Conditions.deviceInfo = @{ isCompliant = [bool]::Parse("$Compliant") } }
        }

        $Body = New-CIPPCAWhatIfRequest -UserId $UserID -IncludeApplications $Request.Body.IncludeApplications -Conditions $Conditions
        $Evaluation = @(Invoke-CIPPCAWhatIf -TenantFilter $Tenant -Bodies @($Body))[0]
        if ($Evaluation.Error) { throw $Evaluation.Error }
        @{ value = @($Evaluation.Policies) }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        "Failed to execute check: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })

}
