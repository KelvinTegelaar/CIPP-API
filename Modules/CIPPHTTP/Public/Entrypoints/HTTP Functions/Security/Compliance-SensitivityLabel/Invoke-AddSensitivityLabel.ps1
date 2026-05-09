Function Invoke-AddSensitivityLabel {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, comments, PolicyParams
    $PolicyParams = ($Request.Body.PowerShellCommand | ConvertFrom-Json).PolicyParams

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $LabelParams = $RequestParams | Select-Object -Property * -ExcludeProperty PolicyParams
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true

            if ($PolicyParams) {
                $PolicyHash = @{}
                $PolicyParams.PSObject.Properties | ForEach-Object { $PolicyHash[$_.Name] = $_.Value }
                if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                    $PolicyHash['Labels'] = @($RequestParams.Name)
                }
                if (-not $PolicyHash.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($PolicyHash['Name'])) {
                    $PolicyHash['Name'] = "$($RequestParams.Name) Policy"
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
            }

            "Successfully created sensitivity label $($RequestParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created sensitivity label $($RequestParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
