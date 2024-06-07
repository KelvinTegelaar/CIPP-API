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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Input bindings are passed in via param block.
    $Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
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
