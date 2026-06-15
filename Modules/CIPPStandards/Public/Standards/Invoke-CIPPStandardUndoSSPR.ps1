function Invoke-CIPPStandardUndoSSPR {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.remediate -eq $true) {

        Write-LogMessage -API 'Standards' -tenant $tenant -message 'The standard for SSPR is no longer supported.' -sev Error
    }
}
