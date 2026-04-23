
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
        $TopCount = if ($InputValue.ThresholdType.value -eq 'drop') { 2 } else { 1 }
        $SecureScores = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/security/secureScores?`$top=$TopCount" -tenantid $TenantFilter -noPagination $true)
        $SecureScore = $SecureScores[0]

        if ($InputValue.ThresholdType.value -eq 'absolute') {
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
        } elseif ($InputValue.ThresholdType.value -eq 'percent') {
            $PercentageScore = [math]::Round((($SecureScore.currentScore / $SecureScore.maxScore) * 100), 2)
            if ($PercentageScore -lt $InputValue.InputValue) {
                $SecureScoreResult = [PSCustomObject]@{
                    Message                  = "Secure Score is below acceptable threshold"
                    Tenant                   = $TenantFilter
                    CurrentScore             = $SecureScore.currentScore
                    MaxScore                 = $SecureScore.maxScore
                    CurrentScorePercentage   = [math]::Round($PercentageScore, 2)
                    ScoreThresholdPercentage = $InputValue.InputValue
                }
            } else {
                $SecureScoreResult = @()
            }
        } elseif ($InputValue.ThresholdType.value -eq 'drop') {
            if ($SecureScores.Count -ge 2) {
                $PreviousScore = $SecureScores[1]
                if ($PreviousScore.currentScore -gt 0) {
                    $DropPercentage = [math]::Round((($PreviousScore.currentScore - $SecureScore.currentScore) / $PreviousScore.currentScore) * 100, 2)
                    if ($DropPercentage -ge $InputValue.InputValue) {
                        $SecureScoreResult = [PSCustomObject]@{
                            Message        = "Secure Score dropped by $DropPercentage% (from $($PreviousScore.currentScore) to $($SecureScore.currentScore))"
                            Tenant         = $TenantFilter
                            CurrentScore   = $SecureScore.currentScore
                            PreviousScore  = $PreviousScore.currentScore
                            MaxScore       = $SecureScore.maxScore
                            DropPercentage = $DropPercentage
                            DropThreshold  = $InputValue.InputValue
                        }
                    } else {
                        $SecureScoreResult = @()
                    }
                } else {
                    $SecureScoreResult = @()
                }
            } else {
                $SecureScoreResult = @()
            }
        }

        if ($SecureScoreResult) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $SecureScoreResult -PartitionKey SecureScore
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get Secure Score for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
