function Invoke-CIPPStandardSSPR {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    Write-LogMessage -API 'Standards' -tenant $tenant -message 'SSPR standard is no longer available' -sev Error

}
