function Invoke-AddTransportRule {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.TransportRule.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $ExecutingUser = $Request.Headers
    Write-LogMessage -Headers $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications

    $Tenants = ($Request.body.selectedTenants).value

    $AllowedTenants = Test-CippAccess -Request $Request -TenantList

    if ($AllowedTenants -ne 'AllTenants') {
        $AllTenants = Get-Tenants -IncludeErrors
        $AllowedTenantList = $AllTenants | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
    }

    $Result = foreach ($tenantFilter in $tenants) {
        $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $tenantFilter -cmdlet 'Get-TransportRule' -useSystemMailbox $true | Where-Object -Property Identity -EQ $RequestParams.name
        try {
            if ($Existing) {
                Write-Host 'Found existing'
                $RequestParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty UseLegacyRegex) -useSystemMailbox $true
                "Successfully set transport rule for $tenantFilter."
            } else {
                Write-Host 'Creating new'
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'New-TransportRule' -cmdParams $RequestParams -useSystemMailbox $true
                "Successfully created transport rule for $tenantFilter."
            }

            Write-LogMessage -Headers $ExecutingUser -API $APINAME -tenant $tenantFilter -message "Created transport rule for $($tenantFilter)" -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create transport rule for $($tenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -Headers $ExecutingUser -API $APINAME -tenant $tenantFilter -message "Could not create transport rule for $($tenantFilter). Error:$($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
