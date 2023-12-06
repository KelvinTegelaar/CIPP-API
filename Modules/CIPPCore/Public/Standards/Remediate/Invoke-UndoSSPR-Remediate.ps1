function Invoke-UndoSSPR-Remediate {
        <#
    .FUNCTIONALITY
    Internal
    #>
        param($tenant)
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'The standard for SSPR is no longer supported.' -sev Error
}
