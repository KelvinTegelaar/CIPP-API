function Invoke-UndoSSPR {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        
    Write-LogMessage -API 'Standards' -tenant $tenant -message 'The standard for SSPR is no longer supported.' -sev Error
}
}
