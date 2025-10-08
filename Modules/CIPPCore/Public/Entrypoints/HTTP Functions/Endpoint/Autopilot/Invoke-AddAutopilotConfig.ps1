function Invoke-AddAutopilotConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Input bindings are passed in via param block.
    $Tenants = $Request.Body.selectedTenants.value
    $Profbod = [pscustomobject]$Request.Body
    $UserType = if ($Profbod.NotLocalAdmin -eq 'true') { 'standard' } else { 'administrator' }
    $DeploymentMode = if ($Profbod.DeploymentMode -eq 'true') { 'shared' } else { 'singleUser' }

    # If deployment mode is shared, disable white glove (pre-provisioning) as it's not supported
    $AllowWhiteGlove = if ($DeploymentMode -eq 'shared') { $false } else { $Profbod.allowWhiteGlove }

    $profileParams = @{
        DisplayName        = $Request.Body.DisplayName
        Description        = $Request.Body.Description
        UserType           = $UserType
        DeploymentMode     = $DeploymentMode
        AssignTo           = $Request.Body.Assignto
        DeviceNameTemplate = $Profbod.DeviceNameTemplate
        AllowWhiteGlove    = $AllowWhiteGlove
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
