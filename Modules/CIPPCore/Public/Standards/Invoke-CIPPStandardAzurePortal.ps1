function Invoke-CIPPStandardAzurePortal {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate -eq $true) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'Azure Portal disablement is no longer functional. Please remove this standard.' -sev Error
    }
}
