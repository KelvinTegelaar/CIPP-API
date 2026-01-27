
function Get-CippAlertSecureScore {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $SecureScore = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/security/secureScores?$top=1' -tenantid $TenantFilter -noPagination $true
        if ($InputValue.ThresholdType.value -eq "absolute") {
            if ($SecureScore.currentScore -lt $InputValue.InputValue) {
                $SecureScoreResult = [PSCustomObject]@{
                    Message        = "Secure Score is below acceptable threshold"
                    Tenant         = $TenantFilter
                    CurrentScore   = $SecureScore.currentScore
                    MaxSecureScore = $SecureScore.maxScore
                }
            } else {
                $SecureScoreResult = @()
            }
        } elseif ($InputValue.ThresholdType.value -eq "percent") {
            $PercentageScore = [math]::Round((($SecureScore.currentScore / $SecureScore.maxScore) * 100),2)
            if ($PercentageScore -lt $InputValue.InputValue) {
                $SecureScoreResult = [PSCustomObject]@{
                    Message                  = "Secure Score is below acceptable threshold"
                    Tenant                   = $TenantFilter
                    CurrentScore             = $SecureScore.currentScore
                    MaxScore                 = $SecureScore.maxScore
                    CurrentScorePercentage   = [math]::Round($PercentageScore,2)
                    ScoreThresholdPercentage = $InputValue.InputValue
                }
            } else {
                $SecureScoreResult = @()
            }
        } 
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $SecureScoreResult -PartitionKey SecureScore
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get Secure Score for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
