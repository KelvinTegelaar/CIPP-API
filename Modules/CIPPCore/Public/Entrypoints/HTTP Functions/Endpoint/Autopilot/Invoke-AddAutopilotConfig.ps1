using namespace System.Net

function Invoke-AddAutopilotConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Input bindings are passed in via param block.
    $Tenants = $Request.Body.selectedTenants.value
    $AssignTo = if ($Request.Body.Assignto -ne 'on') { $Request.Body.Assignto }
    $Profbod = [pscustomobject]$Request.Body
    $UserType = if ($Profbod.NotLocalAdmin -eq 'true') { 'standard' } else { 'administrator' }
    $DeploymentMode = if ($profbod.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }
    $profileParams = @{
        displayname        = $Request.Body.Displayname
        description        = $Request.Body.Description
        usertype           = $UserType
        DeploymentMode     = $DeploymentMode
        assignto           = $AssignTo
        devicenameTemplate = $Profbod.deviceNameTemplate
        allowWhiteGlove    = $Profbod.allowWhiteGlove
        CollectHash        = $Profbod.collectHash
        hideChangeAccount  = $Profbod.hideChangeAccount
        hidePrivacy        = $Profbod.hidePrivacy
        hideTerms          = $Profbod.hideTerms
        Autokeyboard       = $Profbod.Autokeyboard
        Language           = $ProfBod.languages.value
        Headers            = $Headers
    }
    $Results = foreach ($Tenant in $Tenants) {
        $profileParams['TenantFilter'] = $Tenant
        Set-CIPPDefaultAPDeploymentProfile @profileParams
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
