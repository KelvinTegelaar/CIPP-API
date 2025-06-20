function Get-CIPPAlertLowDomainScore {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        [ValidateRange(0, 100)]
        [int]$InputValue = 70
    )

    $DomainData = Get-CIPPDomainAnalyser -TenantFilter $TenantFilter
    $LowScoreDomains = $DomainData | Where-Object {
        $_.ScorePercentage -lt $InputValue -and $_.ScorePercentage -ne ''
    } | ForEach-Object {
        "$($_.Domain): Domain security score is $($_.ScorePercentage)%, which is below the threshold of $InputValue%. Issues: $($_.ScoreExplanation)"
    }

    if ($LowScoreDomains) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $LowScoreDomains
    }
}
