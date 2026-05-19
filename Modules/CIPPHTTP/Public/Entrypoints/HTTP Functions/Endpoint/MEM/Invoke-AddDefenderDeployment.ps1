function Invoke-AddDefenderDeployment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Tenants = ($Request.Body.selectedTenants).value
    if ('AllTenants' -in $Tenants) { $Tenants = (Get-Tenants -IncludeErrors).defaultDomainName }
    $Compliance = $Request.Body.Compliance
    $PolicySettings = $Request.Body.Policy
    $DefenderExclusions = $Request.Body.Exclusion
    $ASR = $Request.Body.ASR
    $EDR = $Request.Body.EDR

    $Results = foreach ($tenant in $Tenants) {
        try {
            if ($Compliance) {
                Set-CIPPDefenderCompliancePolicy -TenantFilter $tenant -Compliance $Compliance -Headers $Headers -APIName $APIName
            }
            if ($PolicySettings) {
                Set-CIPPDefenderAVPolicy -TenantFilter $tenant -PolicySettings $PolicySettings -Headers $Headers -APIName $APIName
            }
            if ($ASR) {
                Set-CIPPDefenderASRPolicy -TenantFilter $tenant -ASR $ASR -Headers $Headers -APIName $APIName
            }
            if ($EDR) {
                Set-CIPPDefenderEDRPolicy -TenantFilter $tenant -EDR $EDR -Headers $Headers -APIName $APIName
            }
            if ($DefenderExclusions) {
                Set-CIPPDefenderExclusionPolicy -TenantFilter $tenant -DefenderExclusions $DefenderExclusions -Headers $Headers -APIName $APIName
            }
        } catch {
            "Failed to add policy for $($tenant): $($_.Exception.Message)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $tenant -message "Failed adding Defender policy. Error: $($_.Exception.Message)" -Sev 'Error'
            continue
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = @($Results) }
        })

}

