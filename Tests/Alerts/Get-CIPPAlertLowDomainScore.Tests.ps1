# Domain analyser findings are {Check, Finding} objects; results saved before that hold one string. The alert text
# must read the same for both.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertLowDomainScore.ps1')

    function Get-CIPPDomainAnalyser { param($TenantFilter) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
}

Describe 'Get-CIPPAlertLowDomainScore' {
    BeforeEach {
        Mock Write-AlertTrace { $script:Alerts = $data }
    }

    It 'lists <Name> findings as text' -ForEach @(
        @{ Name = 'object'; Explanation = @([pscustomobject]@{ Check = 'SPF'; Finding = 'No SPF Record Found' }, [pscustomobject]@{ Check = 'DKIM'; Finding = 'DKIM Not Configured' }) }
        @{ Name = 'legacy string'; Explanation = 'No SPF Record Found, DKIM Not Configured' }
    ) {
        Mock Get-CIPPDomainAnalyser { [pscustomobject]@{ Domain = 'contoso.com'; ScorePercentage = 40; ScoreExplanation = $Explanation } }
        Get-CIPPAlertLowDomainScore -TenantFilter 'contoso.onmicrosoft.com' -InputValue 70
        $script:Alerts.Message | Should -Be 'contoso.com: Domain security score is 40%, which is below the threshold of 70%. Issues: No SPF Record Found, DKIM Not Configured'
        $script:Alerts.ScoreExplanation | Should -Be 'No SPF Record Found, DKIM Not Configured'
    }
}
