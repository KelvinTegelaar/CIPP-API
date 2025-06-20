function Invoke-ListTenantOnboarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    #>
    Param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    try {
        $OnboardTable = Get-CIPPTable -TableName 'TenantOnboarding'
        $TenantOnboardings = Get-CIPPAzDataTableEntity @OnboardTable
        $Results = @(foreach ($TenantOnboarding in $TenantOnboardings) {
                $Steps = $TenantOnboarding.OnboardingSteps | ConvertFrom-Json
                $OnboardingSteps = foreach ($Step in $Steps.PSObject.Properties.Name) { $Steps.$Step }
                $Relationship = try { $TenantOnboarding.Relationship | ConvertFrom-Json -ErrorAction Stop } catch { @{} }
                $Logs = try { $TenantOnboarding.Logs | ConvertFrom-Json -ErrorAction Stop } catch { @{} }
                $TenantOnboarding.OnboardingSteps = $OnboardingSteps
                $TenantOnboarding.Relationship = $Relationship
                $TenantOnboarding.Logs = $Logs
                $TenantOnboarding
            })
        $Results = $Results | Sort-Object Timestamp -Descending
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Function Error: $($ErrorMessage.LineNumber) - $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
