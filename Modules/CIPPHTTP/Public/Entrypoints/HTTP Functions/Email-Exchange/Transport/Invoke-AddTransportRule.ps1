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

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications

    # Remove null properties from payload
    $RequestParams.PSObject.Properties | Where-Object { $null -eq $_.Value } | ForEach-Object { $RequestParams.PSObject.Properties.Remove($_.Name) }

    $Tenants = ($Request.body.selectedTenants).value

    $AllowedTenants = Test-CippAccess -Request $Request -TenantList

    if ($AllowedTenants -ne 'AllTenants') {
        $AllTenants = Get-Tenants -IncludeErrors
        $AllowedTenantList = $AllTenants | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
    }

    $Result = foreach ($tenantFilter in $tenants) {
        $TenantParams = Resolve-CIPPTransportRuleTemplate -Template $RequestParams -TenantFilter $tenantFilter
        $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $tenantFilter -cmdlet 'Get-TransportRule' -useSystemMailbox $true | Where-Object -Property Identity -EQ $TenantParams.name
        try {
            if ($Existing) {
                Write-Host 'Found existing'
                $TenantParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
                # Set-TransportRule rejects Enabled; state changes go through Enable-/Disable-TransportRule.
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-TransportRule' -cmdParams ($TenantParams | Select-Object -Property * -ExcludeProperty UseLegacyRegex, Enabled) -useSystemMailbox $true
                if ($null -ne $TenantParams.Enabled) {
                    $StateCmdlet = if ("$($TenantParams.Enabled)" -in @('True', 'Enabled')) { 'Enable-TransportRule' } else { 'Disable-TransportRule' }
                    $null = New-ExoRequest -tenantid $tenantFilter -cmdlet $StateCmdlet -cmdParams @{ Identity = $Existing.Identity } -useSystemMailbox $true
                }
                "Successfully set transport rule for $tenantFilter."
            } else {
                Write-Host 'Creating new'
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'New-TransportRule' -cmdParams $TenantParams -useSystemMailbox $true
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
