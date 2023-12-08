function Invoke-CIPPStandardDisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings) 

    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Self Service Licenses cannot be disabled' -sev Error

}
