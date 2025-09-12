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
    $Profbod = [pscustomobject]$Request.Body
    $UserType = if ($Profbod.NotLocalAdmin -eq 'true') { 'standard' } else { 'administrator' }
    $DeploymentMode = if ($Profbod.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }
    $profileParams = @{
        DisplayName        = $Request.Body.DisplayName
        Description        = $Request.Body.Description
        UserType           = $UserType
        DeploymentMode     = $DeploymentMode
        AssignTo           = $Request.Body.Assignto
        DeviceNameTemplate = $Profbod.DeviceNameTemplate
        AllowWhiteGlove    = $Profbod.allowWhiteGlove
        CollectHash        = $Profbod.CollectHash
        HideChangeAccount  = $Profbod.HideChangeAccount
        HidePrivacy        = $Profbod.HidePrivacy
        HideTerms          = $Profbod.HideTerms
        Autokeyboard       = $Profbod.Autokeyboard
        Language           = $ProfBod.languages.value
    }
    $Results = foreach ($tenant in $Tenants) {
        $profileParams['tenantFilter'] = $tenant
        Set-CIPPDefaultAPDeploymentProfile @profileParams
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
