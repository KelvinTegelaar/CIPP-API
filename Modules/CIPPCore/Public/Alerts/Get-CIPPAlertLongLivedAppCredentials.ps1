function Get-CIPPAlertLongLivedAppCredentials {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $MaxMonths = $InputValue

    try {
        $Apps = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=id,appId,displayName,passwordCredentials,keyCredentials&`$top=999" -tenantid $TenantFilter -AsApp $true)

        $NowUtc = [datetime]::UtcNow
        $DatePartition = (Get-Date -UFormat '%Y%m%d').ToString()
        $CredTypeMap = @(
            @{ Property = 'passwordCredentials'; TypeLabel = 'Secret' }
            @{ Property = 'keyCredentials'; TypeLabel = 'Certificate' }
        )

        foreach ($App in @($Apps)) {
            foreach ($ct in $CredTypeMap) {
                $credList = $App.($ct.Property)
                if (-not $credList) { continue }
                foreach ($Cred in @($credList)) {
                    $startUtc = ([datetime]$Cred.startDateTime).ToUniversalTime()
                    $endUtc = ([datetime]$Cred.endDateTime).ToUniversalTime()
                    if ($endUtc -le $startUtc -or $endUtc -le $NowUtc) { continue }
                    $months = (New-TimeSpan -Start $startUtc -End $endUtc).TotalDays / 30.4375
                    if ($months -gt $MaxMonths) {
                        $keyId = if ($Cred.keyId) { "$($Cred.keyId)" } else { 'unknown' }
                        $tracePartition = "$DatePartition-$($App.id)-$keyId" -replace '[/\\#?]', '_'
                        $oneFinding = [PSCustomObject]@{
                            AppDisplayName   = $App.displayName
                            AppId            = $App.appId
                            CredentialType   = $ct.TypeLabel
                            CredentialName   = $Cred.displayName
                            KeyId            = $Cred.keyId
                            StartDateTime    = $Cred.startDateTime
                            EndDateTime      = $Cred.endDateTime
                            ValidityMonths   = [math]::Round([double]$months, 2)
                            MaxMonthsAllowed = $MaxMonths
                        }
                        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $oneFinding -PartitionKey $tracePartition
                    }
                }
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Excessive secret validity alert failed: $ErrorMessage" -sev 'Error'
    }
}
