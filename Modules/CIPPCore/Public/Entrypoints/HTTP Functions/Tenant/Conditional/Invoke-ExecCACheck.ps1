using namespace System.Net

function Invoke-ExecCaCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
                'userId'      = "$userId"
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
        if ($Request.body.IpAddress) { $whatIfConditions.ipAddress = $Request.body.IpAddress.value }

        $JSONBody = $ConditionalAccessWhatIfDefinition | ConvertTo-Json -Depth 10
        New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/evaluate' -tenantid $Tenant -type POST -body $JsonBody -AsApp $true
    } catch {
        "Failed to execute check: $($_.Exception.Message)"
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
