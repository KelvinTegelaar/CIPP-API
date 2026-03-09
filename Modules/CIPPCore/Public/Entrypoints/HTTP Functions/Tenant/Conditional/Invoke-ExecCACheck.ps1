function Invoke-ExecCaCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Tenant = $Request.Body.tenantFilter
    $UserID = $Request.Body.userID.value
    if ($Request.Body.IncludeApplications.value) {
        $IncludeApplications = $Request.Body.IncludeApplications.value
    } else {
        $IncludeApplications = '67ad5377-2d78-4ac2-a867-6300cda00e85'
    }
    $Results = try {
        $CAContext = @{
            '@odata.type'         = '#microsoft.graph.applicationContext'
            'includeApplications' = @($IncludeApplications)
        }
        $ConditionalAccessWhatIfDefinition = @{
            'signInIdentity'   = @{
                '@odata.type' = '#microsoft.graph.userSignIn'
                'userId'      = "$UserID"
            }
            'signInContext'    = $CAContext
            'signInConditions' = @{}
        }
        $whatIfConditions = $ConditionalAccessWhatIfDefinition.signInConditions
        if ($Request.body.UserRiskLevel) { $whatIfConditions.userRiskLevel = $Request.body.UserRiskLevel.value }
        if ($Request.body.SignInRiskLevel) { $whatIfConditions.signInRiskLevel = $Request.body.SignInRiskLevel.value }
        if ($Request.body.ClientAppType) { $whatIfConditions.clientAppType = $Request.body.ClientAppType.value }
        if ($Request.body.DevicePlatform) { $whatIfConditions.devicePlatform = $Request.body.DevicePlatform.value }
        if ($Request.body.Country) { $whatIfConditions.country = $Request.body.Country.value }
        if ($Request.body.IpAddress) { $whatIfConditions.ipAddress = $Request.body.IpAddress }
        if ($Request.body.authenticationFlow) { $whatIfConditions.authenticationFlow = @{ transferMethod = $Request.body.authenticationFlow.value } }

        $JSONBody = $ConditionalAccessWhatIfDefinition | ConvertTo-Json -Depth 10
        Write-Host $JSONBody
        $Request = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -tenantid $tenant -type POST -body $JsonBody -AsApp $true
        $Request
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
