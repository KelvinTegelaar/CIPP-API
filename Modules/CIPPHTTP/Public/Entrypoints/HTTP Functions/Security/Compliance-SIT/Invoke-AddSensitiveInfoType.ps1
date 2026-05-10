Function Invoke-AddSensitiveInfoType {
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

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json

    # Build FileData from either advanced (FileDataBase64) or simple (Pattern) mode
    $FileDataBytes = $null
    if ($RawParams.FileDataBase64) {
        try {
            $FileDataBytes = [System.Convert]::FromBase64String($RawParams.FileDataBase64)
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "FileDataBase64 is not valid base64: $($_.Exception.Message)" }
                })
        }
    } elseif ($RawParams.Pattern) {
        $Xml = New-CIPPSitRulePackXml `
            -Name $RawParams.Name `
            -Description ($RawParams.Description ?? '') `
            -Pattern $RawParams.Pattern `
            -Confidence ([int]($RawParams.Confidence ?? 85)) `
            -PatternsProximity ([int]($RawParams.PatternsProximity ?? 300)) `
            -Locale ($RawParams.Locale ?? 'en-us') `
            -PublisherName ($RawParams.PublisherName ?? 'CIPP')
        $FileDataBytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Provide either 'Pattern' (simple mode) or 'FileDataBase64' (advanced mode)." }
            })
    }

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $ExistingSits = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object Name, Publisher } catch { @() }
            $Existing = $ExistingSits | Where-Object { $_.Name -eq $RawParams.Name } | Select-Object -First 1

            if ($Existing -and $Existing.Publisher -like 'Microsoft*') {
                "Sensitive Information Type $($RawParams.Name) is a built-in Microsoft type and cannot be modified — skipping in $TenantFilter."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Sensitive Information Type $($RawParams.Name) is a built-in Microsoft type and cannot be modified — skipping." -sev Warning
                continue
            }

            $CmdletParams = @{ FileData = $FileDataBytes }
            if (-not [string]::IsNullOrWhiteSpace([string]$RawParams.Description)) { $CmdletParams['Description'] = $RawParams.Description }
            if (-not [string]::IsNullOrWhiteSpace([string]$RawParams.Locale)) { $CmdletParams['Locale'] = $RawParams.Locale }

            if ($Existing) {
                $CmdletParams['Identity'] = $RawParams.Name
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpSensitiveInformationType' -cmdParams $CmdletParams -Compliance -useSystemMailbox $true
                "Updated Sensitive Information Type $($RawParams.Name) in $TenantFilter."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Updated Sensitive Information Type $($RawParams.Name)." -sev Info
            } else {
                $CmdletParams['Name'] = $RawParams.Name
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $CmdletParams -Compliance -useSystemMailbox $true
                "Created Sensitive Information Type $($RawParams.Name) in $TenantFilter."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Created Sensitive Information Type $($RawParams.Name)." -sev Info
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not deploy Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not deploy Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
