using namespace System.Net

Function Invoke-ExecCaCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $request.body.tenantFilter
    $UserID = $request.body.userId.value
    if ($Request.body.IncludeApplications.value) {
        $IncludeApplications = $Request.body.IncludeApplications.value
    } else {
        $IncludeApplications = '67ad5377-2d78-4ac2-a867-6300cda00e85'
    }
    $results = try {
        $CAContext = @{
            '@odata.type'         = '#microsoft.graph.whatIfApplicationContext'
            'includeApplications' = @($IncludeApplications)
        }
        $ConditionalAccessWhatIfDefinition = @{
            'conditionalAccessWhatIfSubject'    = @{
                '@odata.type' = '#microsoft.graph.userSubject'
                'userId'      = "$userId"
            }
            'conditionalAccessContext'          = $CAContext
            'conditionalAccessWhatIfConditions' = @{}
        }
        $whatIfConditions = $ConditionalAccessWhatIfDefinition.conditionalAccessWhatIfConditions
        if ($Request.body.UserRiskLevel) { $whatIfConditions.userRiskLevel = $Request.body.UserRiskLevel.value }
        if ($Request.body.SignInRiskLevel) { $whatIfConditions.signInRiskLevel = $Request.body.SignInRiskLevel.value }
        if ($Request.body.ClientAppType) { $whatIfConditions.clientAppType = $Request.body.ClientAppType.value }
        if ($Request.body.DevicePlatform) { $whatIfConditions.devicePlatform = $Request.body.DevicePlatform.value }
        if ($Request.body.Country) { $whatIfConditions.country = $Request.body.Country.value }
        if ($Request.body.IpAddress) { $whatIfConditions.ipAddress = $Request.body.IpAddress.value }

        $JSONBody = $ConditionalAccessWhatIfDefinition | ConvertTo-Json -Depth 10
        Write-Host $JSONBody
        $Request = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -tenantid $tenant -type POST -body $JsonBody -AsApp $true
        $Request
    } catch {
        "Failed to execute check: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
