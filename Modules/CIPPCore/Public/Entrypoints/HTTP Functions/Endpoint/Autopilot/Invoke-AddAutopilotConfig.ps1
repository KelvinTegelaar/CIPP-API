using namespace System.Net

Function Invoke-AddAutopilotConfig {
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
    $Tenants = $Request.body.selectedTenants.value
    $AssignTo = if ($request.body.Assignto -ne 'on') { $request.body.Assignto }
    $Profbod = [pscustomobject]$Request.body
    $usertype = if ($Profbod.NotLocalAdmin -eq 'true') { 'standard' } else { 'administrator' }
    $DeploymentMode = if ($profbod.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }
    $profileParams = @{
        displayname        = $request.body.Displayname
        description        = $request.body.Description
        usertype           = $usertype
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
    }
    $results = foreach ($Tenant in $tenants) {
        $profileParams['tenantFilter'] = $Tenant
        Set-CIPPDefaultAPDeploymentProfile @profileParams
    }
    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })



}
