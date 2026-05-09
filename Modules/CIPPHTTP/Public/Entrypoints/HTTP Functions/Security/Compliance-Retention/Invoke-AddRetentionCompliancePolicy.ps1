Function Invoke-AddRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, comments, RuleParams
    $RuleParams = ($Request.Body.PowerShellCommand | ConvertFrom-Json).RuleParams

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $PolicyParams = $RequestParams | Select-Object -Property * -ExcludeProperty RuleParams
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionCompliancePolicy' -cmdParams $PolicyParams -Compliance -AsApp -useSystemMailbox $true

            if ($RuleParams) {
                $RuleHash = @{}
                $RuleParams.PSObject.Properties | ForEach-Object { $RuleHash[$_.Name] = $_.Value }
                $RuleHash['Policy'] = $RequestParams.Name
                if (-not $RuleHash.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($RuleHash['Name'])) {
                    $RuleHash['Name'] = "$($RequestParams.Name) Rule"
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionComplianceRule' -cmdParams $RuleHash -Compliance -AsApp -useSystemMailbox $true
            }

            "Successfully created Retention compliance policy $($RequestParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Retention compliance policy $($RequestParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
