using namespace System.Net

Function Invoke-AddTransportRule {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $ExetutingUser = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExetutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, HasSenderOverride, ExceptIfHasSenderOverride, ExceptIfMessageContainsDataClassifications, MessageContainsDataClassifications

    $Tenants = ($Request.body.selectedTenants).value
    $Result = foreach ($tenantFilter in $tenants) {
        $Existing = New-ExoRequest -ErrorAction SilentlyContinue -tenantid $tenantFilter -cmdlet 'Get-TransportRule' -useSystemMailbox $true | Where-Object -Property Identity -EQ $RequestParams.name
        try {
            if ($Existing) {
                Write-Host 'Found existing'
                $RequestParams | Add-Member -NotePropertyValue $RequestParams.name -NotePropertyName Identity
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-TransportRule' -cmdParams ($RequestParams | Select-Object -Property * -ExcludeProperty UseLegacyRegex) -useSystemMailbox $true
                "Successfully set transport rule for $tenantFilter."
            } else {
                Write-Host 'Creating new'
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'New-TransportRule' -cmdParams $RequestParams -useSystemMailbox $true
                "Successfully created transport rule for $tenantFilter."
            }

            Write-LogMessage -user $ExetutingUser -API $APINAME -tenant $tenantFilter -message "Created transport rule for $($tenantFilter)" -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create transport rule for $($tenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -user $ExetutingUser -API $APINAME -tenant $tenantFilter -message "Could not create transport rule for $($tenantFilter). Error:$($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
