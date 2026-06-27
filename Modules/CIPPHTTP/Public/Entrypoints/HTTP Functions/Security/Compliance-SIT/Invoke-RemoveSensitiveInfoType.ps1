Function Invoke-RemoveSensitiveInfoType {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Identity = $Request.Query.Identity ?? $Request.Body.Identity ?? $Request.Body.Name
    $FingerprintPackId = '00000000-0000-0000-0001-000000000001'

    try {
        $Sit = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance |
            Where-Object { $_.Name -eq $Identity -or $_.Id -eq $Identity -or $_.Identity -eq $Identity } | Select-Object -First 1
        if (-not $Sit) {
            throw "Sensitive Information Type '$Identity' not found."
        }
        if ($Sit.Publisher -like 'Microsoft*') {
            throw "SIT '$($Sit.Name)' is a Microsoft built-in and cannot be deleted."
        }

        # Regex/keyword SITs are their own rule package and must be removed at the package level - the
        # singular Remove-DlpSensitiveInformationType only removes a SIT from the shared fingerprint pack.
        if ($Sit.RulePackId -and $Sit.RulePackId -ne $FingerprintPackId -and $Sit.Type -ne 'Fingerprint') {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ Identity = $Sit.RulePackId } -Compliance -useSystemMailbox $true
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DlpSensitiveInformationType' -cmdParams @{ Identity = $Identity } -Compliance -useSystemMailbox $true
        }
        $Result = "Deleted Sensitive Information Type $Identity"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete Sensitive Information Type $Identity - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
