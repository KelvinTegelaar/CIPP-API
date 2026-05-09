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

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, comments

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            # New-DlpSensitiveInformationType expects FileData (byte array of XML rule pack) or specific simple parameters.
            # We pass through whatever the user provided as JSON parameters.
            $Params = @{}
            $RequestParams.PSObject.Properties | ForEach-Object {
                $Params[$_.Name] = $_.Value
            }

            # If the template provided XML rule pack content as base64, decode it for FileData
            if ($Params.ContainsKey('FileDataBase64') -and $Params['FileDataBase64']) {
                $Params['FileData'] = [System.Convert]::FromBase64String($Params['FileDataBase64'])
                $Params.Remove('FileDataBase64')
            }

            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $Params -Compliance -useSystemMailbox $true
            "Successfully created Sensitive Information Type $($RequestParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Sensitive Information Type $($RequestParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
