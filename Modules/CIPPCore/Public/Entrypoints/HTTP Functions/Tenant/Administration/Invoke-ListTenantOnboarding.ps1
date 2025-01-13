function Invoke-ListTenantOnboarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    #>
    Param(
        $Request,
        $TriggerMetadata
    )
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
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $($_.InvocationInfo.ScriptLineNumber) - $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}