function Invoke-AddCorporateDeviceIdentifier {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    .DESCRIPTION
        Uploads corporate device identifiers (manufacturer, model and serial number) for Windows Autopilot device preparation via the Graph importedDeviceIdentities API
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter

    $Result = try {
        $Devices = @($Request.Body.devicePrepData | Where-Object { $_ })
        if ($Devices.Count -eq 0) { throw 'No devices were provided to import.' }

        $Identities = foreach ($Device in $Devices) {
            $Manufacturer = "$($Device.manufacturer)".Trim()
            $Model = "$($Device.model)".Trim()
            $SerialNumber = "$($Device.serialNumber)".Trim()
            if (-not $Manufacturer -or -not $Model -or -not $SerialNumber) {
                throw "Every device requires a manufacturer, model and serial number. Offending entry: '$Manufacturer,$Model,$SerialNumber'"
            }
            @{
                importedDeviceIdentifier   = '{0},{1},{2}' -f $Manufacturer, $Model, $SerialNumber
                importedDeviceIdentityType = 'manufacturerModelSerial'
            }
        }

        $Body = ConvertTo-Json -Depth 10 -Compress -InputObject @{
            overwriteImportedDeviceIdentities = $Request.Body.overwriteExisting -eq $true
            importedDeviceIdentities          = @($Identities)
        }
        $ImportResult = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/importedDeviceIdentities/importDeviceIdentityList' -tenantid $TenantFilter -body $Body

        # The action returns one importedDeviceIdentityResult per identity, each with a
        # boolean status. Build one result per device so the frontend renders a bar each.
        $DeviceResults = foreach ($Identity in @($ImportResult.value)) {
            $IsError = $Identity.status -ne $true
            $Text = if ($IsError) {
                "$($Identity.importedDeviceIdentifier): failed to import. The identifier may already exist - enable 'Overwrite existing identifiers' to replace it."
            } else {
                "$($Identity.importedDeviceIdentifier): imported successfully"
            }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Corporate identifier import - $Text" -Sev $(if ($IsError) { 'Error' } else { 'Info' })
            [PSCustomObject]@{
                resultText = $Text
                state      = if ($IsError) { 'error' } else { 'success' }
                copyField  = $Identity.importedDeviceIdentifier
                details    = $Identity
            }
        }
        if (-not $DeviceResults) {
            $DeviceResults = [PSCustomObject]@{ resultText = "Submitted $(@($Identities).Count) corporate identifier(s) for import"; state = 'success' }
        }
        $StatusCode = [HttpStatusCode]::OK
        # Emit as the try block's value so the outer `$Result = try {...}` captures it.
        $DeviceResults
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        [PSCustomObject]@{
            resultText = "$($TenantFilter): Failed to import corporate device identifiers. $($ErrorMessage.NormalizedError)"
            state      = 'error'
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to import corporate device identifiers. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Result) }
        })
}
