function Invoke-ExecSyncDEP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    .DESCRIPTION
        Syncs devices from Apple Business Manager to Intune
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    try {
        $DepOnboardingSettings = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter)

        if ($null -eq $DepOnboardingSettings -or $DepOnboardingSettings.Count -eq 0) {
            $Result = 'No Apple Business Manager connections found'
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        } else {
            $SyncCount = 0
            foreach ($DepSetting in $DepOnboardingSettings) {
                if ($DepSetting.id) {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings/$($DepSetting.id)/syncWithAppleDeviceEnrollmentProgram" -tenantid $TenantFilter
                    $SyncCount++
                }
            }
            if ($SyncCount -eq 0) {
                $Result = 'No Apple Business Manager connections found'
            } else {
                $Result = "Successfully started device sync for $SyncCount Apple Business Manager connection$(if ($SyncCount -gt 1) { 's' })"
            }
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = 'Failed to start Apple Business Manager device sync'
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
