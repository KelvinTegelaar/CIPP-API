function Get-CIPPAlertLowDomainScore {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        [ValidateRange(0, 100)]
        [int]$InputValue = 70
    )

    $DomainData = Get-CIPPDomainAnalyser -TenantFilter $TenantFilter
    if (-not $DomainData) {
        # No analyser results yet is 'could not check', not 'every domain is fine'.
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message 'Low domain score alert skipped: no domain analyser data available yet' -sev Info
        return
    }
    $LowScoreDomains = $DomainData | Where-Object { $_.ScorePercentage -lt $InputValue -and $_.ScorePercentage -ne '' -and $_.Domain -notlike '*.onmicrosoft.com' -and $_.Domain -notlike '*.mail.onmicrosoft.com' } | ForEach-Object {
        # Findings are {Check, Finding} objects; results saved before that are a plain string.
        $Issues = @($_.ScoreExplanation | ForEach-Object { $_.Finding ?? $_ }) -join ', '
        [PSCustomObject]@{
            Message          = "$($_.Domain): Domain security score is $($_.ScorePercentage)%, which is below the threshold of $InputValue%. Issues: $Issues"
            Id               = $_.Domain # stable identity; Message carries live score
            Domain           = $_.Domain
            ScorePercentage  = $_.ScorePercentage
            ScoreExplanation = $Issues
            Tenant           = $TenantFilter
        }
    }

    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $LowScoreDomains
}
